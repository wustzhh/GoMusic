import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _songs = List.from(widget.playlist.songs);
    _loadFavs();
    _service.currentSongNotifier.addListener(_onSongChanged);
    _service.onPositionChanged.listen((p) => setState(() => _position = p));
    _service.onDurationChanged.listen((d) => setState(() => _duration = d));
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

  void _showSongMenu(Song song, bool isFav) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : Colors.grey),
            title: Text(isFav ? '取消收藏' : '添加到我喜欢'),
            onTap: () { Navigator.pop(ctx); AudioPlayerService.toggleFavorite(song.filePath); _loadFavs(); }),
          ListTile(leading: const Icon(Icons.playlist_add), title: const Text('添加到歌单...'),
            onTap: () { Navigator.pop(ctx); _showAddToList(song); }),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('删除歌曲', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              _confirmDelete(song);
            }),
        ]),
      ),
    );
  }

  void _confirmDelete(Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌曲'),
        content: Text('确定要删除「${song.title}」吗？\n本地文件也将被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            _deleteSong(song);
          }, child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  void _deleteSong(Song song) {
    try {
      File(song.filePath).deleteSync();
      if (song.coverUrl != null) File(song.coverUrl!).deleteSync();
      SongManager.unregisterSong(song.filePath);
    } catch (_) {}
    _refresh();
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
                return GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: song.title));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('已复制: ${song.title}'),
                      behavior: SnackBarBehavior.floating,
                      margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 120, left: 20, right: 20),
                      duration: const Duration(seconds: 1),
                    ));
                  },
                  child: Container(
                    color: isPlaying ? Colors.deepPurple.withValues(alpha: 0.12) : Colors.transparent,
                    child: InkWell(
                      onTap: () => _playSong(song),
                      child: ListTile(
                        contentPadding: const EdgeInsets.only(left: 0, right: 4),
                        horizontalTitleGap: 8,
                        leading: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            _buildCover(song),
                            if (isFav)
                              Positioned(right: -4, bottom: -4,
                                child: Icon(Icons.favorite, color: Colors.red, size: 14)),
                          ],
                        ),
                        title: Text(song.title, style: TextStyle(fontSize: 14, fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(song.uploader.isNotEmpty ? song.uploader : (_service.isPlaying && isPlaying ? '正在播放' : ''), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        trailing: SizedBox(
                          width: 32, height: 32,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => _showSongMenu(song, isFav),
                              child: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              })),
        _buildBottomBar(),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final currentSong = _service.currentSong;
    final displaySong = currentSong ?? (_getFiltered().isNotEmpty ? _getFiltered().first : null);
    if (displaySong == null) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage())),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(6), child: _buildCoverSmall(displaySong)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(displaySong.title, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (displaySong.uploader.isNotEmpty)
                  Text(displaySong.uploader, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
          const SizedBox(width: 8),
          // 圆形进度播放按钮
          SizedBox(
            width: 40, height: 40,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0,
                strokeWidth: 2.5, color: Colors.deepPurple, backgroundColor: Colors.grey.withValues(alpha: 0.2),
              ),
              IconButton(
                icon: Icon(_service.isPlaying ? Icons.pause : Icons.play_arrow, size: 22, color: Colors.deepPurple),
                onPressed: () => _service.togglePause(),
                padding: EdgeInsets.zero,
              ),
            ]),
          ),
          IconButton(icon: const Icon(Icons.queue_music, size: 22, color: Colors.grey), onPressed: _showQueueSheet),
        ]),
      ),
    ),
    );

  }

  void _showQueueSheet() {
    final scrollCtrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final idx = _service.queueIndex;
      if (!scrollCtrl.hasClients || idx < 0) return;
      final target = (idx * 76.0 - scrollCtrl.position.viewportDimension / 2 + 38).clamp(0.0, scrollCtrl.position.maxScrollExtent);
      scrollCtrl.jumpTo(target);
    });
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(12), child: Row(children: [
              const Icon(Icons.drag_handle, color: Colors.grey, size: 24),
              const Spacer(),
              Text(_service.playModeLabel, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(width: 8),
              PopupMenuButton<PlayMode>(
                icon: const Icon(Icons.swap_horiz, color: Colors.grey, size: 20),
                onSelected: (m) { _service.setPlayMode(m); setState(() {}); },
                itemBuilder: (_) => PlayMode.values.map((m) => PopupMenuItem(
                  value: m,
                  child: Text(_modeLabel(m), style: TextStyle(
                    color: _service.playMode == m ? Colors.deepPurple : null,
                    fontWeight: _service.playMode == m ? FontWeight.bold : null,
                  )),
                )).toList(),
              ),
            ])),
            Expanded(child: ListView.builder(
              controller: scrollCtrl,
              itemCount: _service.queue.length,
              itemBuilder: (_, i) {
                final s = _service.queue[i]; final cur = i == _service.queueIndex;
                final tile = ListTile(
                  leading: Icon(cur ? Icons.play_arrow : Icons.music_note, color: cur ? Colors.red : Colors.grey, size: 20),
                  title: Text(s.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cur ? Colors.red : null), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () { _service.removeFromQueue(i); setState(() {}); }),
                );
                if (cur) {
                  return Container(color: Colors.red.withValues(alpha: 0.08), child: tile);
                }
                return InkWell(
                  onTap: () { _service.playSong(s); Navigator.pop(context); },
                  child: tile,
                );
              },
            )),
          ]),
        ),
      ),
    );
  }

  void _showModePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: PlayMode.values.map((m) {
          final sel = _service.playMode == m;
          return ListTile(
            leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? Colors.deepPurple : Colors.grey),
            title: Text(_modeLabel(m)),
            onTap: () { _service.setPlayMode(m); setState(() {}); Navigator.pop(context); },
          );
        }).toList()),
      ),
    );
  }

  String _modeLabel(PlayMode m) { switch (m) { case PlayMode.sequential: return '顺序播放'; case PlayMode.loopList: return '列表循环'; case PlayMode.loopOne: return '单曲循环'; case PlayMode.shuffle: return '随机播放'; }}

  Widget _buildCover(Song song) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final f = File(song.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(f, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, e, s) => _icon()));
      }
    }
    return _icon();
  }

  Widget _icon() => const Icon(Icons.music_note, color: Colors.deepPurple, size: 28);

  Widget _buildCoverSmall(Song song) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final f = File(song.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        try {
          return Image.file(f, width: 36, height: 36, fit: BoxFit.cover);
        } catch (_) {}
      }
    }
    return Icon(Icons.music_note, color: Colors.deepPurple, size: 24);
  }
}
