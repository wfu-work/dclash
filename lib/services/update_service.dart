import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../utils/bounded_http.dart';
import 'settings_service.dart';

class AppRelease {
  const AppRelease(this.version, this.url, this.notes);
  final String version, url, notes;

  static AppRelease parse(dynamic value) {
    if (value is! Map ||
        value['draft'] == true ||
        value['prerelease'] == true) {
      throw const FormatException('Invalid stable release');
    }
    final version = '${value['tag_name'] ?? ''}'.replaceFirst(
      RegExp(r'^[vV]'),
      '',
    );
    final url = Uri.tryParse('${value['html_url'] ?? ''}');
    final path = url?.pathSegments;
    if (AppVersion.tryParse(version) == null ||
        url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.port != 443 ||
        url.userInfo.isNotEmpty ||
        path == null ||
        path.length != 5 ||
        path.take(4).join('/') != 'wfu-work/dclash/releases/tag' ||
        path.last.replaceFirst(RegExp(r'^[vV]'), '') != version) {
      throw const FormatException('Invalid release version or download page');
    }
    final notes = '${value['body'] ?? ''}';
    return AppRelease(
      version,
      url.toString(),
      notes.length > 60000 ? notes.substring(0, 60000) : notes,
    );
  }
}

/// SemVer precedence, including numeric prerelease identifiers and build metadata.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts, this.prerelease);
  final List<int> parts;
  final List<String> prerelease;
  static AppVersion? tryParse(String value) {
    final match = RegExp(
      r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    ).firstMatch(value);
    if (match == null ||
        (match[4]?.split('.').any((id) => RegExp(r'^0[0-9]+$').hasMatch(id)) ??
            false)) {
      return null;
    }
    return AppVersion([
      for (var i = 1; i <= 3; i++) int.parse(match[i]!),
    ], match[4]?.split('.') ?? []);
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final order = parts[i].compareTo(other.parts[i]);
      if (order != 0) return order;
    }
    if (prerelease.isEmpty || other.prerelease.isEmpty) {
      return prerelease.isEmpty == other.prerelease.isEmpty
          ? 0
          : prerelease.isEmpty
          ? 1
          : -1;
    }
    for (var i = 0; i < prerelease.length && i < other.prerelease.length; i++) {
      final a = prerelease[i], b = other.prerelease[i];
      final an = int.tryParse(a), bn = int.tryParse(b);
      final order = an != null && bn != null
          ? an.compareTo(bn)
          : an != null
          ? -1
          : bn != null
          ? 1
          : a.compareTo(b);
      if (order != 0) return order;
    }
    return prerelease.length.compareTo(other.prerelease.length);
  }
}

class UpdateService extends GetxService {
  UpdateService(
    this.settings, {
    Future<dynamic> Function()? fetch,
    Future<String> Function()? version,
  }) : _fetch = fetch ?? _fetchRelease,
       _version =
           version ?? (() async => (await PackageInfo.fromPlatform()).version);
  final SettingsService settings;
  final Future<dynamic> Function() _fetch;
  final Future<String> Function() _version;
  final checking = false.obs;
  final noRelease = false.obs;
  bool _closed = false, _automatic = true;
  final currentVersion = ''.obs;
  final release = Rxn<AppRelease>();
  final error = RxnString();
  final checkedAt = Rxn<DateTime>();
  Worker? _worker;
  Timer? _timer;
  Future<void>? _pending;
  bool get available {
    final latest = release.value;
    final current = AppVersion.tryParse(currentVersion.value);
    return latest != null &&
        current != null &&
        AppVersion.tryParse(latest.version)!.compareTo(current) > 0;
  }

  static Future<dynamic> _fetchRelease() async {
    try {
      final response = await boundedHttp(
        Uri.parse(
          'https://api.github.com/repos/wfu-work/dclash/releases/latest',
        ),
        headers: {'Accept': 'application/vnd.github+json'},
        maxBytes: 512 * 1024,
      );
      return jsonDecode(utf8.decode(response.bytes));
    } on HttpException catch (error) {
      if (error.message == 'Server returned HTTP 404.') return null;
      rethrow;
    }
  }

  void initialize({bool automatic = true}) {
    if (_closed) return;
    _worker?.dispose();
    _automatic = automatic;
    var enabled = settings.fields['autoCheckUpdates'];
    _worker = ever(settings.fields, (_) {
      if (enabled == settings.fields['autoCheckUpdates']) return;
      enabled = settings.fields['autoCheckUpdates'];
      _schedule();
    });
    unawaited(
      _version()
          .then((value) {
            if (!_closed) currentVersion.value = value;
          })
          .catchError((Object failure) {
            if (!_closed) error.value = failure.toString();
          }),
    );
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_closed || !_automatic || settings.fields['autoCheckUpdates'] != true) {
      return;
    }
    final last = checkedAt.value;
    final elapsed = last == null
        ? Duration.zero
        : DateTime.now().difference(last);
    final delay = last == null || elapsed >= const Duration(days: 1)
        ? const Duration(seconds: 3)
        : const Duration(days: 1) - elapsed;
    _timer = Timer(delay, () => unawaited(check()));
  }

  Future<void> check() => _closed
      ? Future.value()
      : _pending ??= _check().whenComplete(() => _pending = null);
  Future<void> _check() async {
    checking.value = true;
    error.value = null;
    release.value = null;
    noRelease.value = false;
    try {
      final installed = await _version();
      if (_closed) return;
      currentVersion.value = installed;
      if (AppVersion.tryParse(currentVersion.value) == null) {
        throw const FormatException('Invalid installed version');
      }
      final payload = await _fetch();
      if (_closed) return;
      noRelease.value = payload == null;
      if (payload != null) release.value = AppRelease.parse(payload);
    } on Object catch (failure) {
      if (!_closed) error.value = failure.toString();
    } finally {
      if (!_closed) {
        checkedAt.value = DateTime.now();
        checking.value = false;
        _schedule();
      }
    }
  }

  @override
  void onClose() {
    _closed = true;
    _worker?.dispose();
    _timer?.cancel();
    super.onClose();
  }
}
