import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/song.dart';
import '../models/lyric_section.dart';
import 'local_store.dart';
import 'sync_service.dart';

/// 온라인일 땐 Supabase(클라우드 공유 DB)와 동기화하여 팀원 모두에게 최신 곡 목록을
/// 보여주고, 오프라인일 땐 이미 캐시된 로컬(Hive) 데이터를 그대로 보여주는
/// 하이브리드 데이터 프로바이더.
///
/// 쓰기(등록/수정/삭제)는 온라인 상태에서만 허용된다. 오프라인에서 쓰기를 시도하면
/// [OfflineWriteException]을 던진다.
class OfflineWriteException implements Exception {
  final String message;
  OfflineWriteException([this.message = '오프라인 상태에서는 곡 등록·수정이 불가능합니다']);
  @override
  String toString() => message;
}

class SongProvider extends ChangeNotifier {
  final LocalStore _store = LocalStore.instance;
  final SyncService _sync = SyncService.instance;

  List<Song> _songs = [];
  bool _loading = true;
  bool _isOnline = true;
  bool _syncing = false;
  String? _syncStatus;
  DateTime? _lastSyncedAt;

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  List<Song> get songs => _songs;
  bool get loading => _loading;
  bool get isOnline => _isOnline;
  bool get syncing => _syncing;
  String? get syncStatus => _syncStatus;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  Future<void> init() async {
    await _store.init();
    _reload();
    _loading = false;
    notifyListeners();

    // 최초 온라인 상태 확인 + 동기화 시도 (실패해도 로컬 캐시로 계속 동작)
    _isOnline = await _sync.isOnline();
    notifyListeners();
    if (_isOnline) {
      unawaited(refresh());
    }

    // 연결 상태 변화를 실시간 감지 -> 온라인으로 복귀 시 자동 동기화
    _connSub = Connectivity().onConnectivityChanged.listen((results) async {
      final nowOnline = results.any((r) => r != ConnectivityResult.none);
      final wasOffline = !_isOnline;
      _isOnline = nowOnline;
      notifyListeners();
      if (nowOnline && wasOffline) {
        await refresh();
      }
    });
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  /// 서버와 수동/자동 동기화. 오프라인이면 조용히 스킵.
  Future<void> refresh() async {
    if (_syncing) return;
    _syncing = true;
    _syncStatus = '동기화 중...';
    notifyListeners();
    try {
      final ok = await _sync.syncFromCloud(
        onProgress: (s) {
          _syncStatus = s;
          notifyListeners();
        },
        onMetadataReady: (songs) {
          // 곡 메타데이터가 준비되는 즉시 화면을 갱신한다.
          // (악보 바이너리 다운로드는 백그라운드에서 계속 진행됨)
          _reload();
        },
      );
      _isOnline = ok || await _sync.isOnline();
      if (ok) {
        _lastSyncedAt = DateTime.now();
        _reload();
      }
    } finally {
      _syncing = false;
      _syncStatus = null;
      notifyListeners();
    }
  }

  Future<void> _ensureOnlineForWrite() async {
    final online = await _sync.isOnline();
    _isOnline = online;
    if (!online) {
      notifyListeners();
      throw OfflineWriteException();
    }
  }

  void _reload() {
    _songs = _store.getAllSongs();
    notifyListeners();
  }

  Song? byId(String id) {
    try {
      return _songs.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Song> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      final list = [..._songs];
      list.sort((a, b) => a.title.compareTo(b.title));
      return list;
    }
    final list = _songs.where((s) => s.searchText.contains(q)).toList();
    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  List<Song> byKey(String key) {
    final list = _songs.where((s) => s.keys.contains(key)).toList();
    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  Uint8List? getSheetBytes(String storageRef) => _store.getFile(storageRef);

  int get totalSheetsSizeBytes => _store.totalSheetsSizeBytes;

  /// 오프라인 상태에서도 볼 수 있도록 모든 악보 파일을 미리 다운로드한다.
  Future<int> cacheAllSheetsForOffline({
    void Function(int done, int total)? onProgress,
  }) async {
    await _ensureOnlineForWrite();
    final n = await _sync.cacheAllSheets(onProgress: onProgress);
    notifyListeners();
    return n;
  }

  /// 새 곡 생성 (id 반환) — 온라인 전용
  Future<String> createSong({
    required String title,
    required String composer,
    required List<String> tags,
    required SongLyrics lyrics,
  }) async {
    await _ensureOnlineForWrite();
    final song = await _sync.createSong(
      title: title,
      composer: composer,
      tags: tags,
      lyrics: lyrics,
    );
    _reload();
    return song.id;
  }

  Future<void> updateSongMeta({
    required String id,
    required String title,
    required String composer,
    required List<String> tags,
    required SongLyrics lyrics,
  }) async {
    await _ensureOnlineForWrite();
    final song = byId(id);
    if (song == null) return;
    song.title = title;
    song.composer = composer;
    song.tags = tags;
    song.lyrics = lyrics;
    await _sync.updateSongMeta(song);
    _reload();
  }

  Future<void> updateLyrics(String songId, SongLyrics lyrics) async {
    await _ensureOnlineForWrite();
    final song = byId(songId);
    if (song == null) return;
    song.lyrics = lyrics;
    await _sync.updateLyrics(songId, lyrics);
    await _store.saveSongRaw(song);
    _reload();
  }

  Future<void> deleteSong(String id) async {
    await _ensureOnlineForWrite();
    final song = byId(id);
    if (song == null) return;
    await _sync.deleteSong(song);
    _reload();
  }

  /// 악보 페이지 추가 / 교체 — 온라인 전용
  Future<void> addOrReplaceSheet({
    required String songId,
    String? existingSheetId,
    required String musicKey,
    required int ord,
    required Uint8List bytes,
    required String filename,
    required String mime,
  }) async {
    await _ensureOnlineForWrite();
    final song = byId(songId);
    if (song == null) return;

    String? existingStorageRef;
    if (existingSheetId != null) {
      final existing = song.sheets.firstWhere(
        (s) => s.id == existingSheetId,
        orElse: () => SheetMeta(
          id: '',
          musicKey: '',
          storageRef: '',
          filename: '',
          mime: '',
          size: 0,
          ord: 1,
        ),
      );
      if (existing.id.isNotEmpty) existingStorageRef = existing.storageRef;
    }

    final newSheet = await _sync.uploadSheet(
      songId: songId,
      existingSheetId: existingSheetId,
      existingStorageRef: existingStorageRef,
      musicKey: musicKey,
      ord: ord,
      bytes: bytes,
      filename: filename,
      mime: mime,
    );

    if (existingSheetId != null) {
      final idx = song.sheets.indexWhere((s) => s.id == existingSheetId);
      if (idx >= 0) {
        song.sheets[idx] = newSheet;
      } else {
        song.sheets.add(newSheet);
      }
    } else {
      song.sheets.add(newSheet);
    }
    await _store.saveSongRaw(song);
    _reload();
  }

  Future<void> removeSheet(String songId, String sheetId) async {
    await _ensureOnlineForWrite();
    final song = byId(songId);
    if (song == null) return;
    final idx = song.sheets.indexWhere((s) => s.id == sheetId);
    if (idx < 0) return;
    final sheet = song.sheets[idx];
    await _sync.deleteSheet(sheet);
    song.sheets.removeAt(idx);
    await _store.saveSongRaw(song);
    _reload();
  }

  Future<void> removeKey(String songId, String musicKey) async {
    await _ensureOnlineForWrite();
    final song = byId(songId);
    if (song == null) return;
    final toRemove = song.sheets.where((s) => s.musicKey == musicKey).toList();
    for (final s in toRemove) {
      await _sync.deleteSheet(s);
    }
    song.sheets.removeWhere((s) => s.musicKey == musicKey);
    await _store.saveSongRaw(song);
    _reload();
  }

  /// 로컬 캐시만 초기화 (서버 데이터는 그대로 유지됨). 다음 온라인 동기화 시 다시 채워진다.
  Future<void> clearLocalCache() async {
    await _store.clearAll();
    _reload();
    if (_isOnline) {
      await refresh();
    }
  }
}
