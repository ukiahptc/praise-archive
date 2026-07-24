import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/song.dart';

/// 완전 오프라인 로컬 저장소.
/// 곡 메타데이터(Hive box 'songs') + 악보 바이너리(Hive box 'sheet_files')를
/// 모두 기기 로컬에 저장한다. 네트워크 연결이 전혀 필요 없다.
class LocalStore {
  static const String songsBoxName = 'songs_v1';
  static const String filesBoxName = 'sheet_files_v1';

  late Box<Map> _songsBox;
  late Box<Uint8List> _filesBox;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  static final LocalStore instance = LocalStore._internal();
  LocalStore._internal();

  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();
    _songsBox = await Hive.openBox<Map>(songsBoxName);
    _filesBox = await Hive.openBox<Uint8List>(filesBoxName);
    _initialized = true;
  }

  // ── 곡 CRUD ──
  List<Song> getAllSongs() {
    final list = <Song>[];
    for (final key in _songsBox.keys) {
      final raw = _songsBox.get(key);
      if (raw != null) {
        try {
          list.add(Song.fromMap(Map<String, dynamic>.from(raw)));
        } catch (_) {}
      }
    }
    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  Future<void> saveSong(Song song) async {
    song.updatedAt = DateTime.now();
    await _songsBox.put(song.id, song.toMap());
  }

  /// 서버(Supabase)로부터 받은 Song을 그대로 캐시에 저장한다.
  /// (updatedAt을 현재 시각으로 덮어쓰지 않고 서버 값을 그대로 보존)
  Future<void> saveSongRaw(Song song) async {
    await _songsBox.put(song.id, song.toMap());
  }

  Future<void> deleteSong(Song song) async {
    for (final sheet in song.sheets) {
      await _filesBox.delete(sheet.storageRef);
    }
    await _songsBox.delete(song.id);
  }

  // ── 악보 파일 바이너리 ──
  Future<void> putFile(String storageRef, Uint8List bytes) async {
    await _filesBox.put(storageRef, bytes);
  }

  Uint8List? getFile(String storageRef) {
    return _filesBox.get(storageRef);
  }

  Future<void> deleteFile(String storageRef) async {
    await _filesBox.delete(storageRef);
  }

  // ── 통계 ──
  int get songCount => _songsBox.length;

  int get totalSheetsSizeBytes {
    int total = 0;
    for (final key in _filesBox.keys) {
      final v = _filesBox.get(key);
      if (v != null) total += v.length;
    }
    return total;
  }

  Future<void> clearAll() async {
    await _songsBox.clear();
    await _filesBox.clear();
  }
}
