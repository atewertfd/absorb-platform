import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Stand-in for dart:io's [Platform] in screens that also run on the web,
/// where dart:io's getters throw (which broke the Settings screen there).
///
/// Use it by changing only the import line of an upstream file:
/// `import 'dart:io' hide Platform;` plus an import of this file. Every
/// `Platform.isX` check then answers false on the web instead of throwing.
abstract final class Platform {
  static bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
  static bool get isIOS => !kIsWeb && io.Platform.isIOS;
  static bool get isWindows => !kIsWeb && io.Platform.isWindows;
  static bool get isLinux => !kIsWeb && io.Platform.isLinux;
  static bool get isMacOS => !kIsWeb && io.Platform.isMacOS;
}
