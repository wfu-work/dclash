import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:get/get.dart';

import '../app/widgets/app_widgets.dart';
import 'profile_service.dart';

class LinkService extends GetxService {
  LinkService(this.profiles);
  final ProfileService profiles;
  final _links = AppLinks();
  StreamSubscription<Uri>? _subscription;
  bool _handling = false;

  @override
  void onReady() {
    super.onReady();
    _subscription = _links.uriLinkStream.listen(
      (uri) => unawaited(_handle(uri)),
      onError: (Object error) {
        final context = Get.context;
        if (context != null && context.mounted) showAppError(context, error);
      },
    );
    unawaited(_initial());
  }

  Future<void> _initial() async {
    try {
      final uri = await _links.getInitialLink();
      if (uri != null) await _handle(uri);
    } on Object catch (error) {
      final context = Get.context;
      if (context != null && context.mounted) showAppError(context, error);
    }
  }

  Future<void> _handle(Uri uri) async {
    if (_handling ||
        ![
          'clash',
          'clashmeta',
          'flclash',
          'cloudrift',
          'dclash',
        ].contains(uri.scheme)) {
      return;
    }
    final context = Get.context;
    if (context == null) return;
    _handling = true;
    try {
      final confirmed = await AppDialogs.confirm(
        context,
        title: 'import'.tr,
        message:
            '${'profiles'.tr}: ${Uri.tryParse(uri.queryParameters['url'] ?? '')?.host ?? uri.host}',
      );
      if (confirmed) {
        final url = uri.queryParameters['url'];
        if (uri.host != 'install-config' || url == null) {
          throw const FormatException('Unsupported profile import link.');
        }
        await profiles.importUrl(url, name: uri.queryParameters['name']);
      }
    } on Object catch (error) {
      if (context.mounted) showAppError(context, error);
    } finally {
      _handling = false;
    }
  }

  @override
  void onClose() {
    unawaited(_subscription?.cancel());
    super.onClose();
  }
}
