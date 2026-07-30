import 'dart:async';
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
    if (widget.song != null) {
      _service.playSong(widget.song!);
    }
    _song = _service.currentSong;
    _isPlaying = _service.isPlaying;
    _checkFav();

    _stateSub = _service.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _isPlaying = s == PlayerState.playing);
    });
    _posSub = _service.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _service.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    super.dispose();
  }

  Future<void> _checkFav() async {
    if (_song != null) {
      final f = await AudioPlayerService.isFavorite(_song!.bvid);
      if (mounted) setState(() => _isFav = f);
    }
  }

  Future<void> _toggleFav() async {
    if (_song == null) return;
    await AudioPlayerService.toggleFavorite(_song!.bvid);
    setState(() => _isFav = !_isFav);
  }

  void _showQueueSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _QueueSheet(player: _service),
    );
  }

  void _showModeMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ModeSheet(player: _service),
    );
  }

  @override
  Widget build(BuildContext context) {
    _song = _service.currentSong;
    if (_song == null) {
      return Scaffold(appBar: AppBar(title: const Text('')), body: const Center(child: Text('未在播放', style: TextStyle(color: Colors.grey))));
    }

    final progress = _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          if (_song!.hasVideo)
            TextButton.icon(onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (_) => VideoDetailPage(song: _song!))); }, icon: const Icon(Icons.ondemand_video, size: 16), label: const Text('源视频')),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          // 封面
          Container(
            width: 260, height: 260,
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(16)),
            child: Center(
              child: Icon(_song!.hasVideo ? Icons.play_circle_outline : Icons.album, size: 100, color: Colors.grey[600]),
            ),
          ),
          const Spacer(),
          // 歌曲信息
          Text(_song!.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_song!.uploader, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 24),
          // 进度条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
                child: Slider(value: progress, onChanged: (v) { _service.seek(_duration * v); }),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(_position), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(_fmt(_duration), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          // 播放控制
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.skip_previous, size: 44), onPressed: () { _service.prev(); setState(() { _song = _service.currentSong; _checkFav(); }); }),
            const SizedBox(width: 20),
            IconButton(icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle, size: 64, color: Colors.deepPurple), onPressed: () { _service.togglePause(); setState(() => _isPlaying = !_isPlaying); }),
            const SizedBox(width: 20),
            IconButton(icon: const Icon(Icons.skip_next, size: 44), onPressed: () { _service.next(); setState(() { _song = _service.currentSong; _checkFav(); }); }),
          ]),
          const SizedBox(height: 24),
          // 底部操作栏
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(icon: Icon(_isFav ? Icons.favorite : Icons.favorite_border, color: _isFav ? Colors.red : Colors.grey, size: 28), onPressed: _toggleFav),
            IconButton(icon: const Icon(Icons.queue_music, size: 28, color: Colors.grey), onPressed: _showQueueSheet),
            GestureDetector(onTap: _showModeMenu, child: Row(mainAxisSize: MainAxisSize.min, children: [Text(_service.playModeLabel, style: TextStyle(fontSize: 14, color: Colors.grey[600])), const Icon(Icons.arrow_drop_down, color: Colors.grey)])),
          ]),
          const Spacer(),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ==================== 播放队列底部弹窗 ====================

class _QueueSheet extends StatelessWidget {
  final AudioPlayerService player;
  const _QueueSheet({required this.player});

  @override
  Widget build(BuildContext context) {
    final queue = player.queue;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Text('播放列表 (${queue.length}首)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            _ModeButton(player: player),
          ]),
        ),
        Expanded(
          child: queue.isEmpty
              ? const Center(child: Text('队列为空', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: queue.length,
                  itemBuilder: (_, i) {
                    final s = queue[i];
                    final isCurrent = i == player.queueIndex;
                    return ListTile(
                      leading: Icon(isCurrent ? Icons.play_arrow : Icons.music_note, color: isCurrent ? Colors.deepPurple : Colors.grey, size: 24),
                      title: Text(s.title, style: TextStyle(fontSize: 14, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal), overflow: TextOverflow.ellipsis),
                      subtitle: Text(s.uploader, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () { player.removeFromQueue(i); Navigator.pop(context); }),
                      onTap: () { player.playSong(s); Navigator.pop(context); },
                    );
                  }),
        ),
      ]),
    );
  }
}

// ==================== 播放模式弹窗 ====================

class _ModeSheet extends StatelessWidget {
  final AudioPlayerService player;
  const _ModeSheet({required this.player});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: PlayMode.values.map((m) {
          final selected = player.playMode == m;
          return ListTile(
            leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? Colors.deepPurple : Colors.grey, size: 20),
            title: Text(player._modeLabel(m), style: TextStyle(color: selected ? Colors.deepPurple : null)),
            onTap: () { player.setPlayMode(m); Navigator.pop(context); },
          );
        }).toList(),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final AudioPlayerService player;
  const _ModeButton({required this.player});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))), builder: (_) => _ModeSheet(player: player));
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(player.playModeLabel, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const Icon(Icons.arrow_drop_down, color: Colors.grey),
      ]),
    );
  }
}

extension _ModeLabel on AudioPlayerService {
  String _modeLabel(PlayMode m) {
    switch (m) {
      case PlayMode.sequential: return '顺序播放';
      case PlayMode.loopList: return '列表循环';
      case PlayMode.loopOne: return '单曲循环';
      case PlayMode.shuffle: return '随机播放';
    }
  }
}
