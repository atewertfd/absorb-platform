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
