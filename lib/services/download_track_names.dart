// Download names Windows can't store. `_sanitizePath` in download_service.dart
// already removes the characters every system rejects; these helpers fix only
// the names that are still invalid, so every name that works today comes out
// byte-identical. Downloads are found again by the paths saved with them, not
// by rebuilding names, so existing downloads are never affected.

/// Device names Windows reserves, alone or before an extension (`CON`,
/// `nul.txt`). Windows 10 refuses them anywhere in a path; Windows 11 still
/// refuses `NUL`.
const _windowsReservedStems = {
  'CON', 'PRN', 'AUX', 'NUL', //
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  'COM¹', 'COM²', 'COM³', 'LPT¹', 'LPT²', 'LPT³',
};

final _controlChars = RegExp(r'[\x00-\x1F]+');

/// The last step of a sanitized download name (a folder, a track's name
/// before its extension, an EPUB's file name). On Windows, control
/// characters become spaces and a reserved device name gets `_` after it
/// (`CON` -> `CON_`, `nul.txt` -> `nul_.txt`). Other systems keep the name.
String windowsSafeName(String name, {required bool windows}) {
  if (!windows) return name;
  var s = name;
  if (_controlChars.hasMatch(s)) {
    s = s.replaceAll(_controlChars, ' ').replaceAll(RegExp(r' {2,}'), ' ').trim();
    if (s.isEmpty) s = 'Unknown';
  }
  return _avoidReservedStem(s);
}

String _avoidReservedStem(String s) {
  final dot = s.indexOf('.');
  final stem = s.substring(0, dot < 0 ? s.length : dot).trimRight();
  if (!_windowsReservedStems.contains(stem.toUpperCase())) return s;
  return '${stem}_${s.substring(stem.length)}';
}

/// A book's download folder ("Author/Title"), with each folder name made
/// usable. `.` and `..` would point at another folder on every system and
/// become `Unknown`. On Windows a folder ending in more than one dot or
/// space (`Wait...`, `Vol 1 .`) can't be created, so that ending is dropped.
/// A single final dot (`Jr.`) works there and is kept.
String safeDownloadFolder(String nested, {required bool windows}) =>
    nested.split('/').map((s) => _safeFolderName(s, windows: windows)).join('/');

/// The id tail that tells two books with the same "Author/Title" folder
/// apart: the last 8 characters, or the whole id when it is shorter
/// (BookOrbit ids are short numbers, and substring threw a RangeError).
String folderIdSuffix(String itemId) =>
    itemId.length > 8 ? itemId.substring(itemId.length - 8) : itemId;

String _safeFolderName(String name, {required bool windows}) {
  if (name == '.' || name == '..') return 'Unknown';
  if (!windows) return name;
  final end = RegExp(r'[. ]+$').firstMatch(name);
  if (end == null || (end.end - end.start < 2 && end.start > 0)) return name;
  final s = name.substring(0, end.start);
  return s.isEmpty ? 'Unknown' : _avoidReservedStem(s);
}

/// Makes the on-disk names of one book's tracks unique.
///
/// Multi-disc books (`CD1/01.mp3`, `CD2/01.mp3`) and names that only differ
/// after the first 100 characters reduce to the same file name, which would
/// download two tracks into one file. A later clash gets its 1-based track
/// number in front (`002 - 01.mp3`). Names that don't clash are unchanged, so
/// existing downloads keep their layout. Compared case-insensitively because
/// Windows, Android shared storage and SAF folders are.
List<String> uniqueTrackFileNames(List<String> names) {
  final used = <String>{};
  final out = <String>[];
  for (var i = 0; i < names.length; i++) {
    var name = names[i];
    if (used.contains(name.toLowerCase())) {
      final prefix = (i + 1).toString().padLeft(3, '0');
      name = '$prefix - ${names[i]}';
      for (var n = 2; used.contains(name.toLowerCase()); n++) {
        name = '$prefix-$n - ${names[i]}';
      }
    }
    used.add(name.toLowerCase());
    out.add(name);
  }
  return out;
}
