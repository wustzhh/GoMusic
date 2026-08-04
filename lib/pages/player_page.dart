import 'dart:async';

import 'dart:io';

import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

import 'package:flutter/material.dart';

import '../models/music_data.dart';

import '../services/audio_player_service.dart';

import 'video_detail_page.dart';



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

    if (_song != null) {

      AudioPlayerService.isFavorite(_song!.filePath).then((f) { if (mounted) setState(() => _isFav = f); });

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

              await AudioPlayerService.toggleFavorite(_song!.filePath);

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

      context: context, isScrollControlled: true,

      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),

      builder: (_) => _QueueSheet(player: _service),

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

        if (_song!.hasVideo) TextButton.icon(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => VideoDetailPage(song: _song!))); }, icon: const Icon(Icons.ondemand_video, size: 16), label: const Text('源视频')),

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

            child: Slider(value: progress, onChanged: (v) => _service.seek(dur * v))),

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

          Stack(clipBehavior: Clip.none, children: [

            IconButton(icon: const Icon(Icons.playlist_add, size: 28, color: Colors.grey), onPressed: _addToList),

            if (_isFav) const Positioned(right: 2, bottom: 2, child: Icon(Icons.favorite, color: Colors.red, size: 10)),

          ]),

          IconButton(icon: const Icon(Icons.queue_music, size: 28, color: Colors.grey), onPressed: _showQueue),

          GestureDetector(onTap: _showModeMenu, child: Row(mainAxisSize: MainAxisSize.min, children: [

            Text(_service.playModeLabel, style: TextStyle(fontSize: 13, color: Colors.grey[600])),

            const Icon(Icons.arrow_drop_down, color: Colors.grey),

          ])),

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

  @override

  Widget build(BuildContext context) {

    final p = widget.player;

    var queue = p.queue;

    // 随机模式重新洗牌显示

    if (p.playMode == PlayMode.shuffle && queue.isNotEmpty) {

      queue = List.from(queue)..shuffle(Random(p.queueIndex));

    }

    return SizedBox(height: MediaQuery.of(context).size.height * 0.55, child: Column(children: [

      Padding(padding: const EdgeInsets.all(16), child: Row(children: [

        Text('播放列表 (${queue.length}首)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),

        const Spacer(), Text(p.playModeLabel, style: TextStyle(fontSize: 13, color: Colors.grey[600])),

      ])),

      Expanded(child: queue.isEmpty

        ? const Center(child: Text('队列为空'))

        : ListView.builder(itemCount: queue.length, itemBuilder: (_, i) {

            final s = queue[i]; final isCur = i == p.queueIndex;

            return ListTile(

              leading: Icon(isCur ? Icons.play_arrow : Icons.music_note, color: isCur ? Colors.deepPurple : Colors.grey, size: 22),

              title: Text(s.title, style: TextStyle(fontSize: 14, fontWeight: isCur ? FontWeight.bold : FontWeight.normal)),

              subtitle: Text(s.uploader, style: const TextStyle(fontSize: 12, color: Colors.grey)),

              trailing: IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () { p.removeFromQueue(i); setState(() {}); }),

              onTap: () { p.playSong(s); Navigator.pop(context); },

            );

          })),

    ]));

  }

}

