import 'package:absorb/services/log_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJ1c2VySWQiOiJhYmMifQ.c2lnbmF0dXJlLXZhbHVl';

  test('masks Bearer tokens and keeps the scheme word', () {
    final out = redactLogSecrets('Authorization: Bearer opaque-token_123');
    expect(out, 'Authorization: Bearer ***');
  });

  test('masks bare JWTs and JSON secret fields', () {
    expect(redactLogSecrets('refresh reply $jwt'), 'refresh reply [jwt]');
    final json = redactLogSecrets(
        '{"user":{"accessToken":"abc","refreshToken":"def","id":"u1"}}');
    expect(json, contains('"accessToken":"***"'));
    expect(json, contains('"refreshToken":"***"'));
    expect(json, contains('"id":"u1"'));
  });

  test('masks code= and session cookie values', () {
    expect(redactLogSecrets('callback code=abc123&state=x'),
        'callback code=***&state=x');
    expect(redactLogSecrets('Captured raw cookie: connect.sid=s%3Aabc.def'),
        isNot(contains('s%3Aabc')));
    expect(redactLogSecrets('cookie: oidc_session=secret-value'),
        'cookie: oidc_session=***');
    // Cookie names alone and status codes stay readable.
    expect(redactLogSecrets('Captured cookie: connect.sid'),
        'Captured cookie: connect.sid');
    expect(redactLogSecrets('statusCode=401 exitCode=0'),
        'statusCode=401 exitCode=0');
  });

  test('masks the query of app-link callbacks, not of web URLs', () {
    expect(
      redactLogSecrets('Custom Tab returned: absorb://oauth?code=abc&state=def'),
      'Custom Tab returned: absorb://oauth?***',
    );
    expect(redactLogSecrets('opened absorbplus://login#access_token=xyz'),
        'opened absorbplus://login#***');
    expect(redactLogSecrets('GET https://abs.example/api/items?limit=5'),
        'GET https://abs.example/api/items?limit=5');
    expect(redactLogSecrets('file:///C:/Users/me/book.m4b'),
        'file:///C:/Users/me/book.m4b');
  });

  test('masks the path secret of loopback media servers', () {
    expect(
      redactLogSecrets(
          'cover http://127.0.0.1:41234/AbCdEf0123456789_-xyzQ/cover/42'),
      'cover http://127.0.0.1:41234/***/cover/42',
    );
    // Short readable first segments are not secrets.
    expect(redactLogSecrets('http://127.0.0.1:8080/book/a.mobi'),
        'http://127.0.0.1:8080/book/a.mobi');
  });
}
