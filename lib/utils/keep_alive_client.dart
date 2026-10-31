import 'keep_alive_client_web.dart'
    if (dart.library.io) 'keep_alive_client_io.dart' as impl;

import 'package:http/http.dart' as http;

/// An HTTP client that reuses connections between requests. On native
/// platforms idle connections close after [keepAliveIdle], just under the
/// 5 s keep-alive timeout of Node servers such as Audiobookshelf, so a
/// request is never sent on a connection the server is about to drop. On web
/// the browser manages connections.
http.Client newKeepAliveClient() => impl.newKeepAliveClient(keepAliveIdle);

const keepAliveIdle = Duration(seconds: 4);
