import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../services/song_provider.dart';
import '../models/lyric_section.dart';
import '../theme/app_theme.dart';
import '../utils/key_utils.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _caching = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _syncNow(SongProvider provider) async {
    await provider.refresh();
    if (!mounted) return;
    _toast(provider.isOnline ? '동기화 완료' : '오프라인 상태라 동기화할 수 없습니다');
  }

  Future<void> _cacheAll(SongProvider provider) async {
    setState(() => _caching = true);
    try {
      final n = await provider.cacheAllSheetsForOffline();
      _toast('악보 $n개를 오프라인용으로 저장했습니다');
    } on OfflineWriteException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _caching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SongProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('설정')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionTitle('동기화 상태'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            provider.isOnline
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined,
                            size: 18,
                            color: provider.isOnline
                                ? AppColors.ok
                                : AppColors.danger,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            provider.isOnline ? '온라인 (서버 연결됨)' : '오프라인 (캐시 모드)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: provider.isOnline
                                  ? AppColors.ok
                                  : AppColors.danger,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _statRow('등록된 곡 (공유 DB)', '${provider.songs.length}곡'),
                      const Divider(height: 20),
                      _statRow(
                        '기기에 저장된 악보 용량',
                        fmtSize(provider.totalSheetsSizeBytes),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '찬양팀 전체가 공유하는 클라우드 DB(Supabase)를 사용합니다. 온라인일 때 등록된 곡이 자동으로 동기화되어, 오프라인에서도 이미 받아둔 데이터를 볼 수 있어요.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkFaint,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: provider.syncing
                                  ? null
                                  : () => _syncNow(provider),
                              icon: provider.syncing
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.sync, size: 16),
                              label: const Text('지금 동기화'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _caching
                                  ? null
                                  : () => _cacheAll(provider),
                              icon: _caching
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.download_for_offline_outlined,
                                      size: 16,
                                    ),
                              label: const Text('오프라인 저장'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _sectionTitle('백업 & 복원'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.upload_file_outlined,
                        color: AppColors.brassDeep,
                      ),
                      title: const Text('가사·메타 정보 내보내기'),
                      subtitle: const Text(
                        '제목·가사·태그를 .json 파일로 저장 (악보 이미지는 포함되지 않음)',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      onTap: () => _exportBackup(context, provider),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.download_outlined,
                        color: AppColors.brassDeep,
                      ),
                      title: const Text('백업 파일 불러오기'),
                      subtitle: const Text(
                        '내보낸 .json 파일에서 곡 정보를 가져옵니다',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      onTap: () => _importBackup(context, provider),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _sectionTitle('위험 구역'),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: AppColors.danger,
                  ),
                  title: const Text(
                    '로컬 캐시 지우기',
                    style: TextStyle(color: AppColors.danger),
                  ),
                  subtitle: const Text(
                    '이 기기에 저장된 캐시만 삭제됩니다 (서버의 곡 데이터는 유지되며, 온라인이면 다시 자동으로 받아옵니다)',
                    style: TextStyle(fontSize: 11.5),
                  ),
                  onTap: () => _confirmClearAll(context, provider),
                ),
              ),
              const SizedBox(height: 22),
              const Center(
                child: Text(
                  '찬양 보관함 · v1.0.0\n온라인 동기화 + 오프라인 캐시',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkFaint,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10, left: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.inkFaint,
      ),
    ),
  );

  Widget _statRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
      ),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      ),
    ],
  );

  Future<void> _exportBackup(
    BuildContext context,
    SongProvider provider,
  ) async {
    try {
      final data = {
        'type': 'praise-archive-flutter',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'songs': provider.songs
            .map(
              (s) => {
                'title': s.title,
                'composer': s.composer,
                'tags': s.tags,
                'lyrics': s.lyrics.toMap(),
                'keys': s.keys,
              },
            )
            .toList(),
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final dir = await getTemporaryDirectory();
      final dateStr = DateTime.now().toIso8601String().substring(0, 10);
      final file = File('${dir.path}/찬양보관함_백업_$dateStr.json');
      await file.writeAsString(jsonStr);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '찬양 보관함 백업 (${provider.songs.length}곡)',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('내보내기 실패: $e')));
      }
    }
  }

  Future<void> _importBackup(
    BuildContext context,
    SongProvider provider,
  ) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.first.bytes == null) {
        return;
      }
      final jsonStr = utf8.decode(result.files.first.bytes!);
      final data = jsonDecode(jsonStr);
      if (data is! Map || data['songs'] is! List) {
        throw Exception('올바른 백업 파일이 아닙니다');
      }
      final songsRaw = data['songs'] as List;
      int imported = 0;
      for (final raw in songsRaw) {
        if (raw is! Map) continue;
        final title = raw['title']?.toString() ?? '';
        if (title.isEmpty) continue;
        final composer = raw['composer']?.toString() ?? '';
        final tags = (raw['tags'] is List)
            ? (raw['tags'] as List).map((e) => e.toString()).toList()
            : <String>[];
        final lyrics = SongLyrics.fromMap(raw['lyrics']);
        await provider.createSong(
          title: title,
          composer: composer,
          tags: tags,
          lyrics: lyrics,
        );
        imported++;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$imported곡을 가져왔습니다 (악보는 별도로 등록해주세요)')),
        );
      }
    } on OfflineWriteException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('가져오기 실패: $e')));
      }
    }
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    SongProvider provider,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로컬 캐시 지우기'),
        content: const Text(
          '이 기기에 저장된 캐시만 삭제됩니다. 서버에 저장된 곡 데이터는 삭제되지 않으며, 온라인이면 다시 자동으로 받아옵니다. 계속할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await provider.clearLocalCache();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('로컬 캐시를 삭제했습니다')));
      }
    }
  }
}
