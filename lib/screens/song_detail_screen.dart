import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../models/song.dart';
import '../models/lyric_section.dart';
import '../services/song_provider.dart';
import '../theme/app_theme.dart';
import '../utils/key_utils.dart';
import 'song_editor_screen.dart';
import 'sheet_viewer_screen.dart';

class SongDetailScreen extends StatefulWidget {
  final String songId;
  const SongDetailScreen({super.key, required this.songId});

  @override
  State<SongDetailScreen> createState() => _SongDetailScreenState();
}

class _SongDetailScreenState extends State<SongDetailScreen> {
  String? _currentKey;
  late SongLyrics _lyrics;
  bool _showPreview = false;
  bool _initialized = false;

  void _initFrom(Song song) {
    if (_initialized) return;
    _lyrics = song.lyrics.clone();
    _currentKey = song.keys.isNotEmpty ? sortKeys(song.keys).first : null;
    _initialized = true;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _persistLyrics(SongProvider provider) async {
    try {
      await provider.updateLyrics(widget.songId, _lyrics);
    } on OfflineWriteException catch (e) {
      _toast('${e.message} (변경사항은 온라인 상태가 되면 다시 시도해주세요)');
    } catch (e) {
      _toast('저장 실패: $e');
    }
  }

  void _copyText(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SongProvider>(
      builder: (context, provider, _) {
        final song = provider.byId(widget.songId);
        if (song == null) {
          return const Scaffold(body: Center(child: Text('곡을 찾을 수 없습니다')));
        }
        _initFrom(song);
        final keys = sortKeys(song.keys);

        return Scaffold(
          appBar: AppBar(
            title: Text(song.title, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '곡 수정',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SongEditorScreen(songId: song.id),
                    ),
                  );
                },
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('곡 삭제'),
                        content: const Text(
                          '이 곡과 모든 악보·가사를 삭제할까요? 이 작업은 되돌릴 수 없습니다.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              '삭제',
                              style: TextStyle(color: AppColors.danger),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      try {
                        await provider.deleteSong(song.id);
                        if (context.mounted) Navigator.of(context).pop();
                      } on OfflineWriteException catch (e) {
                        if (context.mounted) _toast(e.message);
                      } catch (e) {
                        if (context.mounted) _toast('삭제 실패: $e');
                      }
                    }
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '곡 삭제',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _buildMetaSection(song, keys),
              const SizedBox(height: 18),
              _buildSheetCard(context, song, keys, provider),
              const SizedBox(height: 18),
              _buildLyricsCard(context, provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetaSection(Song song, List<String> keys) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          song.title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (song.composer.isNotEmpty)
              Text(
                song.composer,
                style: const TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 13.5,
                ),
              ),
            Text(
              keys.isEmpty
                  ? '등록된 악보 없음'
                  : '${keys.length}개 키 · 악보 ${song.sheets.length}장',
              style: const TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
            ),
          ],
        ),
        if (song.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: song.tags
                .map(
                  (t) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Text(
                      t,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildSheetCard(
    BuildContext context,
    Song song,
    List<String> keys,
    SongProvider provider,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🎼', style: TextStyle(fontSize: 14)),
                SizedBox(width: 8),
                Text(
                  '악보 — 키 선택',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (keys.isEmpty)
              const Text(
                '등록된 키가 없습니다. 곡 수정에서 키별 악보를 올려주세요.',
                style: TextStyle(color: AppColors.inkSoft, fontSize: 13.5),
              )
            else ...[
              SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: keys.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final k = keys[i];
                    final active = k == _currentKey;
                    return GestureDetector(
                      onTap: () => setState(() => _currentKey = k),
                      child: Container(
                        width: 58,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? Colors.white : AppColors.paper,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: active ? AppColors.brass : AppColors.line,
                            width: 1.4,
                          ),
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: AppColors.brass.withValues(
                                      alpha: 0.18,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              prettyKey(k),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              active ? '선택됨' : '악보',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? AppColors.brassDeep
                                    : AppColors.inkFaint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              if (_currentKey != null)
                _buildSheetPages(context, song, _currentKey!, provider),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSheetPages(
    BuildContext context,
    Song song,
    String key,
    SongProvider provider,
  ) {
    final pages = song.pagesFor(key);
    if (pages.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 30),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(
              Icons.description_outlined,
              size: 30,
              color: AppColors.inkFaint,
            ),
            SizedBox(height: 8),
            Text('이 키의 악보가 없습니다.', style: TextStyle(color: AppColors.inkSoft)),
          ],
        ),
      );
    }
    return Column(
      children: [
        if (pages.length > 1)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () =>
                  _downloadAllPages(context, song, pages, provider),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: Text('이 키 전체 저장 (${pages.length}장)'),
            ),
          ),
        ...pages.asMap().entries.map((entry) {
          final idx = entry.key;
          final sheet = entry.value;
          final bytes = provider.getSheetBytes(sheet.storageRef);
          return Container(
            margin: EdgeInsets.only(top: idx > 0 ? 14 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (pages.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${idx + 1} / ${pages.length} 페이지',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brassDeep,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: bytes == null
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SheetViewerScreen(
                              bytes: bytes,
                              mime: sheet.mime,
                              title: '${prettyKey(key)} · ${sheet.filename}',
                            ),
                          ),
                        ),
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 160),
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.line),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: bytes == null
                        ? const Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: AppColors.inkFaint,
                              size: 36,
                            ),
                          )
                        : sheet.isImage
                        ? Image.memory(bytes, fit: BoxFit.contain)
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.picture_as_pdf_outlined,
                                  size: 40,
                                  color: AppColors.brassDeep,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  sheet.filename,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  '탭하여 PDF 보기',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${prettyKey(key)} 키 · ${sheet.filename} ${sheet.size > 0 ? '· ${fmtSize(sheet.size)}' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkSoft,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: bytes == null
                          ? null
                          : () => _saveToDevice(
                              context,
                              song,
                              key,
                              sheet,
                              bytes,
                              idx,
                              pages.length,
                            ),
                      icon: const Icon(Icons.download_outlined, size: 20),
                      tooltip: '기기에 저장',
                      color: AppColors.brassDeep,
                    ),
                    IconButton(
                      onPressed: bytes == null
                          ? null
                          : () => _shareFile(
                              song,
                              key,
                              sheet,
                              bytes,
                              idx,
                              pages.length,
                            ),
                      icon: const Icon(Icons.share_outlined, size: 20),
                      tooltip: '공유',
                      color: AppColors.inkSoft,
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Future<File> _writeTempFile(
    Song song,
    String key,
    SheetMeta sheet,
    Uint8List bytes,
    int idx,
    int total,
  ) async {
    final dir = await getTemporaryDirectory();
    final ext = sheet.filename.contains('.')
        ? sheet.filename.split('.').last
        : (sheet.isPdf ? 'pdf' : 'png');
    final suffix = total > 1 ? '_p${idx + 1}' : '';
    final name = safeFileName('${song.title}_$key$suffix.$ext');
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _saveToDevice(
    BuildContext context,
    Song song,
    String key,
    SheetMeta sheet,
    Uint8List bytes,
    int idx,
    int total,
  ) async {
    try {
      final file = await _writeTempFile(song, key, sheet, bytes, idx, total);
      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '${song.title} · ${prettyKey(key)} 키 악보',
        ),
      );
    } catch (e) {
      _toast('저장 실패: $e');
    }
  }

  Future<void> _shareFile(
    Song song,
    String key,
    SheetMeta sheet,
    Uint8List bytes,
    int idx,
    int total,
  ) async {
    try {
      final file = await _writeTempFile(song, key, sheet, bytes, idx, total);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '${song.title} · ${prettyKey(key)} 키 악보',
        ),
      );
    } catch (e) {
      _toast('공유 실패: $e');
    }
  }

  Future<void> _downloadAllPages(
    BuildContext context,
    Song song,
    List<SheetMeta> pages,
    SongProvider provider,
  ) async {
    final files = <XFile>[];
    for (final sheet in pages) {
      final bytes = provider.getSheetBytes(sheet.storageRef);
      if (bytes == null) continue;
      final idx = pages.indexOf(sheet);
      final file = await _writeTempFile(
        song,
        sheet.musicKey,
        sheet,
        bytes,
        idx,
        pages.length,
      );
      files.add(XFile(file.path));
    }
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: files, text: '${song.title} 악보 전체'),
    );
  }

  // ── 가사 파트 & 배치 ──
  Widget _buildLyricsCard(BuildContext context, SongProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text('🎤', style: TextStyle(fontSize: 14)),
                SizedBox(width: 8),
                Text(
                  '가사 & 배치',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppColors.inkFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSubLabel('파트'),
            const SizedBox(height: 8),
            _buildParts(provider),
            const SizedBox(height: 20),
            _buildSubLabel('배치 (부르는 순서)'),
            const SizedBox(height: 8),
            _buildArrangement(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildSubLabel(String text) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.inkFaint,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider(height: 1, color: AppColors.lineSoft)),
      ],
    );
  }

  Widget _buildParts(SongProvider provider) {
    if (_lyrics.sections.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '등록된 가사 파트가 없습니다. 곡 수정에서 추가하세요.',
          style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
        ),
      );
    }
    return Column(
      children: _lyrics.sections.map((sec) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brassSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sec.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brassDeep,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() => _lyrics.arrangement.add(sec.id));
                        _persistLyrics(provider);
                        _toast("'${sec.label}' 배치에 추가됨");
                      },
                      child: const Text(
                        '+ 배치 추가',
                        style: TextStyle(
                          color: AppColors.brassDeep,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _copyText('[${sec.label}]\n${sec.text.trim()}');
                        _toast("'${sec.label}' 복사됨");
                      },
                      child: const Text('복사', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  sec.text.trim().isEmpty ? '(가사 없음)' : sec.text,
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.6,
                    color: sec.text.trim().isEmpty
                        ? AppColors.inkFaint
                        : AppColors.ink,
                    fontStyle: sec.text.trim().isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildArrangement(SongProvider provider) {
    final map = {for (final s in _lyrics.sections) s.id: s};
    _lyrics.arrangement.removeWhere((id) => !map.containsKey(id));
    final hasArr = _lyrics.arrangement.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_lyrics.sections.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _lyrics.sections.map((sec) {
              return OutlinedButton.icon(
                onPressed: () {
                  setState(() => _lyrics.arrangement.add(sec.id));
                  _persistLyrics(provider);
                },
                icon: const Icon(Icons.add, size: 14, color: AppColors.brass),
                label: Text(sec.label, style: const TextStyle(fontSize: 12.5)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                    color: AppColors.brass,
                    style: BorderStyle.solid,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        if (!hasArr)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.line,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '위 파트를 눌러 부르는 순서를 만들어 보세요.\n(같은 파트를 여러 번 넣을 수 있어요)',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkSoft, fontSize: 13),
            ),
          )
        else
          Column(
            children: _lyrics.arrangement.asMap().entries.map((entry) {
              final i = entry.key;
              final id = entry.value;
              final sec = map[id]!;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '[${sec.label}]',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: i == 0
                          ? null
                          : () {
                              setState(() {
                                final a = _lyrics.arrangement;
                                final tmp = a[i - 1];
                                a[i - 1] = a[i];
                                a[i] = tmp;
                              });
                              _persistLyrics(provider);
                            },
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      onPressed: i == _lyrics.arrangement.length - 1
                          ? null
                          : () {
                              setState(() {
                                final a = _lyrics.arrangement;
                                final tmp = a[i + 1];
                                a[i + 1] = a[i];
                                a[i] = tmp;
                              });
                              _persistLyrics(provider);
                            },
                      icon: const Icon(Icons.arrow_downward, size: 16),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() => _lyrics.arrangement.removeAt(i));
                        _persistLyrics(provider);
                      },
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.danger,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ElevatedButton.icon(
              onPressed: hasArr
                  ? () {
                      _copyText(_lyrics.buildCopy(withLabels: true));
                      _toast('배치 순서대로 복사 (파트 라벨 포함)');
                    }
                  : null,
              icon: const Icon(Icons.copy_all, size: 16),
              label: const Text('배치대로 복사'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            OutlinedButton(
              onPressed: hasArr
                  ? () {
                      _copyText(_lyrics.buildCopy(withLabels: false));
                      _toast('가사만 복사 (라벨 없음)');
                    }
                  : null,
              child: const Text('라벨 없이 복사'),
            ),
            if (_lyrics.sections.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(
                    () => _lyrics.arrangement = _lyrics.sections
                        .map((s) => s.id)
                        .toList(),
                  );
                  _persistLyrics(provider);
                  _toast('전체 파트를 순서대로 채웠습니다');
                },
                child: const Text('전체 파트 채우기'),
              ),
            if (hasArr)
              TextButton(
                onPressed: () {
                  setState(() {
                    _lyrics.arrangement = [];
                    _showPreview = false;
                  });
                  _persistLyrics(provider);
                },
                child: const Text('배치 비우기'),
              ),
            if (hasArr)
              TextButton(
                onPressed: () => setState(() => _showPreview = !_showPreview),
                child: Text(_showPreview ? '미리보기 닫기' : '미리보기'),
              ),
          ],
        ),
        if (_showPreview && hasArr)
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2036),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              _lyrics.buildCopy(withLabels: true),
              style: const TextStyle(
                color: Color(0xFFE8E8F0),
                fontSize: 12.5,
                height: 1.7,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
    );
  }
}
