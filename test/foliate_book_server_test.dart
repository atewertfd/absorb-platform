import 'dart:convert';
import 'dart:io';

import 'package:absorb/services/foliate_book_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// The MOBI reader's loopback server serves the reader page only: other
/// websites open in a browser must not be able to read the book.
void main() {
  late Directory dir;
  late FoliateBookServer server;
  late int port;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('foliate_server_test');
    final book = File('${dir.path}/book.mobi')..writeAsStringSync('BOOKDATA');
    server = FoliateBookServer();
    port = await server.start(bookFile: book, mime: 'application/x-mobipocket-ebook');
  });

  tearDown(() async {
    await server.stop();
    await dir.delete(recursive: true);
  });

  Future<HttpClientResponse> get(String path,
      {String? host, String? origin, String method = 'GET'}) async {
    final client = HttpClient();
    final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:$port$path'));
    if (host != null) req.headers.host = host;
    if (origin != null) req.headers.set('origin', origin);
    final res = await req.close();
    client.close();
    return res;
  }

  test('serves the book to its own page without a CORS header', () async {
    final res = await get('/book/book.mobi');
    expect(res.statusCode, 200);
    expect(await utf8.decodeStream(res), 'BOOKDATA');
    expect(res.headers.value('access-control-allow-origin'), isNull);

    final sameOrigin = await get('/book/book.mobi', origin: 'http://127.0.0.1:$port');
    expect(sameOrigin.statusCode, 200);
    await sameOrigin.drain<void>();
  });

  test('refuses other origins, foreign hosts and writes', () async {
    final crossSite = await get('/book/book.mobi', origin: 'https://evil.example');
    expect(crossSite.statusCode, HttpStatus.forbidden);
    await crossSite.drain<void>();

    final rebound = await get('/book/book.mobi', host: 'evil.example');
    expect(rebound.statusCode, HttpStatus.forbidden);
    await rebound.drain<void>();

    final post = await get('/book/book.mobi', method: 'POST');
    expect(post.statusCode, HttpStatus.forbidden);
    await post.drain<void>();
  });

  test('isOwnRequest checks method, host, port and origin', () {
    expect(FoliateBookServer.isOwnRequest('GET', '127.0.0.1', 5000, null, 5000), isTrue);
    expect(FoliateBookServer.isOwnRequest('HEAD', 'localhost', 5000, null, 5000), isTrue);
    expect(FoliateBookServer.isOwnRequest('GET', '127.0.0.1', 5001, null, 5000), isFalse);
    expect(FoliateBookServer.isOwnRequest('GET', '127.0.0.1', 5000, 'null', 5000), isFalse);
    expect(FoliateBookServer.isOwnRequest(
        'GET', '127.0.0.1', 5000, 'http://localhost:5000', 5000), isTrue);
  });
}
