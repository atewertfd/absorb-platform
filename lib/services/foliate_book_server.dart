import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

/// Tiny loopback HTTP server that hosts the foliate-js reader. foliate-js needs
/// a real HTTP origin (ES modules + fetch), so assets can't be loaded via
/// file:// - they're served from the bundle here, plus the book file itself.
class FoliateBookServer {
  HttpServer? _server;
  File? _bookFile;
  String _bookMime = 'application/octet-stream';

  int get port => _server?.port ?? 0;

  Future<int> start({
    required File bookFile,
    required String mime,
  }) async {
    _bookFile = bookFile;
    _bookMime = mime;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle);
    return server.port;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    // Same-origin page only: no CORS header, so another website open in a
    // browser can't read the book, and a foreign Host or Origin (DNS
    // rebinding, a page probing loopback ports) is refused outright.
    if (!isOwnRequest(req.method, req.headers.host, req.headers.port,
        req.headers.value('origin'), port)) {
      res.statusCode = HttpStatus.forbidden;
      await res.close();
      return;
    }
    final path = req.uri.path;
    try {
      if (path == '/' || path == '/reader.html' || path == '/index.html') {
        await _serveAsset(res, 'assets/foliate/reader.html', 'text/html; charset=utf-8');
      } else if (path == '/reader-app.js') {
        await _serveAsset(res, 'assets/foliate/reader-app.js', 'text/javascript; charset=utf-8');
      } else if (path.startsWith('/foliate-js/')) {
        final rel = path.substring('/foliate-js/'.length);
        // Guard against path traversal before touching the bundle.
        if (rel.contains('..')) {
          res.statusCode = HttpStatus.forbidden;
          await res.close();
          return;
        }
        await _serveAsset(res, 'assets/foliate/foliate-js/$rel', 'text/javascript; charset=utf-8');
      } else if (path.startsWith('/book/')) {
        await _serveBook(res);
      } else {
        res.statusCode = HttpStatus.notFound;
        await res.close();
      }
    } catch (_) {
      try {
        res.statusCode = HttpStatus.internalServerError;
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _serveAsset(HttpResponse res, String assetKey, String contentType) async {
    final data = await rootBundle.load(assetKey);
    res.headers.contentType = ContentType.parse(contentType);
    res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    await res.close();
  }

  Future<void> _serveBook(HttpResponse res) async {
    final f = _bookFile;
    if (f == null || !f.existsSync()) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    res.headers.contentType = ContentType.parse(_bookMime);
    res.headers.set('Accept-Ranges', 'bytes');
    await f.openRead().pipe(res);
  }

  /// GET/HEAD addressed to this loopback server, from no other origin.
  static bool isOwnRequest(
      String method, String? host, int? hostPort, String? origin, int port) {
    if (method != 'GET' && method != 'HEAD') return false;
    const hosts = {'127.0.0.1', 'localhost'};
    if (host == null || !hosts.contains(host.toLowerCase()) || hostPort != port) {
      return false;
    }
    if (origin == null) return true;
    final o = Uri.tryParse(origin);
    return o != null &&
        o.scheme == 'http' &&
        hosts.contains(o.host.toLowerCase()) &&
        o.port == port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
