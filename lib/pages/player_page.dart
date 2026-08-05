import 'dart:async';

import 'dart:io';

import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

import 'package:flutter/material.dart';

import '../models/music_data.dart';

import '../services/audio_player_service.dart';

import 'video_detail_page.dart';
import '../widgets/song_queue_list.dart';
import '../widgets/song_queue_list.dart';



class PlayerPage extends StatefulWidget {

  final Song? song;

  const PlayerPage({super.key, this.song});

  @override

  State<PlayerPage> createState() => _PlayerPageState();

}



class _PlayerPageState extends State<PlayerPage> {

  final _service = AudioPlayerService();

  Song? _song;

  bool _isPlaying = false;

  Duration _position = Duration.zero;

  Duration _duration = Duration.zero;

  bool _isFav = false;

  StreamSubscription? _stateSub, _posSub, _durSub;



  @override

  void initState() {

    super.initState();

    if (widget.song != null) _service.playSong(widget.song!);

    _refresh();

    _stateSub = _service.onPlayingChanged.listen((playing) {

      if (mounted) setState(() { _isPlaying = playing; _refresh(); });

    });

    _posSub = _service.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });

    _durSub = _service.onDurationChanged.listen((d) { if (mounted) setState(() => _duration = d); });

    _service.currentSongNotifier.addListener(() { if (mounted) { setState(() {}); _refresh(); } });

  }



  void _refresh() {

    _song = _service.currentSong;

    _isPlaying = _service.isPlaying;

    _position = _service.currentPosition;

    if (_song != null) {

      AudioPlayerService.getFavorites().then((l) => l.contains(_song!.filePath)).then((f) { if (mounted) setState(() => _isFav = f); });

    }

  }



  @override

  void dispose() { _stateSub?.cancel(); _posSub?.cancel(); _durSub?.cancel(); super.dispose(); }



  void _addToList() async {

    if (_song == null) return;

    final existing = await PlaylistService.getPlaylists();



    showModalBottomSheet(

      context: context,

      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),

      builder: (ctx) => Padding(

        padding: const EdgeInsets.all(16),

        child: Column(mainAxisSize: MainAxisSize.min, children: [

          const Text('添加到收藏夹', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

          const SizedBox(height: 12),

          ListTile(

            leading: const Icon(Icons.favorite, color: Colors.red, size: 24),

            title: const Text('我喜欢'),

            trailing: _isFav ? const Icon(Icons.check, color: Colors.green) : null,

            onTap: () async {

              Navigator.pop(ctx);

              await AudioPlayerService.toggleFavorite(_song!);

              setState(() => _isFav = !_isFav);

            },

          ),

          ...existing.map((pl) => FutureBuilder<bool>(

            future: PlaylistService.isSongInPlaylist(pl.id, _song!.filePath),

            builder: (_, snap) => ListTile(

              leading: const Icon(Icons.list, color: Colors.grey, size: 22),

              title: Text(pl.name),

              trailing: (snap.data == true) ? const Icon(Icons.check, color: Colors.green) : null,

              onTap: () async {

                Navigator.pop(ctx);

                await PlaylistService.addSongToPlaylist(pl.id, _song!.filePath);

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

              _showNewList();

            },

          ),

        ]),

      ),

    );

  }



  void _showNewList() {

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

              final pls = await PlaylistService.getPlaylists();

              final created = pls.where((p) => p.name == ctrl.text.trim()).firstOrNull;

              if (created != null) {

                await PlaylistService.addSongToPlaylist(created.id, _song!.filePath);

              }

              Navigator.pop(ctx);

              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已创建并添加')));

            }

          }, child: const Text('创建')),

        ],

      ),

    );

  }



  void _showQueue() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      isDismissible: true,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
        child: _QueueSheet(player: _service),
      ),
    );
  }




  void _showModeMenu() {

    showModalBottomSheet(

      context: context,

      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),

      builder: (_) => Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: PlayMode.values.map((m) {

        final sel = _service.playMode == m;

        return ListTile(

          leading: Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? Colors.deepPurple : Colors.grey, size: 20),

          title: Text(_label(m)),

          onTap: () { _service.setPlayMode(m); setState(() {}); Navigator.pop(context); },

        );

      }).toList())),

    );

  }



  String _label(PlayMode m) { switch (m) { case PlayMode.sequential: return '顺序播放'; case PlayMode.loopList: return '列表循环'; case PlayMode.loopOne: return '单曲循环'; case PlayMode.shuffle: return '随机播放'; }}



  @override

  Widget build(BuildContext context) {

    if (_song == null) return Scaffold(appBar: AppBar(title: const Text('')), body: const Center(child: Text('未在播放')));

    final dur = _duration.inMilliseconds > 0 ? _duration : (_song?.duration ?? Duration.zero);
    final progress = dur.inMilliseconds > 0 ? _position.inMilliseconds / dur.inMilliseconds : 0.0;



    return Scaffold(

      appBar: AppBar(title: const Text(''), actions: [

        if (_song!.hasVideo) IconButton(icon: const Icon(Icons.ondemand_video, size: 20, color: Colors.grey), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => VideoDetailPage(song: _song!))); }, tooltip: ''),

      ]),

      body: Column(mainAxisAlignment: MainAxisAlignment.center, children: [

        const Spacer(),

        Container(width: 260, height: 260, margin: const EdgeInsets.symmetric(horizontal: 40),

          decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(16)),

          clipBehavior: Clip.antiAlias, child: _buildCover(_song!),

        ),

        const Spacer(),

        Text(_song!.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),

        const SizedBox(height: 4),

        Text(_song!.uploader, style: const TextStyle(fontSize: 14, color: Colors.grey)),

        const SizedBox(height: 24),

        Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(children: [

          SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),

            child: Slider(value: progress, onChanged: (v) {
              _service.seek(dur * v);
              _service.resume();
              setState(() => _isPlaying = true);
            })),

          Padding(padding: const EdgeInsets.symmetric(horizontal: 8),

            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [

              Text(_fmt(_position), style: const TextStyle(fontSize: 12, color: Colors.grey)),

              Text(_fmt(dur), style: const TextStyle(fontSize: 12, color: Colors.grey)),

            ])),

        ])),

        const SizedBox(height: 24),

        Row(mainAxisAlignment: MainAxisAlignment.center, children: [

          IconButton(icon: const Icon(Icons.skip_previous, size: 44), onPressed: () { _service.prev(); setState(() {}); }),

          const SizedBox(width: 20),

          IconButton(icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle, size: 64, color: Colors.deepPurple),

            onPressed: () { _service.togglePause(); setState(() => _isPlaying = !_isPlaying); }),

          const SizedBox(width: 20),

          IconButton(icon: const Icon(Icons.skip_next, size: 44), onPressed: () { _service.next(); setState(() {}); }),

        ]),

        const SizedBox(height: 24),

        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [

          IconButton(
            icon: Icon(_isFav ? Icons.favorite : Icons.favorite_border, size: 28, color: _isFav ? Colors.red : Colors.grey),
            onPressed: () async {
              if (_song == null) return;
              await AudioPlayerService.toggleFavorite(_song!);
              setState(() => _isFav = !_isFav);
            },
          ),

          IconButton(icon: const Icon(Icons.queue_music, size: 28, color: Colors.grey), onPressed: _showQueue),

          GestureDetector(
            onTap: () {
              final modes = PlayMode.values;
              final next = (modes.indexOf(_service.playMode) + 1) % modes.length;
              _service.setPlayMode(modes[next]);
              setState(() {});
            },
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_service.playModeLabel, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              const SizedBox(width: 4),
              const Icon(Icons.swap_horiz, color: Colors.grey, size: 16),
            ]),
          ),

        ]),

        const Spacer(),

      ]),

    );

  }



  Widget _buildCover(Song song) {

    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {

      final f = File(song.coverUrl!);

      if (f.existsSync() && f.lengthSync() > 0) {

        

          

          return ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(f, fit: BoxFit.cover));

        

      }

    }

    return Center(child: Icon(Icons.album, size: 100, color: Colors.grey[600]));

  }



  String _fmt(Duration d) {

    final m = d.inMinutes.toString().padLeft(2, '0');

    final s = (d.inSeconds % 60).toString().padLeft(2, '0');

    return '$m:$s';

  }

}



