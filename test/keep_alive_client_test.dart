import 'package:absorb/utils/keep_alive_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('idle connections close before a Node server drops them (5 s)', () {
    expect(keepAliveIdle, lessThan(const Duration(seconds: 5)));
    final client = newKeepAliveClient();
    addTearDown(client.close);
  });
}
