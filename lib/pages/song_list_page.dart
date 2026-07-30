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
    _service.currentSongNotifier.addListener(_onSongChanged);
  }

  @override
  void dispose() {
    _service.currentSongNotifier.removeListener(_onSongChanged);
    super.dispose();
  }

  void _onSongChanged() { if (mounted) setState(() {}); }

  Future<void> _loadFavs() async {
    final f = await AudioPlayerService.getFavorites();
    if (mounted) setState(() => _favs = f);
  }

  Future<void> _refresh() async {
    final svc = await SettingsService.getInstance();
    final dir = await svc.getDownloadPath();
    _cleanZeroFiles(dir);
    if (widget.playlist.id == 'local') {
      _songs = await scanLocalAudioFiles(dir);
    } else if (widget.playlist.id == 'fav') {
      final favPaths = await AudioPlayerService.getFavorites();
      final all = await scanLocalAudioFiles(dir);
      _songs = all.where((s) => favPaths.contains(s.filePath)).toList();
    } else {
      final pls = await PlaylistService.getPlaylists();
      final found = pls.where((p) => p.id == widget.playlist.id).firstOrNull;
      if (found != null) _songs = found.songs;
    }
    if (mounted) setState(() {});
  }

  void _cleanZeroFiles(String dir) {
    try { for (final f in Directory(dir).listSync()) { if (f is File && f.lengthSync() == 0) f.deleteSync(); } } catch (_) {}
  }

  void _playSong(Song song) {
    _service.setQueue(_getFiltered(), startIndex: _getFiltered().indexWhere((s) => s.filePath == song.filePath));
    _service.playSong(song);
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
      builder: (ctx) => Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('添加到收藏夹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ListTile(leading: const Icon(Icons.favorite, color: Colors.red, size: 24), title: const Text('我喜欢'),
          trailing: _favs.contains(song.filePath) ? const Icon(Icons.check, color: Colors.green) : null,
          onTap: () async { Navigator.pop(ctx); await AudioPlayerService.toggleFavorite(song.filePath); _loadFavs(); },
        ),
        ...existing.map((pl) => FutureBuilder<bool>(
          future: PlaylistService.isSongInPlaylist(pl.id, song.filePath),
          builder: (_, snap) => ListTile(leading: const Icon(Icons.list, color: Colors.grey, size: 22), title: Text(pl.name),
            trailing: (snap.data == true) ? const Icon(Icons.check, color: Colors.green) : null,
            onTap: () async { Navigator.pop(ctx); await PlaylistService.addSongToPlaylist(pl.id, song.filePath); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加到${pl.name}'))); },
          ),
        )),
        const Divider(),
        ListTile(leading: const Icon(Icons.add, color: Colors.blue), title: const Text('新建收藏夹'),
          onTap: () { Navigator.pop(ctx); _showNewListDialog(song); },
        ),
      ])),
    );
  }

  void _showNewListDialog(Song song) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新建收藏夹'),
      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '名称', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () async {
          if (ctrl.text.trim().isNotEmpty) {
            await PlaylistService.addPlaylist(ctrl.text.trim());
            final pls = await PlaylistService.getPlaylists();
            final created = pls.where((p) => p.name == ctrl.text.trim()).firstOrNull;
            if (created != null) { await PlaylistService.addSongToPlaylist(created.id, song.filePath); }
            Navigator.pop(ctx);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已创建并添加')));
          }
        }, child: const Text('创建')),
      ],
    ));
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
              padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final song = filtered[i]; final isFav = _favs.contains(song.filePath);
                final isPlaying = _service.currentSong?.filePath == song.filePath;
                return Container(
                  color: isPlaying ? Colors.deepPurple.withValues(alpha: 0.12) : Colors.transparent,
                  child: ListTile(
                    leading: isPlaying
                      ? const Icon(Icons.volume_up, color: Colors.deepPurple, size: 28)
                      : _buildCover(song),
                    title: Text(song.title, style: TextStyle(fontSize: 14, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal)),
                    subtitle: Text(song.uploader.isNotEmpty ? song.uploader : (_service.isPlaying && isPlaying ? '正在播放' : ''), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Stack(clipBehavior: Clip.none, children: [
                    IconButton(icon: Icon(Icons.add_circle_outline, color: Colors.grey[500], size: 24), onPressed: () => _showAddToList(song)),
                    if (isFav) Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.favorite, color: Colors.white, size: 7))),
                  ]),
                  onTap: () => _playSong(song),
                ));
              })),
        _buildBottomBar(),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final currentSong = _service.currentSong;
    final displaySong = currentSong ?? (_getFiltered().isNotEmpty ? _getFiltered().first : null);
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.12)))),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (displaySong != null)
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage())),
            child: Container(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [
              Icon(Icons.music_note, color: currentSong != null ? Colors.deepPurple : Colors.grey, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(displaySong.title, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
              if (_service.isPlaying) const Icon(Icons.volume_up, color: Colors.deepPurple, size: 18),
            ])),
          ),
        SizedBox(height: 40, child: Row(children: [
          GestureDetector(
            onTap: () {
              if (_service.queue.isEmpty) _service.setQueue(_getFiltered(), startIndex: 0);
              showModalBottomSheet(context: context, isScrollControlled: true,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                builder: (_) => StatefulBuilder(builder: (ctx, setSheetState) => _buildQueueSheet(setSheetState)),
              );
            },
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.queue_music, size: 18, color: Colors.grey), const SizedBox(width: 6),
              Text('播放列表', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            ])),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              showModalBottomSheet(context: context,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                builder: (_) => StatefulBuilder(builder: (ctx, setSheetState) => Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: PlayMode.values.map((m) {
                  final sel = _service.playMode == m;
                  return ListTile(
                    leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? Colors.deepPurple : Colors.grey, size: 20),
                    title: Text(_modeLabel(m)),
                    onTap: () { _service.setPlayMode(m); setState(() {}); setSheetState(() {}); Navigator.pop(context); },
                  );
                }).toList()))),
              );
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_service.playModeLabel, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 16),
            ]),
          ),
        ])),
      ]),
    );
  }

  Widget _buildQueueSheet(void Function(VoidCallback) setSheetState) {
    final queue = _service.queue.isNotEmpty ? _service.queue : _getFiltered();
    final scrollCtrl = ScrollController();
    final targetIndex = _service.queueIndex;

    // 定位到正在播放的歌曲
    if (targetIndex >= 0 && targetIndex < queue.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final itemHeight = 56.0;
        final offset = (targetIndex * itemHeight).clamp(0.0, scrollCtrl.position.maxScrollExtent);
        scrollCtrl.animateTo(offset, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });
    }

    return SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: Text('播放列表 (${queue.length}首)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      Expanded(child: queue.isEmpty ? const Center(child: Text('队列为空')) : ListView.builder(
        controller: scrollCtrl, itemCount: queue.length, itemBuilder: (_, i) {
        final s = queue[i]; final isCur = i == _service.queueIndex;
        return ListTile(
          leading: Icon(isCur ? Icons.play_arrow : Icons.music_note, color: isCur ? Colors.deepPurple : Colors.grey, size: 22),
          title: Text(s.title, style: TextStyle(fontSize: 14, fontWeight: isCur ? FontWeight.bold : FontWeight.normal)),
          onTap: () {
            if (_service.queue.isEmpty) _service.setQueue(_getFiltered(), startIndex: i);
            _service.playSong(s);
            setState(() {});
            setSheetState(() {});
            Navigator.pop(context);
          },
        );
      })),
    ]));
  }

  String _modeLabel(PlayMode m) { switch (m) { case PlayMode.sequential: return '顺序播放'; case PlayMode.loopList: return '列表循环'; case PlayMode.loopOne: return '单曲循环'; case PlayMode.shuffle: return '随机播放'; }}

  Widget _buildCover(Song song) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final f = File(song.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        return Image.file(f, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, e, s) {
          try { File('D:/pyProj/GoMusic/cover_debug.log').writeAsStringSync('ERRF url=${song.coverUrl} err=$e\n', mode: FileMode.append); } catch (_) {}
          return _icon();
        });
      }
    }
    return _icon();
  }

  Widget _icon() => const Icon(Icons.music_note, color: Colors.deepPurple, size: 28);
}
