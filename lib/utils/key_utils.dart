/// 음악 키 관련 유틸리티
const List<String> kKeyOptions = [
  'C',
  'C#',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
  'Cm',
  'C#m',
  'Dm',
  'Ebm',
  'Em',
  'Fm',
  'F#m',
  'Gm',
  'Abm',
  'Am',
  'Bbm',
  'Bm',
];

const List<String> kPartTypes = [
  'Verse',
  'Pre-Chorus',
  'Chorus',
  'Bridge',
  'Intro',
  'Tag',
  'Ending',
];

List<String> sortKeys(Iterable<String> keys) {
  final list = keys.toList();
  list.sort((a, b) => kKeyOptions.indexOf(a).compareTo(kKeyOptions.indexOf(b)));
  return list;
}

/// 화면 표시용 (♭ ♯ 기호로 변환)
String prettyKey(String k) {
  return k.replaceAll('b', '\u266d').replaceAll('#', '\u266f');
}

/// 검색어가 키 이름과 일치하는지 확인 (예: "eb", "Am" 등)
String? parseKeyQuery(String query) {
  if (query.trim().isEmpty) return null;
  final n = query
      .trim()
      .replaceAll('♭', 'b')
      .replaceAll('♯', '#')
      .toLowerCase();
  for (final k in kKeyOptions) {
    if (k.toLowerCase() == n) return k;
  }
  return null;
}

String autoLabel(String type, List<String> existingTypes) {
  final n = existingTypes.where((t) => t == type).length + 1;
  if (type == 'Verse') return 'Verse $n';
  return n == 1 ? type : '$type $n';
}

String fmtSize(int? bytes) {
  if (bytes == null) return '';
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(0)}KB';
  return '${(bytes / 1048576).toStringAsFixed(1)}MB';
}

String safeFileName(String s) {
  return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
}
