import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/song.dart';
import 'local_store.dart';

/// Supabase(클라우드 공유 DB) ↔ Hive(로컬 오프라인 캐시) 동기화를 담당한다.
///
/// 설계 원칙:
/// - 온라인일 때: Supabase에서 최신 songs+sheets 메타데이터를 가져와 로컬 캐시를 갱신하고,
///   아직 다운로드되지 않은 악보 파일만 Storage에서 내려받아 캐시에 저장한다.
/// - 오프라인일 때: 동기화를 시도하지 않고 로컬 캐시를 그대로 사용한다.
/// - 쓰기(등록/수정/삭제)는 온라인 상태에서만 허용되며, Supabase에 먼저 반영한 뒤
///   로컬 캐시를 갱신한다.
class SyncService {
  SyncService._internal();
  static final SyncService instance = SyncService._internal();

  final LocalStore _store = LocalStore.instance;
  final Connectivity _connectivity = Connectivity();

  SupabaseClient get _client => Supabase.instance.client;

  /// 현재 인터넷(네트워크) 연결 여부를 확인한다.
  /// 참고: 실제 기기 연결 상태(wifi/mobile on)만 확인하며, 서버 도달 가능성까지
  /// 보장하지는 않는다 (완전한 오프라인 감지를 위해선 실제 요청 실패 시 fallback 처리도 함께 함).
  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true; // 확인 불가 시 시도는 해보도록 낙관적으로 처리
    }
  }

  /// Supabase에서 songs + sheets(embedded)를 가져와 로컬 캐시(Hive)에 반영한다.
  ///
  /// 중요: 곡 목록(메타데이터)은 서버에서 받아오는 즉시 로컬 캐시에 저장하고
  /// [onMetadataReady]로 알려서 화면에 바로 표시되도록 한다. 악보 이미지/PDF
  /// 바이너리는 그 이후 백그라운드에서 순차적으로 다운로드하므로, 곡이 많거나
  /// 네트워크가 느려도 곡 목록 자체는 즉시 뜬다.
  ///
  /// 반환값: 성공 여부 (네트워크 오류 시 false, 예외를 던지지 않음)
  Future<bool> syncFromCloud({
    void Function(String status)? onProgress,
    void Function(List<Song> songs)? onMetadataReady,
  }) async {
    if (!await isOnline()) return false;
    try {
      onProgress?.call('서버에서 곡 목록을 가져오는 중...');
      final List<dynamic> rows = await _client
          .from('songs')
          .select('*, sheets(*)')
          .order('title');

      final songs = rows
          .whereType<Map>()
          .map((m) => Song.fromSupabaseMap(m))
          .toList();

      // 서버에 없는(삭제된) 곡은 로컬에서도 제거
      final serverIds = songs.map((s) => s.id).toSet();
      final localSongs = _store.getAllSongs();
      for (final local in localSongs) {
        if (!serverIds.contains(local.id)) {
          await _store.deleteSong(local);
        }
      }

      // 메타데이터부터 즉시 캐시에 저장 -> 곡 목록이 바로 화면에 뜬다.
      for (final song in songs) {
        await _store.saveSongRaw(song);
      }
      onMetadataReady?.call(songs);

      // 악보 바이너리는 백그라운드에서 순차 다운로드 (곡 목록 표시를 막지 않음)
      int done = 0;
      final allSheets = songs.expand((s) => s.sheets).toList();
      for (final sheet in allSheets) {
        done++;
        if (sheet.storageRef.isEmpty) continue;
        final existing = _store.getFile(sheet.storageRef);
        if (existing != null) continue;
        onProgress?.call('악보 파일 다운로드 중... ($done/${allSheets.length})');
        try {
          final bytes = await _client.storage
              .from(SupabaseConfig.sheetsBucket)
              .download(sheet.storageRef);
          await _store.putFile(sheet.storageRef, bytes);
          // 10장마다 한 번씩 화면 갱신 (악보 이미지가 점진적으로 나타나도록)
          if (done % 10 == 0) onMetadataReady?.call(songs);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('악보 다운로드 실패(${sheet.storageRef}): $e');
          }
          // 개별 파일 실패는 무시하고 계속 진행 (메타데이터는 유지)
        }
      }
      onMetadataReady?.call(songs);

      onProgress?.call('동기화 완료');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('동기화 실패: $e');
      return false;
    }
  }

  /// 곡 생성 (온라인 전용). 성공 시 생성된 Song(캐시 반영 완료)을 반환.
  Future<Song> createSong({
    required String title,
    required String composer,
    required List<String> tags,
    required dynamic lyrics, // SongLyrics
  }) async {
    final payload = {
      'title': title,
      'composer': composer,
      'tags': tags,
      'lyrics': lyrics.toMap(),
    };
    final inserted = await _client
        .from('songs')
        .insert(payload)
        .select()
        .single();
    final song = Song.fromSupabaseMap(inserted);
    await _store.saveSongRaw(song);
    return song;
  }

  /// 곡 메타(제목/작곡가/태그/가사) 수정 (온라인 전용)
  Future<void> updateSongMeta(Song song) async {
    await _client.from('songs').update(song.toSupabaseMap()).eq('id', song.id);
    await _store.saveSongRaw(song);
  }

  /// 가사/배치만 수정 (온라인 전용)
  Future<void> updateLyrics(String songId, dynamic lyrics) async {
    await _client
        .from('songs')
        .update({'lyrics': lyrics.toMap()})
        .eq('id', songId);
  }

  /// 곡 삭제 (온라인 전용) — Storage 파일 + sheets row + songs row 모두 제거
  Future<void> deleteSong(Song song) async {
    final paths = song.sheets
        .map((s) => s.storageRef)
        .where((p) => p.isNotEmpty)
        .toList();
    if (paths.isNotEmpty) {
      try {
        await _client.storage.from(SupabaseConfig.sheetsBucket).remove(paths);
      } catch (e) {
        if (kDebugMode) debugPrint('스토리지 파일 삭제 실패: $e');
      }
    }
    // sheets 테이블은 songs FK에 ON DELETE CASCADE가 없을 수 있으므로 명시적으로 삭제
    await _client.from('sheets').delete().eq('song_id', song.id);
    await _client.from('songs').delete().eq('id', song.id);
    await _store.deleteSong(song);
  }

  /// 악보 페이지 업로드(신규) 또는 교체 (온라인 전용)
  /// [existingStorageRef]가 있으면 같은 파일 경로에 upsert, 없으면 새 경로 생성.
  Future<SheetMeta> uploadSheet({
    required String songId,
    String? existingSheetId,
    String? existingStorageRef,
    required String musicKey,
    required int ord,
    required Uint8List bytes,
    required String filename,
    required String mime,
  }) async {
    final storageRef =
        existingStorageRef ??
        '$songId/${musicKey}_${DateTime.now().millisecondsSinceEpoch}_$filename';

    await _client.storage
        .from(SupabaseConfig.sheetsBucket)
        .uploadBinary(
          storageRef,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: true),
        );

    final rowPayload = {
      'song_id': songId,
      'music_key': musicKey,
      'file_path': storageRef,
      'filename': filename,
      'mime': mime,
      'size': bytes.length,
      'ord': ord,
    };

    Map<String, dynamic> row;
    if (existingSheetId != null) {
      row = await _client
          .from('sheets')
          .update(rowPayload)
          .eq('id', existingSheetId)
          .select()
          .single();
    } else {
      row = await _client.from('sheets').insert(rowPayload).select().single();
    }

    await _store.putFile(storageRef, bytes);
    return SheetMeta.fromSupabaseMap(row);
  }

  /// 악보 페이지 삭제 (온라인 전용)
  Future<void> deleteSheet(SheetMeta sheet) async {
    if (sheet.storageRef.isNotEmpty) {
      try {
        await _client.storage.from(SupabaseConfig.sheetsBucket).remove([
          sheet.storageRef,
        ]);
      } catch (e) {
        if (kDebugMode) debugPrint('스토리지 파일 삭제 실패: $e');
      }
    }
    if (sheet.id.isNotEmpty) {
      await _client.from('sheets').delete().eq('id', sheet.id);
    }
    await _store.deleteFile(sheet.storageRef);
  }

  /// 아직 로컬에 캐시되지 않은 모든 악보 파일을 다운로드한다 ("오프라인 전체 저장" 기능용).
  Future<int> cacheAllSheets({
    void Function(int done, int total)? onProgress,
  }) async {
    if (!await isOnline()) return 0;
    final songs = _store.getAllSongs();
    final allSheets = songs.expand((s) => s.sheets).toList();
    int cached = 0;
    int done = 0;
    for (final sheet in allSheets) {
      done++;
      onProgress?.call(done, allSheets.length);
      if (sheet.storageRef.isEmpty) continue;
      if (_store.getFile(sheet.storageRef) != null) continue;
      try {
        final bytes = await _client.storage
            .from(SupabaseConfig.sheetsBucket)
            .download(sheet.storageRef);
        await _store.putFile(sheet.storageRef, bytes);
        cached++;
      } catch (e) {
        if (kDebugMode) debugPrint('캐싱 실패(${sheet.storageRef}): $e');
      }
    }
    return cached;
  }
}