// 队列弹窗

class _QueueSheet extends StatefulWidget {

  final AudioPlayerService player;

  const _QueueSheet({required this.player});

  @override

  State<_QueueSheet> createState() => _QueueSheetState();

}

class _QueueSheetState extends State<_QueueSheet> {
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _targetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.player.currentSongNotifier.addListener(() { if (mounted) setState(() {}); WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget()); });
    _scrollToTarget();
  }

  void _scrollToTarget() {
    // 歌名定位：找 title 与当前播放歌曲一致的 item
    final curSong = widget.player.currentSong;
    if (curSong == null) return;
    final idx = widget.player.queue.indexWhere((s) => s.title == curSong.title);
    if (idx < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      // 先估计跳到目标附近
      final est = (idx * 64.0 - _scrollCtrl.position.viewportDimension / 2).clamp(0.0, _scrollCtrl.position.maxScrollExtent);
      _scrollCtrl.jumpTo(est);
      // 循环逼近直到目标item渲染出来，再ensureVisible
      int tries = 0;
      void locate() {
        if (tries++ > 10) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _targetKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
            return;
          }
          // 还没渲染：向前翻一页
          _scrollCtrl.jumpTo((_scrollCtrl.offset + _scrollCtrl.position.viewportDimension * 0.7).clamp(0.0, _scrollCtrl.position.maxScrollExtent));
          locate();
        });
      }
      locate();
    });
  }

  Widget _queueCover(Song s, bool isCur) {
    if (s.coverUrl != null && s.coverUrl!.isNotEmpty) {
      final f = File(s.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(f, width: 34, height: 34, fit: BoxFit.cover));
      }
    }
    return Icon(isCur ? Icons.play_arrow : Icons.music_note, color: isCur ? Colors.red : Colors.grey, size: 22);
  }

  @override
  void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {

    final p = widget.player;

    final queue = p.queue;

    return SizedBox(height: MediaQuery.of(context).size.height * 0.55, child: Column(children: [

      Padding(padding: const EdgeInsets.all(16), child: Row(children: [

        Text('播放列表 (${queue.length}首)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

        const Spacer(),

        GestureDetector(
          onTap: () {
            final modes = PlayMode.values;
            final next = (modes.indexOf(widget.player.playMode) + 1) % modes.length;
            widget.player.setPlayMode(modes[next]);
            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.player.playModeLabel, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(width: 6),
            const Icon(Icons.swap_horiz, color: Colors.grey, size: 18),
          ]),
        ),

      ])),

      Expanded(child: queue.isEmpty

        ? const Center(child: Text('队列为空'))

        : SongQueueList(
            queue: queue,
            currentIndex: p.queueIndex,
            playlistId: p.currentPlaylistId,
            onPlay: (s) { p.playSong(s); Navigator.pop(context); },
            onRemove: (i) { p.removeFromQueue(i); setState(() {}); },
          )),

    ]));

  }

}

