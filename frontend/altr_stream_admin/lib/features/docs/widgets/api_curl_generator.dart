/// Utility to generate reproducible cURL commands for an API request
class ApiCurlGenerator {
  /// Generate a multi-line formatted cURL command
  static String generate({
    required String method,
    required String url,
    Map<String, String>? headers,
    String? body,
  }) {
    final buffer = StringBuffer();
    final normalizedMethod = method.toUpperCase().trim();

    buffer.writeln('curl -X $normalizedMethod "$url" \\');

    // Default headers if none specified
    final effectiveHeaders = <String, String>{
      'Accept': 'application/json',
      ...?headers,
    };

    if (body != null && body.trim().isNotEmpty && normalizedMethod != 'GET' && normalizedMethod != 'HEAD') {
      effectiveHeaders['Content-Type'] = 'application/json';
    }

    effectiveHeaders.forEach((k, v) {
      buffer.writeln('  -H "$k: $v" \\');
    });

    if (body != null && body.trim().isNotEmpty && normalizedMethod != 'GET' && normalizedMethod != 'HEAD') {
      // Escape single quotes for bash single-quoted string
      final escapedBody = body.replaceAll("'", "'\\''");
      buffer.write("  -d '$escapedBody'");
    } else {
      // Remove trailing backslash from the last header line
      final str = buffer.toString().trimRight();
      if (str.endsWith('\\')) {
        return str.substring(0, str.length - 1).trimRight();
      }
      return str;
    }

    return buffer.toString().trimRight();
  }
}
