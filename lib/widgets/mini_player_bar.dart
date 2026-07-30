import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
import '../pages/player_page.dart';

/// 全局底部迷你播放器（毛玻璃效果）
class MiniPlayerBar extends StatefulWidget {
  const MiniPlayerBar({super.key});

  @override
  State<MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<MiniPlayerBar> {
  final _service = AudioPlayerService();
  Song? _song;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _song = _service.currentSong;
    _checkPlaying();
    _service.player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _isPlaying = s == PlayerState.playing);
    });
    _service.player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _service.player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  void _checkPlaying() {
    _isPlaying = _service.isPlaying;
  }

  @override
  Widget build(BuildContext context) {
    _song = _service.currentSong;
    if (_song == null) return const SizedBox.shrink();

    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
      },
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
          border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 2,
              child: LinearProgressIndicator(value: progress, minHeight: 2, backgroundColor: Colors.transparent, color: Colors.deepPurple),
            ),
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: _song!.coverUrl != null && _song!.coverUrl!.isNotEmpty
                        ? Image.asset('', width: 36, height: 36, errorBuilder: (_, e, s) => _musicIcon())
                        : _musicIcon(),
                  ),
                  const SizedBox(width: 10),
                  // 歌曲信息
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_song!.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                        Text(_song!.uploader, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  // 控制按钮
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 28, color: Colors.deepPurple),
                    onPressed: () {
                      _service.togglePause();
                      setState(() => _isPlaying = !_isPlaying);
                    },
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _musicIcon() => const Icon(Icons.music_note, color: Colors.deepPurple, size: 30);
}
