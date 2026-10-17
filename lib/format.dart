import 'dart:convert';

/// File name typed by the user, made safe for MediaStore (255 UTF-8 bytes per name,
/// so 200 leaves room for "_NN.jpg" and MediaStore's " (n)").
String sanitizeName(String raw, String fallback) {
  var s = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), '')
      .replaceFirst(RegExp(r'^[\s.]+'), '')
      .trim();
  var runes = s.runes.toList();
  while (utf8.encode(s).length > 200) {
    runes = runes.sublist(0, runes.length - 1);
    s = String.fromCharCodes(runes).trimRight();
  }
  return s.isEmpty ? fallback : s;
}

String _two(int n) => n.toString().padLeft(2, '0');

String defaultName(DateTime t) =>
    'Papyr_${t.year}${_two(t.month)}${_two(t.day)}_${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

String formatDate(DateTime t) => '${_two(t.day)}/${_two(t.month)}/${t.year} ${_two(t.hour)}:${_two(t.minute)}';

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1023.95 && i < units.length - 1) { // 1023.95 rounds to "1024,0"
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(1).replaceAll('.', ',')} ${units[i]}';
}
