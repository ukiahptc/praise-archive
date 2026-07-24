import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/song.dart';
import '../models/lyric_section.dart';
import '../services/song_provider.dart';
import '../theme/app_theme.dart';
import '../utils/key_utils.dart';

const _uuid = Uuid();

class _EditPage {
  String? sheetId; // existing sheet id (null if new)
  Uint8List? bytes; // new bytes to upload
  String? filename;
  String? mime;
  bool existing; // has existing data unchanged
  int size;

  _EditPage({
    this.sheetId,
    this.filename,
    this.mime,
    this.existing = false,
    this.size = 0,
  });

  bool get hasData => bytes != null || existing;
}

class _EditKeyRow {
  String musicKey;
  List<_EditPage> pages;
  _EditKeyRow({required this.musicKey, required this.pages});
}

class SongEditorScreen extends StatefulWidget {
  final String? songId;
  const SongEditorScreen({super.key, this.songId});

  @override
  State<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends State<SongEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _composerCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  List<LyricSection> _sections = [];
  List<String> _arrangement = [];
  List<_EditKeyRow> _keyRows = [];
  bool _saving = false;
  bool _initialized = false;

  bool get isEditing => widget.songId != null;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _composerCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  void _initFromSong(Song? song) {
    if (_initialized) return;
    _initialized = true;
    if (song != null) {
      _titleCtrl.text = song.title;
      _composerCtrl.text = song.composer;
      _tagsCtrl.text = song.tags.join(', ');
      _sections = song.lyrics.sections
          .map(
            (s) => LyricSection(
              id: s.id,
              type: s.type,
              label: s.label,
              text: s.text,
            ),
          )
          .toList();
      _arrangement = [...song.lyrics.arrangement];
      final keys = sortKeys(song.keys);
      _keyRows = keys.map((k) {
        final pages = song
            .pagesFor(k)
            .map(
              (sh) => _EditPage(
                sheetId: sh.id,
                existing: true,
                filename: sh.filename,
                mime: sh.mime,
                size: sh.size,
              ),
            )
            .toList();
        return _EditKeyRow(musicKey: k, pages: pages);
      }).toList();
    }
    if (_keyRows.isEmpty) {
      _keyRows.add(_EditKeyRow(musicKey: '', pages: [_EditPage()]));
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save(SongProvider provider) async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _toast('제목을 입력하세요');
      return;
    }
    final composer = _composerCtrl.text.trim();
    final tags = _tagsCtrl.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final rows = _keyRows.where((r) => r.musicKey.isNotEmpty).toList();
    final keys = rows.map((r) => r.musicKey).toList();
    final dupSet = <String>{};
    for (final k in keys) {
      if (!dupSet.add(k)) {
        _toast('중복된 키가 있습니다: $k');
        return;
      }
    }

    // arrangement 정리: 존재하는 섹션 id만, 새 섹션은 자동 뒤에 추가
    final sectionIds = _sections.map((s) => s.id).toList();
    var arrangement = _arrangement
        .where((id) => sectionIds.contains(id))
        .toList();
    if (arrangement.isEmpty) arrangement = [...sectionIds];

    final lyrics = SongLyrics(sections: _sections, arrangement: arrangement);

    setState(() => _saving = true);
    try {
      String songId;
      if (isEditing) {
        songId = widget.songId!;
        await provider.updateSongMeta(
          id: songId,
          title: title,
          composer: composer,
          tags: tags,
          lyrics: lyrics,
        );
      } else {
        songId = await provider.createSong(
          title: title,
          composer: composer,
          tags: tags,
          lyrics: lyrics,
        );
      }

      final song = provider.byId(songId);
      final prevSheetIds = song?.sheets.map((s) => s.id).toSet() ?? <String>{};
      final keptIds = <String>{};

      for (final row in rows) {
        int ord = 0;
        for (final page in row.pages) {
          if (!page.hasData) continue;
          ord++;
          if (page.bytes != null) {
            await provider.addOrReplaceSheet(
              songId: songId,
              existingSheetId: page.sheetId,
              musicKey: row.musicKey,
              ord: ord,
              bytes: page.bytes!,
              filename: page.filename ?? 'sheet',
              mime: page.mime ?? 'application/octet-stream',
            );
            if (page.sheetId != null) keptIds.add(page.sheetId!);
          } else if (page.sheetId != null) {
            // existing unchanged, but key/ord may have changed -> re-save with same bytes
            final currentSong = provider.byId(songId);
            final existingSheet = currentSong?.sheets.firstWhere(
              (s) => s.id == page.sheetId,
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
            if (existingSheet != null && existingSheet.id.isNotEmpty) {
              final existingBytes = provider.getSheetBytes(
                existingSheet.storageRef,
              );
              if (existingBytes != null) {
                await provider.addOrReplaceSheet(
                  songId: songId,
                  existingSheetId: page.sheetId,
                  musicKey: row.musicKey,
                  ord: ord,
                  bytes: existingBytes,
                  filename: existingSheet.filename,
                  mime: existingSheet.mime,
                );
              }
            }
            keptIds.add(page.sheetId!);
          }
        }
      }

      // 제거된 페이지 정리
      final toRemove = prevSheetIds.difference(keptIds);
      for (final sid in toRemove) {
        await provider.removeSheet(songId, sid);
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on OfflineWriteException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(SongProvider provider) async {
    if (widget.songId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('곡 삭제'),
        content: const Text('이 곡과 모든 악보·가사를 삭제할까요?'),
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
      try {
        await provider.deleteSong(widget.songId!);
        if (mounted) {
          Navigator.of(context)
            ..pop()
            ..pop();
        }
      } on OfflineWriteException catch (e) {
        _toast(e.message);
      } catch (e) {
        _toast('삭제 실패: $e');
      }
    }
  }

  Future<void> _pickFile(_EditPage page) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      if (f.bytes == null) return;
      if (f.size > 25 * 1048576) {
        _toast('파일이 너무 큽니다 (최대 25MB)');
        return;
      }
      String mime = 'application/octet-stream';
      final ext = (f.extension ?? '').toLowerCase();
      if (ext == 'pdf') {
        mime = 'application/pdf';
      } else if (ext == 'png') {
        mime = 'image/png';
      } else if (ext == 'jpg' || ext == 'jpeg') {
        mime = 'image/jpeg';
      } else if (ext == 'webp') {
        mime = 'image/webp';
      }
      setState(() {
        page.bytes = f.bytes;
        page.filename = f.name;
        page.mime = mime;
        page.existing = false;
        page.size = f.size;
      });
    } catch (e) {
      _toast('파일 선택 실패: $e');
    }
  }

  Future<void> _pickFromCamera(_EditPage page) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      setState(() {
        page.bytes = bytes;
        page.filename = xfile.name;
        page.mime = 'image/jpeg';
        page.existing = false;
        page.size = bytes.length;
      });
    } catch (e) {
      _toast('카메라 촬영 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SongProvider>(
      builder: (context, provider, _) {
        final song = isEditing ? provider.byId(widget.songId!) : null;
        _initFromSong(song);

        return Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? '곡 수정' : '곡 추가'),
            actions: [
              if (isEditing)
                IconButton(
                  onPressed: _saving ? null : () => _delete(provider),
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (!provider.isOnline) _buildOfflineNotice(),
              if (!provider.isOnline) const SizedBox(height: 16),
              _label('제목'),
              const SizedBox(height: 6),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(hintText: '예: 주 은혜임을'),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('작사·작곡 / 출처 (선택)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _composerCtrl,
                          decoration: const InputDecoration(hintText: '예: 마커스'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('태그 (쉼표 구분)'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _tagsCtrl,
                          decoration: const InputDecoration(
                            hintText: '예: 경배, 빠른곡',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _label('가사 — 파트로 나눠서 입력'),
              const SizedBox(height: 10),
              _buildSectionPalette(),
              const SizedBox(height: 10),
              _buildSectionList(),
              const SizedBox(height: 22),
              _label('키별 악보 — 이미지 또는 PDF'),
              const SizedBox(height: 4),
              const Text(
                '키를 선택하고 악보 파일을 올리면, 언제든 오프라인으로 바로 볼 수 있어요.',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
              ),
              const SizedBox(height: 10),
              _buildKeyRows(),
              TextButton.icon(
                onPressed: () => setState(
                  () => _keyRows.add(
                    _EditKeyRow(musicKey: '', pages: [_EditPage()]),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('키 추가'),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : () => _save(provider),
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('저장'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOfflineNotice() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.danger.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
    ),
    child: const Row(
      children: [
        Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.danger),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            '오프라인 상태입니다. 인터넷에 연결되어야 곡을 등록·수정할 수 있어요.',
            style: TextStyle(fontSize: 12, color: AppColors.danger),
          ),
        ),
      ],
    ),
  );

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: AppColors.inkFaint,
    ),
  );

  Widget _buildSectionPalette() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: kPartTypes.map((t) {
        return OutlinedButton.icon(
          onPressed: () {
            setState(() {
              final existingTypes = _sections.map((s) => s.type).toList();
              _sections.add(
                LyricSection(
                  id: _uuid.v4(),
                  type: t,
                  label: autoLabel(t, existingTypes),
                  text: '',
                ),
              );
            });
          },
          icon: const Icon(Icons.add, size: 14, color: AppColors.brass),
          label: Text(t, style: const TextStyle(fontSize: 12.5)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionList() {
    if (_sections.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          '위 버튼으로 파트를 추가하세요 (예: Verse, Chorus…)',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.inkFaint, fontSize: 13),
        ),
      );
    }
    return Column(
      children: _sections.asMap().entries.map((entry) {
        final i = entry.key;
        final sec = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.lineSoft)),
                ),
                child: Row(
                  children: [
                    const Text(
                      '[',
                      style: TextStyle(
                        color: AppColors.inkFaint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: sec.label)
                          ..selection = TextSelection.collapsed(
                            offset: sec.label.length,
                          ),
                        onChanged: (v) => sec.label = v,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const Text(
                      ']',
                      style: TextStyle(
                        color: AppColors.inkFaint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      onPressed: i == 0
                          ? null
                          : () => setState(() {
                              final tmp = _sections[i - 1];
                              _sections[i - 1] = _sections[i];
                              _sections[i] = tmp;
                            }),
                      icon: const Icon(Icons.arrow_upward, size: 15),
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      onPressed: i == _sections.length - 1
                          ? null
                          : () => setState(() {
                              final tmp = _sections[i + 1];
                              _sections[i + 1] = _sections[i];
                              _sections[i] = tmp;
                            }),
                      icon: const Icon(Icons.arrow_downward, size: 15),
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      onPressed: () => setState(() => _sections.removeAt(i)),
                      icon: const Icon(
                        Icons.close,
                        size: 15,
                        color: AppColors.danger,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: TextEditingController(text: sec.text)
                    ..selection = TextSelection.collapsed(
                      offset: sec.text.length,
                    ),
                  onChanged: (v) => sec.text = v,
                  maxLines: 4,
                  minLines: 2,
                  decoration: const InputDecoration(
                    hintText: '이 파트의 가사…',
                    filled: false,
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeyRows() {
    final used = _keyRows
        .map((r) => r.musicKey)
        .where((k) => k.isNotEmpty)
        .toList();
    return Column(
      children: _keyRows.asMap().entries.map((entry) {
        final i = entry.key;
        final row = entry.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.paper,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: row.musicKey.isEmpty ? null : row.musicKey,
                        hint: const Text('키', style: TextStyle(fontSize: 13)),
                        items: kKeyOptions
                            .map(
                              (k) => DropdownMenuItem(
                                value: k,
                                enabled: !used.contains(k) || k == row.musicKey,
                                child: Text(
                                  prettyKey(k),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color:
                                        (!used.contains(k) || k == row.musicKey)
                                        ? AppColors.ink
                                        : AppColors.inkFaint,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => row.musicKey = v ?? ''),
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _keyRows.removeAt(i);
                      if (_keyRows.isEmpty) {
                        _keyRows.add(
                          _EditKeyRow(musicKey: '', pages: [_EditPage()]),
                        );
                      }
                    }),
                    child: const Text(
                      '키 삭제',
                      style: TextStyle(color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...row.pages.asMap().entries.map((pe) {
                final pi = pe.key;
                final page = pe.value;
                final info = page.bytes != null
                    ? '${page.filename} · ${fmtSize(page.size)}'
                    : (page.existing ? '기존 악보 (유지됨)' : '파일 없음');
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          '${pi + 1}페이지',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkFaint,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          info,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: page.hasData
                                ? AppColors.ink
                                : AppColors.inkSoft,
                            fontWeight: page.hasData
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        onPressed: () =>
                            _pickFromCamera(page).then((_) => setState(() {})),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        tooltip: '카메라',
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      TextButton(
                        onPressed: () => _pickFile(page),
                        child: Text(
                          page.hasData ? '교체' : '파일',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.brassDeep,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() => row.pages.removeAt(pi)),
                        icon: const Icon(
                          Icons.close,
                          size: 16,
                          color: AppColors.danger,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                );
              }),
              if (row.pages.length < 3)
                TextButton(
                  onPressed: () => setState(() => row.pages.add(_EditPage())),
                  child: const Text(
                    '+ 페이지 추가 (최대 3장)',
                    style: TextStyle(fontSize: 12, color: AppColors.brassDeep),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
