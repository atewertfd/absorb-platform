import 'package:absorb/widgets/whats_new_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release tags always carry the build, stable releases included', () {
    // release.yml tags every release vX.Y.Z-N; odd patch = beta, even = stable.
    expect(whatsNewReleaseTag('1.12.1', 311), 'v1.12.1-311');
    expect(whatsNewReleaseTag('1.12.2', 320), 'v1.12.2-320');
  });
}
