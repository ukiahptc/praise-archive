import 'lyric_section.dart';

/// 악보 한 장(페이지)의 메타데이터. 실제 바이너리는 FileStorage 에 별도 저장된다.
class SheetMeta {
  final String id; // unique id, also used as stored file identifier
  String musicKey;
  String storageRef; // 로컬 저장소 참조값 (파일 경로 or 웹 스토리지 키)
  String filename; // 원본 파일명
  String mime;
  int size;
  int ord; // 1..3 페이지 순서

  SheetMeta({
    required this.id,
    required this.musicKey,
    required this.storageRef,
    required this.filename,
    required this.mime,
    required this.size,
    required this.ord,
  });

  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  Map<String, dynamic> toMap() => {
    'id': id,
    'musicKey': musicKey,
    'storageRef': storageRef,
    'filename': filename,
    'mime': mime,
    'size': size,
    'ord': ord,
  };

  factory SheetMeta.fromMap(Map map) => SheetMeta(
    id: map['id']?.toString() ?? '',
    musicKey: map['musicKey']?.toString() ?? '',
    storageRef: map['storageRef']?.toString() ?? '',
    filename: map['filename']?.toString() ?? '',
    mime: map['mime']?.toString() ?? '',
    size: (map['size'] is int)
        ? map['size'] as int
        : int.tryParse('${map['size']}') ?? 0,
    ord: (map['ord'] is int)
        ? map['ord'] as int
        : int.tryParse('${map['ord']}') ?? 1,
  );

  /// Supabase `sheets` 테이블 row(jsonb 아님, 컬럼: music_key, file_path 등)로부터 파싱
  factory SheetMeta.fromSupabaseMap(Map map) => SheetMeta(
    id: map['id']?.toString() ?? '',
    musicKey: map['music_key']?.toString() ?? '',
    storageRef: map['file_path']?.toString() ?? '',
    filename: map['filename']?.toString() ?? '',
    mime: map['mime']?.toString() ?? 'application/octet-stream',
    size: (map['size'] is int)
        ? map['size'] as int
        : int.tryParse('${map['size']}') ?? 0,
    ord: (map['ord'] is int)
        ? map['ord'] as int
        : int.tryParse('${map['ord']}') ?? 1,
  );

  /// Supabase `sheets` 테이블에 insert/update 할 때 사용하는 맵 (song_id는 호출측에서 추가)
  Map<String, dynamic> toSupabaseMap() => {
    'music_key': musicKey,
    'file_path': storageRef,
    'filename': filename,
    'mime': mime,
    'size': size,
    'ord': ord,
  };
}

class Song {
  final String id;
  String title;
  String composer;
  List<String> tags;
  SongLyrics lyrics;
  List<SheetMeta> sheets;
  DateTime createdAt;
  DateTime updatedAt;

  Song({
    required this.id,
    required this.title,
    this.composer = '',
    List<String>? tags,
    SongLyrics? lyrics,
    List<SheetMeta>? sheets,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : tags = tags ?? [],
       lyrics = lyrics ?? SongLyrics(),
       sheets = sheets ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  List<String> get keys {
    final set = <String>{};
    for (final s in sheets) {
      set.add(s.musicKey);
    }
    final list = set.toList();
    return list;
  }

  List<SheetMeta> pagesFor(String key) {
    final list = sheets.where((s) => s.musicKey == key).toList();
    list.sort((a, b) => a.ord.compareTo(b.ord));
    return list;
  }

  String get searchText =>
      ('$title $composer ${tags.join(' ')} ${lyrics.allText()}').toLowerCase();

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'composer': composer,
    'tags': tags,
    'lyrics': lyrics.toMap(),
    'sheets': sheets.map((s) => s.toMap()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Song.fromMap(Map map) {
    final sheetsRaw = map['sheets'];
    return Song(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      composer: map['composer']?.toString() ?? '',
      tags: (map['tags'] is List)
          ? (map['tags'] as List).map((e) => e.toString()).toList()
          : [],
      lyrics: SongLyrics.fromMap(map['lyrics']),
      sheets: sheetsRaw is List
          ? sheetsRaw
                .whereType<Object>()
                .map((e) => SheetMeta.fromMap(e as Map))
                .toList()
          : [],
      createdAt:
          DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Supabase `songs` 테이블 row(+embedded sheets)로부터 파싱
  /// 예: select('*, sheets(*)') 결과의 한 row
  factory Song.fromSupabaseMap(Map map) {
    final sheetsRaw = map['sheets'];
    return Song(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      composer: map['composer']?.toString() ?? '',
      tags: (map['tags'] is List)
          ? (map['tags'] as List).map((e) => e.toString()).toList()
          : [],
      lyrics: SongLyrics.fromMap(map['lyrics']),
      sheets: sheetsRaw is List
          ? sheetsRaw
                .whereType<Object>()
                .map((e) => SheetMeta.fromSupabaseMap(e as Map))
                .toList()
          : [],
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  /// Supabase `songs` 테이블에 insert/update 할 때 사용하는 맵 (sheets 제외, id 제외)
  Map<String, dynamic> toSupabaseMap() => {
    'title': title,
    'composer': composer,
    'tags': tags,
    'lyrics': lyrics.toMap(),
  };
}
