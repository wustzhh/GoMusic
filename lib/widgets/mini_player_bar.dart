import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
import '../pages/player_page.dart';

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
    _isPlaying = _service.isPlaying;

    _service.currentSongNotifier.addListener(_onSongChanged);
    _service.onPlayingChanged.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    });
    _service.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _service.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
  }

  void _onSongChanged() {
    if (mounted) setState(() => _song = _service.currentSong);
  }

  @override
  void dispose() {
    _service.currentSongNotifier.removeListener(_onSongChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_song == null) return const SizedBox.shrink();

    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage())),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.12))),
        ),
        child: Column(
          children: [
            LinearProgressIndicator(value: progress, minHeight: 1.5, backgroundColor: Colors.transparent, color: Colors.deepPurple),
            Expanded(
              child: Row(children: [
                const SizedBox(width: 12),
                Icon(Icons.music_note, color: Colors.deepPurple, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${_song!.title} · ${_song!.uploader}',
                      style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
                ),
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 26, color: Colors.deepPurple),
                  onPressed: () { _service.togglePause(); setState(() => _isPlaying = !_isPlaying); },
                ),
                const SizedBox(width: 4),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
