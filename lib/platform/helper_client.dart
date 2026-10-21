import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'core_rpc.dart';

class HelperClient {
  HelperClient(this.directory) {
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionTimeout = const Duration(seconds: 5);
    if (Platform.isLinux) {
      _http.connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(
            InternetAddress(
              '/run/dclash/helper.sock',
              type: InternetAddressType.unix,
            ),
            0,
          );
    }
  }
  final String directory;
  final HttpClient _http = HttpClient();
  int _port = 47991;

  Future<void> start(String session, String address) async {
    if (Platform.isWindows) {
      final registry = await Process.run('reg', [
        'query',
        r'HKLM\SYSTEM\CurrentControlSet\Services\DClashHelperService\Runtime',
        '/v',
        'Port',
      ]);
      if (registry.exitCode == 0) {
        final match = RegExp(
          r'Port\s+REG_DWORD\s+(0x[0-9a-fA-F]+|\d+)',
        ).firstMatch('${registry.stdout}');
        if (match != null) _port = int.parse(match.group(1)!);
      }
    }
    final manifest = jsonDecode(
      await File(p.join(directory, 'manifest.json')).readAsString(),
    );
    final hash = manifest is Map ? manifest['coreSha256'] : null;
    if (hash is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const CoreException(
        'helper_manifest',
        'Core manifest is missing or invalid',
      );
    }
    final health = await _request('GET', '/ping', query: {'coreSha256': hash});
    final helperPath = p.join(
      directory,
      Platform.isWindows ? 'DClashHelperService.exe' : 'DClashHelperService',
    );
    if (!p.equals(p.normalize(health), p.normalize(helperPath))) {
      throw const CoreException(
        'helper_identity',
        'The installed helper does not belong to this DClash installation',
      );
    }
    final reply = jsonDecode(
      await _request(
        'POST',
        '/start',
        body: {'sessionId': session, 'address': address},
      ),
    );
    if (reply is! Map ||
        reply['sessionId'] != session ||
        reply['pid'] is! num) {
      throw const CoreException(
        'helper_start',
        'The helper returned an invalid process lease',
      );
    }
  }

  Future<void> stop(String session) async {
    final reply = jsonDecode(
      await _request('POST', '/stop', body: {'sessionId': session}),
    );
    if (reply is! Map ||
        reply['sessionId'] != session ||
        reply['stopped'] != true) {
      throw const CoreException(
        'helper_stop',
        'The helper could not confirm stopping this session',
      );
    }
  }

  Future<String> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    try {
      final uri = Uri.http(
        Platform.isLinux ? 'DClashHelperService' : '127.0.0.1:$_port',
        path,
        query,
      );
      final request = await _http
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 5));
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final text = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != HttpStatus.ok) {
        throw CoreException(
          'helper_request',
          'DClash helper ${response.statusCode}: $text',
        );
      }
      if (response.headers.value('x-dclash-helper-protocol') !=
          (Platform.isWindows ? '8' : '6')) {
        throw const CoreException(
          'helper_version',
          'The installed DClash helper protocol is incompatible',
        );
      }
      return text.trim();
    } on SocketException {
      throw const CoreException(
        'helper_missing',
        'Install the DClash privileged helper before enabling TUN mode',
      );
    }
  }

  void close() => _http.close(force: true);
  static Future<void> manage(
    String directory, {
    required bool uninstall,
  }) async {
    if (!Platform.isLinux && !Platform.isWindows) {
      throw const CoreException(
        'unsupported',
        'A privileged helper is available on Linux and Windows',
      );
    }
    final executable = p.join(
      directory,
      Platform.isWindows ? 'DClashHelperService.exe' : 'DClashHelperService',
    );
    if (!await File(executable).exists()) {
      throw const CoreException(
        'helper_missing',
        'The bundled DClash helper is missing',
      );
    }
    final command = uninstall ? 'uninstall' : 'install';
    final ProcessResult result;
    if (Platform.isLinux) {
      result = await Process.run('pkexec', [executable, command]);
    } else {
      final quotedPath = "'${executable.replaceAll("'", "''")}'";
      final arguments = uninstall
          ? "@('uninstall')"
          : "@('install','--owner-pid','$pid')";
      result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '\$dclashInstaller = Start-Process -FilePath $quotedPath '
            '-ArgumentList $arguments '
            '-Verb RunAs -Wait -PassThru; exit \$dclashInstaller.ExitCode',
      ]);
    }
    if (result.exitCode != 0) {
      throw CoreException(
        'helper_install',
        'DClash helper $command failed: ${result.stderr}',
      );
    }
  }
}
