import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import 'player_page.dart';

class SongListPage extends StatefulWidget {
  final Playlist playlist;
  const SongListPage({super.key, required this.playlist});

  @override
  State<SongListPage> createState() => _SongListPageState();
}

class _SongListPageState extends State<SongListPage> {
  final _service = AudioPlayerService();
  late List<Song> _songs;
  Set<String> _favs = {};
  String _searchText = '';
  Timer? _favRefreshTimer;

  @override
  void initState() {
    super.initState();
    _songs = List.from(widget.playlist.songs);
    _loadFavs();
    // 定期刷新收藏状态（因为收藏可能在播放器页被修改）
    _favRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _loadFavs();
    });
  }

  @override
  void dispose() {
    _favRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFavs() async {
    final favs = await AudioPlayerService.getFavorites();
    if (mounted) setState(() => _favs = favs);
  }

  Future<void> _refresh() async {
    final service = await SettingsService.getInstance();
    final dir = await service.getDownloadPath();
    final newSongs = await scanLocalAudioFiles(dir);
    if (mounted) setState(() => _songs = newSongs);
  }

  void _playSong(Song song, int index) {
    // 设置播放队列
    final filtered = _getFilteredSongs();
    _service.setQueue(filtered, startIndex: filtered.indexWhere((s) => s.filePath == song.filePath));
    _service.playSong(song);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }

  List<Song> _getFilteredSongs() {
    if (_searchText.isEmpty) return _songs;
    return _songs.where((s) => s.title.toLowerCase().contains(_searchText.toLowerCase()) || s.uploader.toLowerCase().contains(_searchText.toLowerCase())).toList();
  }

  void _showLongPressMenu(Song song) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('下一首播放'),
              onTap: () { _service.addToQueue(song); Navigator.pop(ctx); },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play),
              title: const Text('添加到...'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddToPlaylistDialog(song);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddToPlaylistDialog(Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加到播放列表'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...mockPlaylists.map((pl) => ListTile(
              title: Text('${pl.icon} ${pl.name}'),
              onTap: () { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加到${pl.name}'))); },
            )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add, color: Colors.blue),
              title: const Text('新建播放列表', style: TextStyle(color: Colors.blue)),
              onTap: () {
                Navigator.pop(ctx);
                _showNewPlaylistDialog(song);
              },
            ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
      ),
    );
  }

  void _showNewPlaylistDialog(Song song) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建播放列表'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: '输入列表名称', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () { Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('播放列表已创建'))); }, child: const Text('创建')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFilteredSongs();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
          PopupMenuButton<String>(itemBuilder: (_) => [
            const PopupMenuItem(value: 'all', child: Text('全部播放')),
          ], onSelected: (v) {
            if (filtered.isNotEmpty) _playSong(filtered.first, 0);
          }),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(hintText: '搜索歌曲...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(vertical: 0)),
            onChanged: (v) => setState(() => _searchText = v),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('没有歌曲', style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final song = filtered[index];
                    final idx = _songs.indexWhere((s) => s.filePath == song.filePath);
                    final isFav = _favs.contains(song.bvid);
                    return ListTile(
                      leading: _buildCover(song),
                      title: Text(song.title, style: const TextStyle(fontSize: 15)),
                      subtitle: Text(song.uploader.isNotEmpty ? song.uploader : (song.lastPlayedText.isNotEmpty ? song.lastPlayedText : ''), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: IconButton(
                        icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : Colors.grey, size: 22),
                        onPressed: () async {
                          await AudioPlayerService.toggleFavorite(song.bvid);
                          _loadFavs();
                        },
                      ),
                      onTap: () => _playSong(song, idx),
                      onLongPress: () => _showLongPressMenu(song),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _buildCover(Song song) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final file = File(song.coverUrl!);
      if (file.existsSync()) {
        return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(file, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, e, s) => _musicIcon()));
      }
    }
    return _musicIcon();
  }

  Widget _musicIcon() => const Icon(Icons.music_note, color: Colors.deepPurple, size: 32);
}
