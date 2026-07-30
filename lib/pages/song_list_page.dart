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
    if (widget.playlist.id == 'local') {
      final svc = await SettingsService.getInstance();
      final dir = await svc.getDownloadPath();
      _songs = await scanLocalAudioFiles(dir);
    } else if (widget.playlist.id == 'fav') {
      final favPaths = await AudioPlayerService.getFavorites();
      final svc = await SettingsService.getInstance();
      final dir = await svc.getDownloadPath();
      final all = await scanLocalAudioFiles(dir);
      _songs = all.where((s) => favPaths.contains(s.filePath)).toList();
    } else {
      // 自定义歌单：重新加载
      final pls = await PlaylistService.getPlaylists();
      final found = pls.where((p) => p.id == widget.playlist.id).firstOrNull;
      if (found != null) _songs = found.songs;
    }
    if (mounted) setState(() {});
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
              // 新建后立即把当前歌曲加进去
              final pls = await PlaylistService.getPlaylists();
              final created = pls.where((p) => p.name == ctrl.text.trim()).firstOrNull;
              if (created != null) {
                await PlaylistService.addSongToPlaylist(created.id, song.filePath);
              }
              Navigator.pop(ctx);
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已创建并添加')));
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
        const SizedBox(height: 8),
        // 底部固定区域：当前播放 + 队列 + 模式
        _buildBottomBar(),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final service = AudioPlayerService();
    final currentSong = service.currentSong;
    final displaySong = currentSong ?? (_getFiltered().isNotEmpty ? _getFiltered().first : null);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.12))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 当前播放行
          if (displaySong != null)
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage())),
              child: Row(children: [
                Icon(Icons.music_note, color: currentSong != null ? Colors.deepPurple : Colors.grey, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(displaySong.title, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                if (service.isPlaying)
                  const Icon(Icons.volume_up, color: Colors.deepPurple, size: 16),
              ]),
            ),
          // 播放列表 + 模式行
          Row(children: [
            GestureDetector(
              onTap: () {
                final queue = service.queue;
                if (queue.isEmpty) {
                  service.setQueue(_getFiltered(), startIndex: 0);
                }
                showModalBottomSheet(
                  context: context, isScrollControlled: true,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => _buildQueueSheet(),
                );
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.queue_music, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('播放列表', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ]),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (_) => Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: PlayMode.values.map((m) {
                    final sel = service.playMode == m;
                    return ListTile(
                      leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? Colors.deepPurple : Colors.grey, size: 20),
                      title: Text(_modeLabel(m)),
                      onTap: () { service.setPlayMode(m); Navigator.pop(context); },
                    );
                  }).toList())),
                );
              },
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(service.playModeLabel, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 16),
              ]),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildQueueSheet() {
    final service = AudioPlayerService();
    final queue = service.queue.isNotEmpty ? service.queue : _getFiltered();
    return SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Text('播放列表 (${queue.length}首)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      Expanded(child: queue.isEmpty ? const Center(child: Text('队列为空')) : ListView.builder(itemCount: queue.length, itemBuilder: (_, i) {
        final s = queue[i]; final isCur = i == service.queueIndex;
        return ListTile(
          leading: Icon(isCur ? Icons.play_arrow : Icons.music_note, color: isCur ? Colors.deepPurple : Colors.grey, size: 22),
          title: Text(s.title, style: TextStyle(fontSize: 14, fontWeight: isCur ? FontWeight.bold : FontWeight.normal)),
          onTap: () { service.playSong(s); Navigator.pop(context); },
        );
      })),
    ]));
  }

  String _modeLabel(PlayMode m) { switch (m) { case PlayMode.sequential: return '顺序播放'; case PlayMode.loopList: return '列表循环'; case PlayMode.loopOne: return '单曲循环'; case PlayMode.shuffle: return '随机播放'; }}

  Widget _buildCover(Song song) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final f = File(song.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(f, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, e, s) => _icon()));
    }
    return _icon();
  }

  Widget _icon() => const Icon(Icons.music_note, color: Colors.deepPurple, size: 28);
}
