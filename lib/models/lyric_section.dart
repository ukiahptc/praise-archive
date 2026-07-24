class LyricSection {
  final String id;
  final String type; // Verse, Chorus, Bridge ...
  String label;
  String text;

  LyricSection({
    required this.id,
    required this.type,
    required this.label,
    required this.text,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'label': label,
    'text': text,
  };

  factory LyricSection.fromMap(Map map) {
    return LyricSection(
      id: map['id']?.toString() ?? '',
      type: map['type']?.toString() ?? 'Verse',
      label: map['label']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
    );
  }

  LyricSection copyWith({String? label, String? text}) => LyricSection(
    id: id,
    type: type,
    label: label ?? this.label,
    text: text ?? this.text,
  );
}

class SongLyrics {
  List<LyricSection> sections;
  List<String>
  arrangement; // list of section ids, order matters, duplicates allowed

  SongLyrics({List<LyricSection>? sections, List<String>? arrangement})
    : sections = sections ?? [],
      arrangement = arrangement ?? [];

  Map<String, dynamic> toMap() => {
    'sections': sections.map((s) => s.toMap()).toList(),
    'arrangement': arrangement,
  };

  factory SongLyrics.fromMap(dynamic map) {
    if (map == null || map is! Map) return SongLyrics();
    final sectionsRaw = map['sections'];
    final arrRaw = map['arrangement'];
    return SongLyrics(
      sections: sectionsRaw is List
          ? sectionsRaw
                .whereType<Object>()
                .map((e) => LyricSection.fromMap(e as Map))
                .toList()
          : [],
      arrangement: arrRaw is List
          ? arrRaw.map((e) => e.toString()).toList()
          : [],
    );
  }

  SongLyrics clone() => SongLyrics.fromMap(toMap());

  String allText() => sections.map((s) => s.text).join(' ');

  String buildCopy({required bool withLabels}) {
    final map = {for (final s in sections) s.id: s};
    final seq = arrangement.isNotEmpty
        ? arrangement
        : sections.map((s) => s.id).toList();
    final parts = <String>[];
    for (final id in seq) {
      final s = map[id];
      if (s == null) continue;
      final body = s.text.trim();
      parts.add(withLabels ? '[${s.label}]\n$body' : body);
    }
    return parts.join('\n\n');
  }
}
