import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:audio_service_win/audio_service_win.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('audio_service_win');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('missing cover does not request a literal null file', () async {
    await AudioServiceWin().setMediaItem(
      SetMediaItemRequest(
        mediaItem: const MediaItemMessage(id: 'book', title: 'Test book'),
      ),
    );
    expect(calls.single.method, 'setMediaItem');
    expect(calls.single.arguments['artUri'], '');
    expect(calls.single.arguments['title'], 'Test book');
  });

  test(
    'cached artwork takes precedence over its authenticated remote URL',
    () async {
      await AudioServiceWin().setMediaItem(
        SetMediaItemRequest(
          mediaItem: MediaItemMessage(
            id: 'book',
            title: 'Test book',
            artUri: Uri.parse('https://example.invalid/cover'),
            extras: {'artCacheFile': r'C:\cache\cover.jpg'},
          ),
        ),
      );
      expect(calls.single.arguments['artUri'], r'C:\cache\cover.jpg');
    },
  );

  test('uncached artwork retains its URI', () async {
    await AudioServiceWin().setMediaItem(
      SetMediaItemRequest(
        mediaItem: MediaItemMessage(
          id: 'book',
          title: 'Test book',
          artUri: Uri.parse('file:///C:/covers/book.jpg'),
        ),
      ),
    );
    expect(calls.single.arguments['artUri'], 'file:///C:/covers/book.jpg');
  });
}
