import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import 'player_page.dart';
import 'video_detail_page.dart';
import '../widgets/song_queue_list.dart';

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
  bool _batchMode = false;
  double _savedScrollOffset = 0; // 批量模式切换时的滚动位置（避免置顶）
  final Set<String> _selectedPaths = {};
  final ScrollController _mainScrollCtrl = ScrollController();
  final GlobalKey _playingRowKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _songs = List.from(widget.playlist.songs);
    // 从存储读取最新顺序（拖动排序持久化后重进歌单仍保持）：
    // local 读本地拖动顺序，自定义歌单读存储顺序；无保存顺序则用传入列表
    _applyPersistedOrder();
    // 同步播放队列为歌单顺序（非随机模式），不改动显示顺序
    if (_service.playMode != PlayMode.shuffle) {
      final curIdx = _songs.indexWhere((s) => _songKey(s) == (_service.currentSong != null ? _songKey(_service.currentSong!) : ""));
      _service.setQueue(_songs, startIndex: _songs.isEmpty ? 0 : curIdx.clamp(0, _songs.length - 1), playlistId: widget.playlist.id, keepOrder: true);
    }
    _loadFavs();
    _position = _service.currentPosition;
    _duration = _service.currentSong?.duration ?? Duration.zero;
    _service.currentSongNotifier.addListener(_onSongChanged);
    _service.onPositionChanged.listen((p) => setState(() => _position = p));
    _service.onDurationChanged.listen((d) => setState(() => _duration = d));
  }

  /// 应用持久化的拖动顺序（重进歌单时保持上次拖动结果）
  Future<void> _applyPersistedOrder() async {
    try {
      if (widget.playlist.id == 'local') {
        final order = await SongManager.getLocalOrder();
        if (order.isEmpty) return;
        final byKey = {for (final s in _songs) _songKey(s): s};
        final ordered = <Song>[];
        for (final k in order) {
          final s = byKey[k];
          if (s != null) { ordered.add(s); byKey.remove(k); }
        }
        ordered.addAll(byKey.values);
        _songs = ordered;
      } else if (widget.playlist.id == 'fav') {
        // 我喜欢：按收藏顺序（拖动排序已写入 favorites）排列
        final favs = await AudioPlayerService.getFavorites();
        if (favs.isEmpty) return;
        final byKey = {for (final s in _songs) _songKey(s): s};
        final ordered = <Song>[];
        for (final k in favs) {
          final s = byKey[k];
          if (s != null) { ordered.add(s); byKey.remove(k); }
        }
        ordered.addAll(byKey.values);
        _songs = ordered;
      } else if (widget.playlist.id != 'recent') {
        final pls = await PlaylistService.getPlaylists();
        final found = pls.where((p) => p.id == widget.playlist.id).firstOrNull;
        if (found == null || found.songs.isEmpty) return;
        // 自定义歌单：按存储顺序排列（补全信息用当前 _songs 的完整数据）
        final byKey = {for (final s in _songs) _songKey(s): s};
        _songs = found.songs
            .map((s) => byKey[s.bvid.isNotEmpty ? s.bvid : _songKey(s)] ?? s)
            .toList();
      }
      if (mounted) {
        if (_service.playMode != PlayMode.shuffle) {
          final curIdx = _songs.indexWhere((s) => _songKey(s) == (_service.currentSong != null ? _songKey(_service.currentSong!) : ""));
          _service.setQueue(_songs, startIndex: _songs.isEmpty ? 0 : curIdx.clamp(0, _songs.length - 1), playlistId: widget.playlist.id, keepOrder: true);
        }
        setState(() {});
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _service.currentSongNotifier.removeListener(_onSongChanged);
    super.dispose();
  }

  void _onSongChanged() {
    if (mounted) setState(() {
      _position = _service.currentPosition;
      final d = _service.currentSong?.duration;
      if (d != null && d.inMilliseconds > 0) _duration = d;
    });
  }

  Future<void> _loadFavs() async {
    final f = await AudioPlayerService.getFavorites();
    if (mounted) setState(() => _favs = f.toSet());
  }

  Future<void> _refresh() async {
    try {
      final svc = await SettingsService.getInstance();
      final dir = await svc.getDownloadPath();
      _cleanZeroFiles(dir);
      if (widget.playlist.id == 'local') {
        final scanned = await scanLocalAudioFiles(dir);
        // 拖动过则应用拖动顺序；否则按添加顺序（最后添加的放最上面，mtime 倒序）
        final order = await SongManager.getLocalOrder();
        if (order.isNotEmpty) {
          final byKey = {for (final s in scanned) _songKey(s): s};
          final ordered = <Song>[];
          for (final k in order) {
            final s = byKey[k];
            if (s != null) { ordered.add(s); byKey.remove(k); }
          }
          ordered.addAll(byKey.values);
          _songs = ordered;
        } else {
          _songs = scanned..sort((a, b) => _mtimeOf(b.filePath).compareTo(_mtimeOf(a.filePath)));
        }
      } else if (widget.playlist.id == 'fav') {
        // 我喜欢：只显示收藏的歌（按收藏顺序，含拖动排序），用扫描结果补全信息
        final all = await scanLocalAudioFiles(dir);
        final favs = await AudioPlayerService.getFavorites();
        final byKey = {for (final s in all) _songKey(s): s};
        final ordered = <Song>[];
        for (final k in favs) {
          final s = byKey[k];
          if (s != null) { ordered.add(s); byKey.remove(k); }
        }
        // 不追加未收藏的本地歌（移出后数量立即正确）
        _songs = ordered;
      } else {
      final pls = await PlaylistService.getPlaylists();
      final found = pls.where((p) => p.id == widget.playlist.id).firstOrNull;
      if (found != null) {
        // 补全：自定义歌单存的是BV号，用本地对照表查标题/封面
        final local = await scanLocalAudioFiles(dir);
        _songs = found.songs.map((s) {
          final bv = s.bvid.isNotEmpty ? s.bvid : _songKey(s);
          return local.where((x) => x.bvid == bv || _songKey(x) == bv).firstOrNull ?? s;
        }).toList();
      }
    }
    if (mounted) {
      // 进入歌单/刷新后同步队列为最新顺序（非随机模式），保证播放顺序和歌单一致
      if (_service.playMode != PlayMode.shuffle) {
        final curIdx = _songs.indexWhere((s) => _songKey(s) == (_service.currentSong != null ? _songKey(_service.currentSong!) : ""));
        _service.setQueue(_songs, startIndex: _songs.isEmpty ? 0 : curIdx.clamp(0, _songs.length - 1), playlistId: widget.playlist.id, keepOrder: true);
      }
      setState(() {});
    }
    } catch (_) {
      // 加载失败时保留初始列表
    }
  }

  void _cleanZeroFiles(String dir) {
    try { for (final f in Directory(dir).listSync()) { if (f is File && f.lengthSync() == 0) f.deleteSync(); } } catch (_) {}
  }

  void _playSong(Song song) {
    // 队列始终用完整歌单（搜索只是显示筛选，不影响播放列表）
    final idx = _songs.indexWhere((s) => _songKey(s) == _songKey(song));
    _service.setQueue(_songs, startIndex: idx, playlistId: widget.playlist.id, keepOrder: true);
    // 随机模式：点击的歌必须放到队列第一首（生成新播放列表后立即播放它）
    if (_service.playMode == PlayMode.shuffle) {
      _service.moveToFront(song);
    }
    _service.playSong(song);
    // 点击歌曲直接进入播放界面
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
    }
  }

  List<Song> _getFiltered() {
    if (_searchText.isEmpty) return _songs;
    return _songs.where((s) => s.title.toLowerCase().contains(_searchText.toLowerCase())).toList();
  }

  void _showAddToList(Song song) async {
    final existing = await PlaylistService.getPlaylists();
    // 一次性读取所有歌单的在列状态（避免每个歌单一次异步读，卡顿）
    final key = _songKey(song);
    final inList = <String, bool>{};
    for (final pl in existing) {
      inList[pl.id] = await PlaylistService.isSongInPlaylist(pl.id, key);
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('添加到收藏夹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ListTile(leading: const Icon(Icons.favorite, color: Colors.red, size: 24), title: const Text('我喜欢'),
          trailing: _favs.contains(key) ? const Icon(Icons.check, color: Colors.green) : null,
          onTap: () async { Navigator.pop(ctx); await AudioPlayerService.toggleFavorite(song); _loadFavs(); },
        ),
        ...existing.map((pl) => ListTile(leading: const Icon(Icons.list, color: Colors.grey, size: 22), title: Text(pl.name),
          trailing: (inList[pl.id] == true) ? const Icon(Icons.check, color: Colors.green) : null,
          onTap: () async { Navigator.pop(ctx); await PlaylistService.addSongToPlaylist(pl.id, key); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加到${pl.name}'))); },
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
            if (created != null) { await PlaylistService.addSongToPlaylist(created.id, _songKey(song)); }
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
          ListTile(leading: const Icon(Icons.playlist_play, color: Colors.deepPurple), title: const Text('下一首播放'),
            onTap: () { Navigator.pop(ctx); _service.playNext(song); }),
          ListTile(leading: const Icon(Icons.vertical_align_top, color: Colors.blue), title: const Text('置顶'),
            onTap: () { Navigator.pop(ctx); _pinSong(song); }),
          ListTile(leading: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : Colors.grey),
            title: Text(isFav ? '取消收藏' : '添加到我喜欢'),
            onTap: () { Navigator.pop(ctx); AudioPlayerService.toggleFavorite(song); _loadFavs(); }),
          ListTile(leading: const Icon(Icons.playlist_add), title: const Text('添加到歌单...'),
            onTap: () { Navigator.pop(ctx); _showAddToList(song); }),
          if (song.hasVideo && song.videoPath != null && song.videoPath!.isNotEmpty)
            ListTile(leading: const Icon(Icons.videocam_off_outlined, color: Colors.orange), title: const Text('删除视频', style: TextStyle(color: Colors.orange)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteVideo(song);
              }),
          if (widget.playlist.id == 'local')
            // 本地歌单：直接删除文件
            ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('删除歌曲', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(song);
              })
          else ...[
            // 其他歌单（我喜欢/自定义/最近播放）：移出歌单 + 移出并删除
            ListTile(leading: const Icon(Icons.playlist_remove, color: Colors.orange), title: const Text('移出歌单', style: TextStyle(color: Colors.orange)),
              onTap: () {
                Navigator.pop(ctx);
                _removeFromPlaylist(song);
              }),
            ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('移出并删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmRemoveAndDelete(song);
              }),
          ],
        ]),
      ),
    );
  }

  /// 单曲移出歌单（我喜欢=取消收藏；自定义=从存储移除；最近播放=从记录移除）
  Future<void> _removeFromPlaylist(Song song) async {
    final key = _songKey(song);
    if (widget.playlist.id == 'fav') {
      await AudioPlayerService.toggleFavorite(song);
      _refresh(); // 重建列表：移出的歌立即消失
    } else if (widget.playlist.id == 'recent') {
      RecentlyPlayedService.removeBvid(key);
      _refresh();
    } else {
      await PlaylistService.removeSongFromPlaylist(widget.playlist.id, key);
      _refresh();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已移出歌单'), duration: Duration(seconds: 1)));
    }
  }

  /// 移出并删除：先从歌单移除，再删本地文件
  Future<void> _confirmRemoveAndDelete(Song song) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移出并删除'),
        content: Text('确定将「${song.title}」移出歌单并删除本地文件吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _removeFromPlaylist(song);
    await _deleteSong(song);
  }

  void _confirmDelete(Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌曲'),
        content: Text('确定要删除「${song.title}」吗？\n本地文件也将被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () async {
            Navigator.pop(ctx);
            await _deleteSong(song);
          }, child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  /// 单独删除视频文件（保留音频）
  void _confirmDeleteVideo(Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除视频'),
        content: Text('确定要删除「${song.title}」的视频文件吗？\n音频保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            try {
              if (song.videoPath != null && song.videoPath!.isNotEmpty) {
                final f = File(song.videoPath!);
                if (f.existsSync()) f.deleteSync();
              }
              SongManager.registerVideoPath(song.filePath, '');
            } catch (_) {}
            _refresh();
            setState(() {});
          }, child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Future<void> _deleteSong(Song song) async {
    final key = _songKey(song);
    try {
      File(song.filePath).deleteSync();
      if (song.coverUrl != null) File(song.coverUrl!).deleteSync();
      if (song.videoPath != null && File(song.videoPath!).existsSync()) File(song.videoPath!).deleteSync();
      SongManager.unregisterSong(song.filePath);
    } catch (_) {}
    // 清理所有歌单里的记录：自定义歌单（await，确保完成）
    try {
      final pls = await PlaylistService.getPlaylists();
      for (final pl in pls) {
        await PlaylistService.removeSongFromPlaylist(pl.id, key);
      }
    } catch (_) {}
    // 清理"我喜欢"（无条件移除，不依赖本地缓存状态）
    try {
      await AudioPlayerService.removeFavorite(key);
    } catch (_) {}
    // 清理最近播放
    try {
      await RecentlyPlayedService.removeSong(key);
    } catch (_) {}
    // 清理组（从所有组中移除该歌曲）
    try {
      SongGroupService.removeSongFromGroups(key);
    } catch (_) {}
    // 清理播放队列
    _service.removeFromQueueByKey(key);
    _refresh();
  }

  /// 反转歌单：完全倒序并持久化（recent 由播放记录派生，不保存）
  void _reversePlaylist() {
    setState(() {
      _songs = _songs.reversed.toList();
      final newKeys = _songs.map((s) => s.bvid.isNotEmpty ? s.bvid : _songKey(s)).toList();
      if (widget.playlist.id == 'local') {
        SongManager.saveLocalOrder(newKeys);
      } else if (widget.playlist.id == 'fav') {
        AudioPlayerService.saveFavoritesOrder(newKeys);
      } else if (widget.playlist.id != 'recent') {
        PlaylistService.reorderSongsInPlaylist(widget.playlist.id, newKeys);
      }
    });
    // 同步播放队列顺序（非随机模式）
    if (_service.playMode != PlayMode.shuffle) {
      final curIdx = _songs.indexWhere((s) => _songKey(s) == (_service.currentSong != null ? _songKey(_service.currentSong!) : ""));
      _service.setQueue(_songs, startIndex: _songs.isEmpty ? 0 : curIdx.clamp(0, _songs.length - 1), playlistId: widget.playlist.id, keepOrder: true);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('歌单已反转'), duration: Duration(seconds: 1)));
    }
  }

  /// 置顶：把歌曲移到列表最前并持久化（recent 由播放记录派生，不保存）
  void _pinSong(Song song) {
    final key = _songKey(song);
    setState(() {
      _songs.removeWhere((s) => _songKey(s) == key);
      _songs.insert(0, song);
      final newKeys = _songs.map((s) => s.bvid.isNotEmpty ? s.bvid : _songKey(s)).toList();
      if (widget.playlist.id == 'local') {
        SongManager.saveLocalOrder(newKeys);
      } else if (widget.playlist.id == 'fav') {
        AudioPlayerService.saveFavoritesOrder(newKeys);
      } else if (widget.playlist.id != 'recent') {
        PlaylistService.reorderSongsInPlaylist(widget.playlist.id, newKeys);
      }
    });
    // 同步播放队列顺序（非随机模式）
    if (_service.playMode != PlayMode.shuffle) {
      final curIdx = _songs.indexWhere((s) => _songKey(s) == (_service.currentSong != null ? _songKey(_service.currentSong!) : ""));
      _service.setQueue(_songs, startIndex: _songs.isEmpty ? 0 : curIdx.clamp(0, _songs.length - 1), playlistId: widget.playlist.id, keepOrder: true);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已置顶'), duration: Duration(seconds: 1)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _getFiltered();
    return PopScope(
      // 批量模式下返回键 = 取消批量，不退出页面
      canPop: !_batchMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _batchMode) {
          setState(() { _batchMode = false; _selectedPaths.clear(); });
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('${widget.playlist.name} (${_songs.length}首)'),
        centerTitle: true,
        leading: _batchMode
            // 批量模式：返回箭头 = 取消批量（与系统返回键行为一致）
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '取消批量',
                onPressed: () => setState(() { _batchMode = false; _selectedPaths.clear(); }),
              )
            : null,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh, tooltip: '刷新'),
        ],
      ),
      body: Column(children: [
        if (widget.playlist.id != 'recent') ...[
        Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 0), child: TextField(
          decoration: InputDecoration(hintText: '搜索...', prefixIcon: const Icon(Icons.search, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8), isDense: true),
          onChanged: (v) => setState(() => _searchText = v),
        )),
        // 功能栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            if (!_batchMode) ...[
              _actionBtn(Icons.play_arrow, '播放全部', () {
                // 搜索只是显示筛选：播放队列始终为完整歌单
                if (_songs.isEmpty) return;
                _service.setQueue(_songs, startIndex: 0, playlistId: widget.playlist.id, keepOrder: true);
                // 随机模式：队列已随机化，播放随机后的第一首；否则按列表第一首
                _service.playSong(_service.playMode == PlayMode.shuffle ? _service.queue.first : _songs.first, forceRestart: true);
              }),
              _actionBtn(Icons.my_location, '定位', () {
                final idx = _getFiltered().indexWhere((s) => _songKey(s) == (_service.currentSong != null ? _songKey(_service.currentSong!) : ""));
                if (idx < 0) return;
                if (!_mainScrollCtrl.hasClients) return;
                final est = (idx * 64.0 - _mainScrollCtrl.position.viewportDimension / 2).clamp(0.0, _mainScrollCtrl.position.maxScrollExtent);
                _mainScrollCtrl.jumpTo(est);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final ctx = _playingRowKey.currentContext;
                  if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
                });
              }),
              // 播放模式：点击循环切换
              GestureDetector(
                onTap: () {
                  final modes = PlayMode.values;
                  final next = (modes.indexOf(_service.playMode) + 1) % modes.length;
                  _service.setPlayMode(modes[next]);
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      switch (_service.playMode) {
                        PlayMode.loopList => Icons.repeat,
                        PlayMode.loopOne => Icons.repeat_one,
                        PlayMode.sequential => Icons.playlist_play,
                        PlayMode.shuffle => Icons.shuffle,
                      },
                      size: 18,
                      color: Colors.deepPurple,
                    ),
                    Text(_service.playModeLabel, style: const TextStyle(fontSize: 9)),
                  ]),
                ),
              ),
            ],
            const Spacer(),
            if (_batchMode) ...[
              TextButton.icon(
                onPressed: () {
                  final all = _getFiltered();
                  final allSelected = all.every((s) => _selectedPaths.contains(_songKey(s)));
                  setState(() {
                    if (allSelected) {
                      _selectedPaths.clear();
                    } else {
                      _selectedPaths.addAll(all.map(_songKey));
                    }
                  });
                },
                icon: const Icon(Icons.select_all, size: 16),
                label: Text(_getFiltered().isNotEmpty && _getFiltered().every((s) => _selectedPaths.contains(_songKey(s))) ? '全消' : '全选', style: const TextStyle(fontSize: 11)),
              ),
            ],
            TextButton.icon(
              onPressed: () {
                // 进入/退出批量时记录并恢复滚动位置，避免切换列表类型导致置顶
                if (_mainScrollCtrl.hasClients) {
                  _savedScrollOffset = _mainScrollCtrl.offset;
                }
                setState(() { _batchMode = !_batchMode; _selectedPaths.clear(); });
                _restoreScrollAfterBatchToggle();
              },
              icon: Icon(_batchMode ? Icons.check_box : Icons.check_box_outline_blank, size: 16),
              label: Text(_batchMode ? '取消选择' : '批量', style: const TextStyle(fontSize: 11)),
            ),
          ]),
        ),
        // 批量操作栏：Wrap 换行，按钮永不消失/溢出
        if (_batchMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Wrap(spacing: 2, runSpacing: 2, children: [
              _batchBtn(Icons.playlist_add, '添加到', _batchAddTo),
              if (widget.playlist.id != 'local')
                _batchBtn(Icons.playlist_remove, '移出', _batchRemove),
              _batchBtn(Icons.group_add, '组队', _batchGroup),
              _batchBtn(Icons.swap_vert, '反转', _reversePlaylist),
              if (widget.playlist.id == 'local')
                _batchBtn(Icons.delete, '删除', _batchDelete, red: true),
            ]),
          ),
        const Divider(height: 1),
        ],
        Expanded(child: filtered.isEmpty
          ? const Center(child: Text('没有歌曲', style: TextStyle(color: Colors.grey)))
          : LayoutBuilder(builder: (ctx, cons) {
              // 批量模式：可拖动排序的平铺列表（每行带拖动手柄）
              if (_batchMode) {
                final searching = _searchText.isNotEmpty;
                final list = _getFiltered();
                if (searching) {
                  // 搜索状态下无拖动手柄，仅复选框选择
                  return ListView.builder(
                    controller: _mainScrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _buildSongItem(filtered[i]),
                  );
                }
                return ReorderableListView.builder(
                  scrollController: _mainScrollCtrl,
                  buildDefaultDragHandles: false, // 用拖动手柄触发，避免与行内手势冲突
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: list.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final moved = list.removeAt(oldIndex);
                      list.insert(newIndex, moved);
                      _songs = List<Song>.from(list);
                      // 持久化：本地/我喜欢/自定义歌单保存新顺序（recent 由播放记录派生，不保存）
                      final newKeys = list.map((s) => s.bvid.isNotEmpty ? s.bvid : _songKey(s)).toList();
                      if (widget.playlist.id == 'local') {
                        SongManager.saveLocalOrder(newKeys);
                      } else if (widget.playlist.id == 'fav') {
                        AudioPlayerService.saveFavoritesOrder(newKeys);
                      } else if (widget.playlist.id != 'recent') {
                        PlaylistService.reorderSongsInPlaylist(widget.playlist.id, newKeys);
                      }
                    });
                  },
                  itemBuilder: (_, i) => _buildSongItem(list[i], key: ValueKey(_songKey(list[i])), showDragHandle: true, dragIndex: i),
                );
              }
              final items = _buildGroupedItems(filtered);
              return ListView.builder(
                controller: _mainScrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: items.length,
                itemBuilder: (_, i) => items[i],
              );
            })),
        _buildBottomBar(),
      ]),
      ),
    );
  }


  /// 组优先 + 单曲在后；批量模式下行首为复选框+封面
  static const _groupColors = [
    Colors.amber, Colors.cyan, Colors.limeAccent, Colors.orangeAccent,
    Colors.pinkAccent, Colors.lightGreenAccent, Colors.tealAccent, Colors.redAccent,
    Colors.lightBlueAccent, Colors.purpleAccent,
  ];

  List<Widget> _buildGroupedItems(List<Song> filtered) {
    final items = <Widget>[];
    final used = <String>{};
    final isFlat = widget.playlist.id == 'recent'; // 最近播放纯列表；我喜欢显示组
    final groups = isFlat ? <SongGroup>[] : SongGroupService.getGroups(playlistId: widget.playlist.id);
    var gi = 0;
    // 按歌单顺序遍历：组内歌曲相邻并框住（位置=组首成员位置，不提前），单曲原位
    for (final s in filtered) {
      if (used.contains(_songKey(s))) continue;
      final g = groups.where((g) => g.songPaths.contains(_songKey(s))).firstOrNull;
      if (g != null) {
        final members = g.songPaths
            .map((p) => filtered.where((x) => x.bvid == p || _songKey(x) == p).firstOrNull)
            .whereType<Song>()
            .toList();
        if (members.isEmpty) continue;
        final color = _groupColors[gi % _groupColors.length];
        gi++;
        items.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(8),
            color: color.withValues(alpha: 0.08),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Icon(Icons.group, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(g.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${members.length}首', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                IconButton(
                  icon: Icon(g.shuffle ? Icons.shuffle : Icons.swap_horiz, size: 14, color: color),
                  tooltip: '', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () { SongGroupService.setGroupShuffle(g.id, !g.shuffle); setState(() {}); },
                ),
                IconButton(
                  icon: const Icon(Icons.undo, size: 14, color: Colors.grey),
                  tooltip: '', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _confirmUngroup(g.id),
                ),
              ]),
            ),
            const Divider(height: 1, color: Colors.white12),
            ...members.map((m) { used.add(_songKey(m)); return _buildSongItem(m); }),
          ]),
        ));
      } else {
        used.add(_songKey(s));
        items.add(_buildSongItem(s));
      }
    }
    return items;
  }

  void _confirmUngroup(String groupId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解散小组'),
        content: const Text('确定解散该小组吗？组内歌曲将恢复为独立歌曲。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              SongGroupService.ungroup(groupId);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('解散'),
          ),
        ],
      ),
    );
  }

  /// 批量模式切换后恢复滚动位置（避免切换列表类型导致置顶）
  void _restoreScrollAfterBatchToggle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _mainScrollCtrl.hasClients) {
        _mainScrollCtrl.jumpTo(_savedScrollOffset.clamp(0, _mainScrollCtrl.position.maxScrollExtent));
      }
    });
  }

  /// 退出批量模式并保持滚动位置
  void _exitBatchMode() {
    if (_mainScrollCtrl.hasClients) _savedScrollOffset = _mainScrollCtrl.offset;
    setState(() { _batchMode = false; _selectedPaths.clear(); });
    _restoreScrollAfterBatchToggle();
  }

  Widget _buildSongItem(Song song, {Key? key, bool showDragHandle = false, int? dragIndex}) {
    final isFav = _favs.contains(_songKey(song));
    final isPlaying = _service.currentSong?.filePath == song.filePath;
    final selected = _selectedPaths.contains(_songKey(song));
    return GestureDetector(
      key: key,
      onTap: _batchMode ? () => setState(() { if (selected) _selectedPaths.remove(_songKey(song)); else _selectedPaths.add(_songKey(song)); }) : null,
      // 批量模式下长按用于拖动（由拖动手柄触发），不拦截为复制；非批量模式保留复制
      onLongPress: _batchMode
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: song.title));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('已复制: ${song.title}'),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.only(bottom: MediaQuery.of(context).size.height - 120, left: 20, right: 20),
                duration: const Duration(seconds: 1),
              ));
            },
      child: Container(
        key: isPlaying ? _playingRowKey : null,
        color: selected ? Colors.deepPurple.withValues(alpha: 0.15) : (isPlaying ? Colors.lightBlue.withValues(alpha: 0.3) : Colors.transparent),
        child: InkWell(
          onTap: _batchMode ? () => setState(() { if (selected) _selectedPaths.remove(_songKey(song)); else _selectedPaths.add(_songKey(song)); }) : () => _playSong(song),
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 0, right: 4),
            horizontalTitleGap: 8,
            leading: _batchMode
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                    value: selected,
                    onChanged: (v) => setState(() { if (v == true) _selectedPaths.add(_songKey(song)); else _selectedPaths.remove(_songKey(song)); }),
                    visualDensity: VisualDensity.compact,
                  ),
                  _buildCover(song),
                ])
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildCover(song),
                    if (isFav)
                      Positioned(right: -4, bottom: -4,
                        child: Icon(Icons.favorite, color: Colors.red, size: 14)),
                  ],
                ),
            title: Text(song.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isPlaying ? Colors.red : null), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(song.uploader.isNotEmpty ? song.uploader : (_service.isPlaying && isPlaying ? '正在播放' : ''), style: const TextStyle(fontSize: 11, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: _batchMode
              ? (showDragHandle && dragIndex != null
                  ? ReorderableDragStartListener(
                      index: dragIndex,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Icon(Icons.drag_handle, color: Colors.grey, size: 22),
                      ),
                    )
                  : null)
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  if (song.hasVideo)
                    SizedBox(
                      width: 32, height: 32,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoDetailPage(song: song))),
                          child: const Icon(Icons.ondemand_video, color: Colors.grey, size: 20),
                        ),
                      ),
                    ),
                  SizedBox(
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
                ]),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final currentSong = _service.currentSong;
    final displaySong = currentSong ?? (_songs.isNotEmpty ? _songs.first : null);
    if (displaySong == null) return const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        // 当前无歌：先恢复上次进度；无记录则播放歌单第一首（队列为完整歌单）
        if (_service.currentSong == null) {
          await _service.restoreLastSong();
          if (_service.currentSong == null) {
            final first = _songs.isNotEmpty ? _songs.first : null;
            if (first != null) {
              _service.setQueue(_songs, startIndex: 0, playlistId: widget.playlist.id, keepOrder: true);
              _service.playSong(_service.playMode == PlayMode.shuffle ? _service.queue.first : first);
            }
          }
        }
        if (!mounted || _service.currentSong == null) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
      },
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
    final targetKey = GlobalKey();
    void locate() {
      final curSong = _service.currentSong;
      if (curSong == null || !scrollCtrl.hasClients) return;
      final idx = _service.queue.indexWhere((s) => s.title == curSong.title);
      if (idx < 0) return;
      final est = (idx * 64.0 - scrollCtrl.position.viewportDimension / 2).clamp(0.0, scrollCtrl.position.maxScrollExtent);
      scrollCtrl.jumpTo(est);
      int tries = 0;
      void loop() {
        if (tries++ > 10) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = targetKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
            return;
          }
          scrollCtrl.jumpTo((scrollCtrl.offset + scrollCtrl.position.viewportDimension * 0.7).clamp(0.0, scrollCtrl.position.maxScrollExtent));
          loop();
        });
      }
      loop();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => locate());
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => ConstrainedBox(
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
              GestureDetector(
                onTap: () {
                  final modes = PlayMode.values;
                  final next = (modes.indexOf(_service.playMode) + 1) % modes.length;
                  _service.setPlayMode(modes[next]);
                  setSheetState(() {});
                  WidgetsBinding.instance.addPostFrameCallback((_) => locate());
                },
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_service.playModeLabel, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(width: 6),
                  const Icon(Icons.swap_horiz, color: Colors.grey, size: 20),
                ]),
              ),
            ])),
            Expanded(child: _service.queue.isEmpty
              ? const Center(child: Text('队列为空', style: TextStyle(color: Colors.grey)))
              : SongQueueList(
                  queue: _service.queue,
                  currentIndex: _service.queueIndex,
                  currentTitle: _service.currentSong?.title,
                  currentBvid: _service.currentSong?.bvid,
                  playlistId: _service.currentPlaylistId,
                  onPlay: (s) { _service.playSong(s); Navigator.pop(context); },
                  onRemove: (i) { _service.removeFromQueue(i); setState(() {}); },
                )),
          ]),
        ),
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

  Widget _queueCover(Song s, bool cur) {
    if (s.coverUrl != null && s.coverUrl!.isNotEmpty) {
      final f = File(s.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(f, width: 34, height: 34, fit: BoxFit.cover));
      }
    }
    return Icon(cur ? Icons.play_arrow : Icons.music_note, color: cur ? Colors.red : Colors.grey, size: 20);
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: Colors.deepPurple),
          Text(label, style: const TextStyle(fontSize: 9)),
        ]),
      ),
    );
  }

  /// 批量操作按钮（底部操作栏用，Wrap 换行）
  Widget _batchBtn(IconData icon, String label, VoidCallback onTap, {bool red = false}) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: red ? Colors.red : Colors.deepPurple),
      label: Text(label, style: TextStyle(fontSize: 11, color: red ? Colors.red : null)),
    );
  }


  String _songKey(Song s) {
    if (s.bvid.isNotEmpty) return s.bvid;
    final name = s.filePath.split('\\').last.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 文件修改时间（不存在返回 epoch）
  DateTime _mtimeOf(String path) {
    try {
      final f = File(path);
      return f.existsSync() ? f.statSync().modified : DateTime.fromMillisecondsSinceEpoch(0);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  List<Song> _selectedSongs() {
    final f = _getFiltered();
    return f.where((s) => _selectedPaths.contains(_songKey(s))).toList();
  }

  // 批量：添加到歌单
  void _batchAddTo() async {
    final sel = _selectedSongs();
    if (sel.isEmpty) return;
    final pls = await PlaylistService.getPlaylists();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(padding: EdgeInsets.all(12), child: Text('添加到歌单', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.favorite, color: Colors.red, size: 20),
          title: const Text('我喜欢', style: TextStyle(fontSize: 14)),
          onTap: () async {
            await AudioPlayerService.addFavoritesBatch(sel);
            Navigator.pop(ctx);
            if (mounted) { _exitBatchMode(); _loadFavs(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加到我喜欢'))); }
          },
        ),
        ...pls.map((pl) => ListTile(
          leading: Text(pl.icon, style: const TextStyle(fontSize: 20)),
          title: Text(pl.name, style: const TextStyle(fontSize: 14)),
          onTap: () async {
            await PlaylistService.addSongsToPlaylist(pl.id, sel.map(_songKey).toList());
            Navigator.pop(ctx);
            if (mounted) { _exitBatchMode(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已添加到${pl.name}'))); }
          },
        )),
      ])),
    );
  }

  // 批量：从当前歌单移出
  void _batchRemove() {
    final sel = _selectedSongs();
    if (sel.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移出歌单'),
        content: Text('确定将选中的 ${sel.length} 首歌曲从「${widget.playlist.name}」移出吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () async {
            if (widget.playlist.id == 'fav') {
              // "我喜欢"：移出 = 取消收藏
              for (final s in sel) {
                await AudioPlayerService.toggleFavorite(s);
              }
            } else {
              // 自定义歌单：从歌单存储中移除
              for (final s in sel) {
                await PlaylistService.removeSongFromPlaylist(widget.playlist.id, _songKey(s));
              }
            }
            Navigator.pop(ctx);
            _refresh();
            if (mounted) _exitBatchMode();
          }, child: const Text('移出')),
        ],
      ),
    );
  }

  // 批量：删除本地歌曲文件（仅本地歌单，二次确认）
  void _batchDelete() {
    final sel = _selectedSongs();
    if (sel.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌曲'),
        content: Text('确定删除选中的 ${sel.length} 首歌曲吗？\n本地文件将被永久删除！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              for (final s in sel) {
                await _deleteSong(s);
              }
              Navigator.pop(ctx);
              _refresh();
              if (mounted) _exitBatchMode();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // 批量：组队（生成组，后续组逻辑由组系统处理）
  void _batchGroup() {
    final sel = _selectedSongs();
    if (sel.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请至少选择2首歌组队')));
      return;
    }
    SongGroupService.groupSongs(sel, playlistId: widget.playlist.id);
    if (mounted) {
      _exitBatchMode();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已创建小组（${sel.length}首）')));
    }
  }
}
