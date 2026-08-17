import 'dart:async';

import 'dart:io';

import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';

import '../models/music_data.dart';

import '../services/audio_player_service.dart';

import 'video_player_page.dart';
import '../widgets/song_queue_list.dart';



class PlayerPage extends StatefulWidget {

  final Song? song;

  const PlayerPage({super.key, this.song});

  @override

  State<PlayerPage> createState() => _PlayerPageState();

}



class _PlayerPageState extends State<PlayerPage> with SingleTickerProviderStateMixin {

  final _service = AudioPlayerService();

  // 流光/呼吸动画控制器：播放时持续旋转流光与封面呼吸
  late final AnimationController _fxController;

  Song? _song;

  bool _isPlaying = false;

  Duration _position = Duration.zero;

  Duration _duration = Duration.zero;

  bool _isFav = false;

  StreamSubscription? _stateSub, _posSub, _durSub;



  @override

  void initState() {

    super.initState();

    _fxController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );

    if (widget.song != null) _service.playSong(widget.song!);

    _refresh();

    _stateSub = _service.onPlayingChanged.listen((playing) {

      if (mounted) setState(() { _isPlaying = playing; _refresh(); });
      _syncFx(playing);

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

      AudioPlayerService.getFavorites().then((l) => l.contains(_song!.bvid.isNotEmpty ? _song!.bvid : _song!.filePath.split("\\").last.split("/").last.split(".").first)).then((f) { if (mounted) setState(() => _isFav = f); });

    }

  }



  @override

  void dispose() { _stateSub?.cancel(); _posSub?.cancel(); _durSub?.cancel(); _fxController.dispose(); super.dispose(); }



  /// 播放时流光旋转+封面呼吸，暂停时停住（保持当前角度不闪变）
  void _syncFx(bool playing) {
    if (playing) {
      if (!_fxController.isAnimating) _fxController.repeat();
    } else {
      _fxController.stop();
    }
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




  @override

  Widget build(BuildContext context) {

    if (_song == null) return Scaffold(backgroundColor: Colors.transparent, appBar: AppBar(title: const Text('')), body: const Center(child: Text('未在播放')));

    final dur = _duration.inMilliseconds > 0 ? _duration : (_song?.duration ?? Duration.zero);
    final progress = dur.inMilliseconds > 0 ? _position.inMilliseconds / dur.inMilliseconds : 0.0;

    if (!_fxController.isAnimating && _isPlaying) _fxController.repeat();



    return Scaffold(
      backgroundColor: Colors.transparent, // 透出全局动态背景

      appBar: AppBar(title: const Text(''), actions: [

        if (_song!.hasVideo) IconButton(icon: const Icon(Icons.ondemand_video, size: 20, color: Colors.grey), onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerPage(song: _song!))); }, tooltip: ''),

      ]),

