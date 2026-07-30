import 'dart:io';
import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import '../widgets/mini_player_bar.dart';
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

  @override
  void initState() {
    super.initState();
    _songs = List.from(widget.playlist.songs);
    _loadFavs();
  }

  Future<void> _loadFavs() async {
    final f = await AudioPlayerService.getFavorites();
    if (mounted) setState(() => _favs = f);
  }

  Future<void> _refresh() async {
    final svc = await SettingsService.getInstance();
    final dir = await svc.getDownloadPath();
    final newSongs = await scanLocalAudioFiles(dir);
    if (mounted) setState(() => _songs = newSongs);
  }

  void _playSong(Song song) {
    _service.setQueue(_getFiltered(), startIndex: 0);
    _service.playSong(song);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }

  List<Song> _getFiltered() {
    if (_searchText.isEmpty) return _songs;
    return _songs.where((s) => s.title.toLowerCase().contains(_searchText.toLowerCase())).toList();
  }

  void _showAddToList(Song song) async {
    final existing = await PlaylistService.getPlaylists();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('添加到收藏夹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // 我喜欢（固定）
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.red, size: 24),
            title: const Text('我喜欢'),
            trailing: _favs.contains(song.filePath) ? const Icon(Icons.check, color: Colors.green) : null,
            onTap: () async {
              Navigator.pop(ctx);
              await AudioPlayerService.toggleFavorite(song.filePath);
              _loadFavs();
            },
          ),
          // 已有的自定义列表
          ...existing.map((pl) => FutureBuilder<bool>(
            future: PlaylistService.isSongInPlaylist(pl.id, song.filePath),
            builder: (_, snap) => ListTile(
              leading: const Icon(Icons.list, color: Colors.grey, size: 22),
              title: Text(pl.name),
              trailing: (snap.data == true) ? const Icon(Icons.check, color: Colors.green) : null,
              onTap: () async {
                Navigator.pop(ctx);
                await PlaylistService.addSongToPlaylist(pl.id, song.filePath);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加到${pl.name}')));
              },
            ),
          )),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add, color: Colors.blue),
            title: const Text('新建收藏夹'),
            onTap: () {
              Navigator.pop(ctx);
              _showNewListDialog(song);
            },
          ),
        ]),
      ),
    );
  }

  void _showNewListDialog(Song song) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '名称', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            if (ctrl.text.trim().isNotEmpty) {
              await PlaylistService.addPlaylist(ctrl.text.trim());
              Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('收藏夹已创建')));
            }
          }, child: const Text('创建')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFiltered();
    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(10), child: TextField(
          decoration: InputDecoration(hintText: '搜索...', prefixIcon: const Icon(Icons.search, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.symmetric(vertical: 0)),
          onChanged: (v) => setState(() => _searchText = v),
        )),
        Expanded(child: filtered.isEmpty
          ? const Center(child: Text('没有歌曲', style: TextStyle(color: Colors.grey)))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final song = filtered[i];
                final isFav = _favs.contains(song.filePath);
                return ListTile(
                  leading: _buildCover(song),
                  title: Text(song.title, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(song.uploader.isNotEmpty ? song.uploader : '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: Icon(Icons.add_circle_outline, color: Colors.grey[500], size: 24),
                        onPressed: () => _showAddToList(song),
                      ),
                      if (isFav)
                        Positioned(right: 0, bottom: 0,
                          child: Container(
                            width: 12, height: 12,
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.favorite, color: Colors.white, size: 7),
                          )),
                    ],
                  ),
                  onTap: () => _playSong(song),
                );
              })),
        const MiniPlayerBar(), // 固定底部迷你播放器
      ]),
    );
  }

  Widget _buildCover(Song song) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final f = File(song.coverUrl!);
      if (f.existsSync()) return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(f, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, e, s) => _icon()));
    }
    return _icon();
  }

  Widget _icon() => const Icon(Icons.music_note, color: Colors.deepPurple, size: 28);
}
