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
    final service = await SettingsService.getInstance();
    final dir = await service.getDownloadPath();
    _songs = await scanLocalAudioFiles(dir);
    _loadFavs();
    setState(() {});
  }

  void _playSong(Song song, int index) {
    final filtered = _getFiltered();
    _service.setQueue(filtered, startIndex: filtered.indexWhere((s) => s.filePath == song.filePath));
    _service.playSong(song);
    Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
  }

  List<Song> _getFiltered() {
    if (_searchText.isEmpty) return _songs;
    return _songs.where((s) => s.title.toLowerCase().contains(_searchText.toLowerCase()) || s.uploader.toLowerCase().contains(_searchText.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFiltered();
    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        PopupMenuButton<String>(itemBuilder: (_) => [
          const PopupMenuItem(value: 'all', child: Text('全部播放')),
        ], onSelected: (v) { if (filtered.isNotEmpty) _playSong(filtered.first, 0); }),
      ]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: TextField(
          decoration: InputDecoration(hintText: '搜索歌曲...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(vertical: 0)),
          onChanged: (v) => setState(() => _searchText = v),
        )),
        Expanded(child: filtered.isEmpty
          ? const Center(child: Text('没有歌曲', style: TextStyle(color: Colors.grey)))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final song = filtered[i];
                final idx = _songs.indexWhere((s) => s.filePath == song.filePath);
                final isFav = _favs.contains(song.filePath);
                return ListTile(
                  leading: _buildCover(song),
                  title: Text(song.title, style: const TextStyle(fontSize: 15)),
                  subtitle: Text(song.uploader.isNotEmpty ? song.uploader : '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: IconButton(
                    icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : Colors.grey, size: 22),
                    onPressed: () async { await AudioPlayerService.toggleFavorite(song.filePath); _loadFavs(); },
                  ),
                  onTap: () => _playSong(song, idx),
                );
              })),
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

  Widget _icon() => const Icon(Icons.music_note, color: Colors.deepPurple, size: 32);
}
