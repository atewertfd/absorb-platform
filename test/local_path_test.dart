import 'package:absorb/utils/local_path.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugLocalPathIsWebOverride = null);

  test('POSIX, Windows drive, UNC and file:// paths are local', () {
    for (final p in [
      '/data/user/0/app/cover.jpg',
      r'C:\Users\me\Documents\Absorb\book\cover.jpg',
      'c:/Users/me/cover.jpg',
      r'\\nas\share\cover.jpg',
      'file:///C:/Users/me/cover.jpg',
    ]) {
      expect(isLocalFilePath(p), isTrue, reason: p);
      expect(isLocalCoverPath(p), isTrue, reason: p);
    }
  });

  test('URLs and empty values are not local', () {
    for (final p in [
      null,
      '',
      'https://abs.example/api/items/1/cover?width=400',
      'http://192.168.1.2:13378/api/items/1/cover',
      'content://media/cover',
      'C:',
      'cover.jpg',
    ]) {
      expect(isLocalFilePath(p), isFalse, reason: '$p');
    }
  });

  test('never local on the web', () {
    debugLocalPathIsWebOverride = true;
    expect(isLocalFilePath('/cover.jpg'), isFalse);
    expect(isLocalFilePath(r'C:\cover.jpg'), isFalse);
  });

  test('localFilePath turns a file URI into a path', () {
    expect(localFilePath('/a/b.jpg'), '/a/b.jpg');
    expect(localFilePath(r'C:\a\b.jpg'), r'C:\a\b.jpg');
    expect(localFilePath('file:///tmp/b.jpg'), isNot(startsWith('file:')));
  });
}
