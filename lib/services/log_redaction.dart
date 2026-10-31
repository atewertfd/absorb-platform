// Absorb Plus: secrets the upstream log sanitizer lets through.
//
// Logging is on by default in betas, and a shared log file goes to whoever
// the user sends it to, so anything that can sign in as the user is masked
// before a line is written. LogService._sanitize runs this first, then its own
// URL and key=value masking.

final _loopbackSecret = RegExp(
  r'(https?://(?:127\.0\.0\.1|localhost|\[::1\])(?::\d+)?/)[A-Za-z0-9_-]{16,}',
  caseSensitive: false,
);
final _schemeUrl = RegExp(
  r'\b([a-zA-Z][a-zA-Z0-9+.-]*)://([^\s?#"\]]*)([?#][^\s"\]]*)?',
);
final _bearer = RegExp(r'\b(Bearer)\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);
final _jwt = RegExp(r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');
final _jsonSecret = RegExp(
  r'"(\w*token|\w*secret|password|\w*cookie|code)"\s*:\s*"[^"]*"',
  caseSensitive: false,
);
final _codeParam = RegExp(r'\b(code|sid)=(?!\*\*\*)[^\s&]+', caseSensitive: false);
/// `cookie: name=value` keeps the name and masks the value.
final _cookieValue = RegExp(
  r'\b(set-cookie|cookies?)(\s*[=:]\s*)([^\s=,;]+)=(?!\*\*\*)[^\s,;]+',
  caseSensitive: false,
);

/// Mask Bearer tokens, bare JWTs, JSON secret fields, `code=` / `sid=`
/// values, cookie values, the path secret of loopback media servers, and the
/// query or fragment of non-http URLs (app-link sign-in callbacks such as
/// `absorb://oauth?code=...`). http(s) queries are left to the URL sanitizer,
/// which keeps harmless parameters readable.
String redactLogSecrets(String message) {
  var s = message;
  s = s.replaceAllMapped(_loopbackSecret, (m) => '${m[1]}***');
  s = s.replaceAllMapped(_schemeUrl, (m) {
    final scheme = m[1]!.toLowerCase();
    final tail = m[3];
    if (scheme == 'http' || scheme == 'https' || tail == null) return m[0]!;
    return '${m[1]}://${m[2]}${tail[0]}***';
  });
  s = s.replaceAllMapped(_bearer, (m) => '${m[1]} ***');
  s = s.replaceAll(_jwt, '[jwt]');
  s = s.replaceAllMapped(_jsonSecret, (m) => '"${m[1]}":"***"');
  s = s.replaceAllMapped(_codeParam, (m) => '${m[1]}=***');
  s = s.replaceAllMapped(_cookieValue, (m) => '${m[1]}${m[2]}${m[3]}=***');
  return s;
}
