import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../services/song_provider.dart';
import '../theme/app_theme.dart';
import '../utils/key_utils.dart';
import '../widgets/key_chip.dart';
import 'song_detail_screen.dart';
import 'song_editor_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SongProvider>(
      builder: (context, provider, _) {
        final keyQ = parseKeyQuery(_query);
        final List<Song> items = keyQ != null
            ? provider.byKey(keyQ)
            : provider.search(_query);
        final totalCount = provider.songs.length;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(context, totalCount, provider),
                Expanded(
                  child: provider.loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.brass,
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.brass,
                          onRefresh: provider.refresh,
                          child: _buildBody(context, items, keyQ, totalCount),
                        ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SongEditorScreen()),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('곡 추가'),
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    int totalCount,
    SongProvider provider,
  ) {
    return Container(
      color: AppColors.ink,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '\u266A',
                style: TextStyle(fontSize: 22, color: AppColors.brassSoft),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '찬양 보관함',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.2,
                      ),
                    ),
                    Text(
                      '검색 · 키별 악보 · 파트별 가사 배치',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFFB9B9CC),
                      ),
                    ),
                  ],
                ),
              ),
              _buildNetBadge(provider),
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                tooltip: '설정',
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: AppColors.ink, fontSize: 14),
            decoration: InputDecoration(
              hintText: '제목·가사·키로 검색 (예: G, Eb, Am)',
              hintStyle: const TextStyle(
                color: AppColors.inkFaint,
                fontSize: 13.5,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.inkFaint,
                size: 20,
              ),
              filled: true,
              fillColor: Colors.white,
              isDense: true,
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.inkFaint,
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetBadge(SongProvider provider) {
    if (provider.syncing) {
      return const Padding(
        padding: EdgeInsets.only(right: 4),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.brassSoft,
          ),
        ),
      );
    }
    if (provider.isOnline) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: provider.refresh,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 13, color: Colors.white),
            SizedBox(width: 4),
            Text(
              '오프라인',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<Song> items,
    String? keyQ,
    int totalCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '곡 목록',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: AppColors.inkFaint,
                ),
              ),
              Text(
                keyQ != null
                    ? '${prettyKey(keyQ)} 키 · ${items.length}곡'
                    : '$totalCount곡${_query.isNotEmpty && items.length != totalCount ? ' · ${items.length} 검색' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _buildEmpty(totalCount, keyQ)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final s = items[index];
                    return _SongListTile(
                      song: s,
                      highlightKey: keyQ,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SongDetailScreen(songId: s.id),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty(int totalCount, String? keyQ) {
    String msg;
    if (totalCount == 0) {
      msg = '아직 곡이 없어요.\n오른쪽 아래 + 버튼으로 첫 곡을 추가해보세요.';
    } else if (keyQ != null) {
      msg = '${prettyKey(keyQ)} 키로 등록된 곡이 없습니다.';
    } else {
      msg = '검색 결과가 없습니다.';
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.music_note_outlined,
                size: 48,
                color: AppColors.inkFaint,
              ),
              const SizedBox(height: 14),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SongListTile extends StatelessWidget {
  final Song song;
  final String? highlightKey;
  final VoidCallback onTap;

  const _SongListTile({
    required this.song,
    required this.onTap,
    this.highlightKey,
  });

  @override
  Widget build(BuildContext context) {
    final keys = sortKeys(song.keys);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        letterSpacing: -0.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (song.composer.isNotEmpty)
                          Flexible(
                            child: Text(
                              song.composer,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.inkSoft,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (song.composer.isNotEmpty && keys.isNotEmpty)
                          const SizedBox(width: 8),
                        if (keys.isNotEmpty)
                          Wrap(
                            spacing: 3,
                            children: keys
                                .map(
                                  (k) => KeyChipMini(
                                    musicKey: k,
                                    highlighted: k == highlightKey,
                                  ),
                                )
                                .toList(),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.inkFaint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
