import 'package:absorb/services/socket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => SocketService().disconnect());

  test('connecting again keeps the callbacks the caller set', () {
    final socket = SocketService();
    // Nothing listens on the discard port; the socket never authenticates,
    // which is all this needs.
    socket.connect('http://127.0.0.1:9', 'fixture-token');
    expect(socket.hasSocket, isTrue);

    void onProgress(Map<String, dynamic> _) {}
    void onFailed() {}
    socket.onProgressUpdated = onProgress;
    socket.onReconnectFailed = onFailed;

    // A headers-only server edit reconnects the active account.
    socket.connect('http://127.0.0.1:9', 'fixture-token',
        customHeaders: const {'X-Proxy': 'fixture'});

    expect(socket.hasSocket, isTrue);
    expect(socket.onProgressUpdated, same(onProgress));
    expect(socket.onReconnectFailed, same(onFailed));
  });

  test('disconnect still clears everything for logout', () {
    final socket = SocketService();
    socket.connect('http://127.0.0.1:9', 'fixture-token');
    socket.onProgressUpdated = (_) {};

    socket.disconnect();

    expect(socket.hasSocket, isFalse);
    expect(socket.onProgressUpdated, isNull);
  });
}
