import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class BoundedResponse {
  const BoundedResponse(this.bytes, this.headers);
  final Uint8List bytes;
  final Map<String, String> headers;
}

Uri validateHttpUri(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty) {
    throw const FormatException('Enter a valid HTTP or HTTPS URL.');
  }
  return uri.replace(fragment: '');
}

bool _sameOrigin(Uri a, Uri b) =>
    a.scheme == b.scheme &&
    a.host.toLowerCase() == b.host.toLowerCase() &&
    a.port == b.port;

/// Local subscriptions are supported. Redirects never downgrade TLS or forward
/// authentication to another origin, and the entire transfer is time bounded.
Future<BoundedResponse> boundedHttp(
  Uri uri, {
  String method = 'GET',
  List<int>? body,
  Map<String, String> headers = const {},
  int maxBytes = 16 * 1024 * 1024,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    return await (() async {
      var current = uri;
      final requestHeaders = <String, String>{
        'User-Agent': 'dclash/0.1',
        ...headers,
      };
      if (uri.userInfo.isNotEmpty &&
          !requestHeaders.keys.any(
            (key) => key.toLowerCase() == 'authorization',
          )) {
        requestHeaders['Authorization'] =
            'Basic ${base64Encode(utf8.encode(Uri.decodeComponent(uri.userInfo)))}';
      }
      for (var redirect = 0; redirect <= 5; redirect++) {
        final request = await client.openUrl(
          method,
          current.replace(userInfo: ''),
        );
        request.followRedirects = false;
        requestHeaders.forEach(request.headers.set);
        if (body != null) {
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirect == 5) {
            throw const HttpException(
              'Too many redirects or missing redirect location.',
            );
          }
          final next = validateHttpUri(current.resolve(location).toString());
          if (current.scheme == 'https' && next.scheme != 'https') {
            throw const HttpException('HTTPS redirect downgrade was blocked.');
          }
          final authenticated = requestHeaders.keys.any(
            (key) =>
                key.toLowerCase() == 'authorization' ||
                key.toLowerCase() == 'cookie',
          );
          if (!_sameOrigin(current, next) &&
              (authenticated || next.userInfo.isNotEmpty || method != 'GET')) {
            throw const HttpException(
              'Authenticated redirect to another server was blocked.',
            );
          }
          if (next.userInfo.isNotEmpty && next.userInfo != current.userInfo) {
            throw const HttpException('Redirect changed URL credentials.');
          }
          current = next;
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('Server returned HTTP ${response.statusCode}.');
        }
        if (response.contentLength > maxBytes) {
          throw const FormatException('Download exceeds the allowed size.');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const FormatException('Download exceeds the allowed size.');
          }
          bytes.add(chunk);
        }
        final responseHeaders = <String, String>{};
        response.headers.forEach(
          (name, values) =>
              responseHeaders[name.toLowerCase()] = values.join(', '),
        );
        return BoundedResponse(bytes.takeBytes(), responseHeaders);
      }
      throw const HttpException('Too many redirects.');
    })().timeout(timeout);
  } on TimeoutException {
    throw const HttpException('The server did not respond within 30 seconds.');
  } finally {
    client.close(force: true);
  }
}
