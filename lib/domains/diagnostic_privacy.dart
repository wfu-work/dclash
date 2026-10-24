/// Applies a conservative, presentation-safe redaction policy to diagnostic
/// strings before they are persisted, copied, or exported.
abstract final class DiagnosticPrivacy {
  static const redacted = '<redacted>';
  static const privateAddress = '<private-address>';

  static String sanitize(String value, {int maxLength = 512}) {
    var result = value.replaceAll('\u0000', '');
    result = result.replaceAllMapped(
      RegExp(r'https?://[^\s]+', caseSensitive: false),
      (match) => _sanitizeUrl(match.group(0)!),
    );
    result = result.replaceAllMapped(
      RegExp(r'\bbearer\s+[^\s,;]+', caseSensitive: false),
      (_) => 'Bearer $redacted',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'\b(authorization|bearer|token|secret|password|passwd|api[_-]?key|subscription)\s*([:=])\s*[^\s,;]+',
        caseSensitive: false,
      ),
      (match) => '${match.group(1)}${match.group(2)}$redacted',
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(?<![\d.])(?:10(?:\.\d{1,3}){3}|127(?:\.\d{1,3}){3}|192\.168(?:\.\d{1,3}){2}|172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?![\d.])',
      ),
      (_) => privateAddress,
    );
    result = result.replaceAllMapped(
      RegExp(
        r'(?<![\w:])(?:::1|fe[89ab][0-9a-f]{0,2}:[0-9a-f:]+)(?![\w:])',
        caseSensitive: false,
      ),
      (_) => privateAddress,
    );
    result = result.replaceAllMapped(
      RegExp(r'(?:/Users/|/home/|[A-Za-z]:\\)[^\s,;]+'),
      (_) => '<local-path>',
    );
    result = result.trim();
    return result.length <= maxLength
        ? result
        : '${result.substring(0, maxLength - 1)}…';
  }

  static String _sanitizeUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return '<invalid-url>';
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
    ).toString();
  }
}
