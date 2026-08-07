import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../models/music_data.dart';

/// 视频播放器：播放/暂停/进度/倍速/全屏
class VideoPlayerPage extends StatefulWidget {
  final Song song;
  const VideoPlayerPage({super.key, required this.song});
  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final _player = Player();
  VideoController? _controller;
  StreamSubscription? _posSub, _durSub, _playingSub, _completeSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _speed = 1.0;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoController(_player);
    _playingSub = _player.stream.playing.listen((p) { if (mounted) setState(() => _playing = p); });
    _posSub = _player.stream.position.listen((p) { if (mounted) setState(() => _position = p); });
    _durSub = _player.stream.duration.listen((d) { if (mounted) setState(() => _duration = d); });
    _completeSub = _player.stream.completed.listen((_) { if (mounted) setState(() => _playing = false); });
    _open();
  }

  Future<void> _open() async {
    final path = widget.song.videoPath ?? widget.song.filePath;
    final f = File(path);
    if (!f.existsSync()) return;
    await _player.open(Media(f.path));
    await _player.setRate(_speed);
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.song.title, style: const TextStyle(fontSize: 15)), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.fullscreen, size: 20), tooltip: '', onPressed: () => setState(() => _fullscreen = !_fullscreen)),
      ]),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            Center(
              child: _controller == null
                  ? const CircularProgressIndicator()
                  : Video(
                      controller: _controller!,
                      controls: NoVideoControls,
                      wakelock: false,
                    ),
            ),
            // 点击切换播放/暂停
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_playing) { _player.pause(); } else { _player.play(); }
                },
                child: Icon(
                  _playing ? Icons.pause_circle : Icons.play_circle,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ]),
        ),
        // 控制栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(children: [
            Slider(
              value: _duration.inMilliseconds > 0 ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0) : 0,
              onChanged: (v) => _player.seek(Duration(milliseconds: (v * _duration.inMilliseconds).round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Text(_fmt(_position), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                Text(_fmt(_duration), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
            ),
            Row(children: [
              IconButton(icon: const Icon(Icons.replay_10, size: 24), tooltip: '', onPressed: () => _player.seek(_position - const Duration(seconds: 10))),
              IconButton(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 36, color: Colors.deepPurple),
                tooltip: '',
                onPressed: () { if (_playing) { _player.pause(); } else { _player.play(); } },
              ),
              IconButton(icon: const Icon(Icons.forward_10, size: 24), tooltip: '', onPressed: () => _player.seek(_position + const Duration(seconds: 10))),
              const Spacer(),
              // 倍速
              PopupMenuButton<double>(
                icon: const Icon(Icons.speed, size: 22, color: Colors.grey),
                onSelected: (s) async { _speed = s; await _player.setRate(s); setState(() {}); },
                itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) => PopupMenuItem(
                  value: s,
                  child: Text('${s}x', style: TextStyle(fontWeight: _speed == s ? FontWeight.bold : FontWeight.normal, color: _speed == s ? Colors.deepPurple : null)),
                )).toList(),
              ),
              Text('${_speed}x', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ]),
        ),
      ]),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