      body: Column(mainAxisAlignment: MainAxisAlignment.center, children: [

        const Spacer(),

        // 封面：流光旋转边框 + 播放时呼吸，点击大图无动作
        AnimatedBuilder(
          animation: _fxController,
          builder: (context, _) {
            final breathe = _isPlaying ? 1.0 + 0.015 * sin(_fxController.value * pi * 2) : 1.0;
            return Transform.scale(
              scale: breathe,
              child: _GlowBorder(
                active: _isPlaying,
                angle: _fxController.value * pi * 2,
                child: Container(width: 260, height: 260, margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias, child: _buildCover(_song!),
                ),
              ),
            );
          },
        ),

        const Spacer(),

        Text(_song!.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),

        const SizedBox(height: 4),

        Text(_song!.uploader, style: const TextStyle(fontSize: 14, color: Colors.grey)),

        const SizedBox(height: 24),

        Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Column(children: [

          SliderTheme(data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),

            child: Slider(
              value: progress,
              onChangeStart: (_) {
                // 拖动中暂停，避免出声
                if (_service.isPlaying) {
                  _service.pause();
                }
              },
              onChanged: (v) {
                // 拖动中只更新 UI，不 seek 不出声
                setState(() => _position = dur * v);
              },
              onChangeEnd: (v) {
                // 拖动结束：seek 到目标位置并开始播放
                _service.seek(dur * v);
                _service.resume();
                setState(() => _isPlaying = true);
              },
            )),

          Padding(padding: const EdgeInsets.symmetric(horizontal: 8),

            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [

              Text(_fmt(_position), style: const TextStyle(fontSize: 12, color: Colors.grey)),

              Text(_fmt(dur), style: const TextStyle(fontSize: 12, color: Colors.grey)),

            ])),

        ])),

        const SizedBox(height: 24),

        Row(mainAxisAlignment: MainAxisAlignment.center, children: [

          _TapScale(child: IconButton(icon: const Icon(Icons.skip_previous, size: 44), onPressed: () { _service.prev(); setState(() {}); })),

          const SizedBox(width: 20),

          _TapScale(child: IconButton(icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle, size: 64, color: Theme.of(context).colorScheme.primary),

            onPressed: () { _service.togglePause(); setState(() => _isPlaying = !_isPlaying); _syncFx(!_isPlaying); })),

          const SizedBox(width: 20),

          _TapScale(child: IconButton(icon: const Icon(Icons.skip_next, size: 44), onPressed: () { _service.next(); setState(() {}); })),

        ]),

        const SizedBox(height: 24),

        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [

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

          IconButton(
            icon: Icon(_isFav ? Icons.favorite : Icons.favorite_border, size: 28, color: _isFav ? Colors.red : Colors.grey),
            onPressed: () async {
              if (_song == null) return;
              await AudioPlayerService.toggleFavorite(_song!);
              setState(() => _isFav = !_isFav);
            },
          ),

          IconButton(icon: const Icon(Icons.queue_music, size: 28, color: Colors.grey), onPressed: _showQueue),

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
            Icon(switch (widget.player.playMode) {
              PlayMode.loopList => Icons.repeat,
              PlayMode.loopOne => Icons.repeat_one,
              PlayMode.sequential => Icons.playlist_play,
              PlayMode.shuffle => Icons.shuffle,
            }, color: Colors.grey, size: 16),
          ]),
        ),

      ])),

      Expanded(child: queue.isEmpty

        ? const Center(child: Text('队列为空'))

        : SongQueueList(
            queue: queue,
            currentIndex: p.queueIndex,
            currentTitle: p.currentSong?.title,
            currentBvid: p.currentSong?.bvid,
            playlistId: p.currentPlaylistId,
            onPlay: (s) { p.playSong(s); Navigator.pop(context); },
            onRemove: (i) { p.removeFromQueue(i); setState(() {}); },
          )),

    ]));

  }

}


/// 流光边框：播放时一束渐变光绕封面旋转（暂停停住并弱化），
/// 光色跟随当前皮肤强调色。
class _GlowBorder extends StatelessWidget {
  final bool active;
  final double angle;
  final Widget child;

  const _GlowBorder({required this.active, required this.angle, required this.child});

  @override
  Widget build(BuildContext context) {
    final accent = skinNotifier.value.accent;
    final alpha = active ? 0.95 : 0.35;
    final border = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Transform.rotate(
        angle: angle,
        child: Container(
          decoration: BoxDecoration(
            gradient: SweepGradient(
              colors: [
                accent.withValues(alpha: 0),
                accent.withValues(alpha: alpha),
                accent.withValues(alpha: 0),
                accent.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.13, 0.42, 1.0],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Stack(fit: StackFit.passthrough, children: [
        Positioned.fill(child: border),
        child,
      ]),
    );
  }
}

/// 点击缩放动画：按下回弹（1→0.86→1.05→1），包在 IconButton 外层，
/// 不拦截子级点击事件（两者同时触发）。
class _TapScale extends StatefulWidget {
  final Widget child;
  const _TapScale({required this.child});
  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 0.86).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.86, end: 1.04).chain(CurveTween(curve: Curves.easeOutBack)),
      weight: 60,
    ),
  ]).animate(_controller);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _controller.forward(from: 0),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
