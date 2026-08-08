import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
import '../pages/player_page.dart';
import 'song_queue_list.dart';

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
    _position = _service.currentPosition;

    _service.currentSongNotifier.addListener(_onSongChanged);
    if (_song != null) _duration = _song!.duration;
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
    if (mounted) setState(() {
      _song = _service.currentSong;
      _position = _service.currentPosition;
      final d = _service.currentSong?.duration;
      if (d != null && d.inMilliseconds > 0) _duration = d;
    });
  }

  @override
  void dispose() {
    _service.currentSongNotifier.removeListener(_onSongChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = _song;
    if (song == null) {
      return Container(
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
          border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.12))),
        ),
        child: const Center(child: Text('未在播放', style: TextStyle(color: Colors.grey, fontSize: 13))),
      );
    }

    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        // 当前无歌（"未在播放"状态）：先恢复上次进度；无记录则播队列第一首
        if (_service.currentSong == null) {
          await _service.restoreLastSong();
          if (_service.currentSong == null && _service.queue.isNotEmpty) {
            _service.playSong(_service.queue.first);
          }
        }
        if (!context.mounted || _service.currentSong == null) return;
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PlayerPage()));
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
          border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.12))),
        ),
        child: Column(
          children: [
            LinearProgressIndicator(value: progress, minHeight: 1.5, backgroundColor: Colors.transparent, color: Colors.deepPurple),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(4), child: _buildCover(song)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(song.title, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (song.uploader.isNotEmpty)
                        Text(song.uploader, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    ]),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 36, height: 36,
                    child: Stack(alignment: Alignment.center, children: [
                      CircularProgressIndicator(
                        value: _duration.inMilliseconds > 0 ? _position.inMilliseconds / _duration.inMilliseconds : 0,
                        strokeWidth: 2.5, color: Colors.deepPurple, backgroundColor: Colors.grey.withValues(alpha: 0.2),
                      ),
                      IconButton(
                        icon: Icon(_service.isPlaying ? Icons.pause : Icons.play_arrow, size: 20, color: Colors.deepPurple),
                        onPressed: () { _service.togglePause(); setState(() {}); },
                        padding: EdgeInsets.zero,
                      ),
                    ]),
                  ),
                  IconButton(icon: const Icon(Icons.queue_music, size: 20, color: Colors.grey), onPressed: _showQueue, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                  const SizedBox(width: 2),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCover(Song song) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final f = File(song.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        return Image.file(f, width: 28, height: 28, fit: BoxFit.cover);
      }
    }
    return Icon(Icons.music_note, color: Colors.deepPurple, size: 22);
  }

  void _showQueue() {
    showModalBottomSheet(
      context: context,
      isDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
        child: _MiniQueueSheet(player: _service),
      ),
    );
  }
}


class _MiniQueueSheet extends StatefulWidget {
  final AudioPlayerService player;
  const _MiniQueueSheet({required this.player});
  @override
  State<_MiniQueueSheet> createState() => _MiniQueueSheetState();
}

class _MiniQueueSheetState extends State<_MiniQueueSheet> {
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _targetKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.player.currentSongNotifier.addListener(() { if (mounted) setState(() {}); WidgetsBinding.instance.addPostFrameCallback((_) => _locate()); });
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  void _locate() {
    final curSong = widget.player.currentSong;
    if (curSong == null || !_scrollCtrl.hasClients) return;
    final idx = widget.player.queue.indexWhere((s) => s.title == curSong.title);
    if (idx < 0) return;
    final est = (idx * 64.0 - _scrollCtrl.position.viewportDimension / 2).clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.jumpTo(est);
    int tries = 0;
    void locate() {
      if (tries++ > 10) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _targetKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
          return;
        }
        _scrollCtrl.jumpTo((_scrollCtrl.offset + _scrollCtrl.position.viewportDimension * 0.7).clamp(0.0, _scrollCtrl.position.maxScrollExtent));
        locate();
      });
    }
    locate();
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

  @override
  void dispose() { _scrollCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    var queue = p.queue;
    return SizedBox(height: MediaQuery.of(context).size.height * 0.5, child: Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Text('播放列表 (${queue.length}首)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        GestureDetector(
          onTap: () {
            final modes = PlayMode.values;
            final next = (modes.indexOf(widget.player.playMode) + 1) % modes.length;
            widget.player.setPlayMode(modes[next]);
            setState(() {});
            WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
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
            currentTitle: p.currentSong?.title,
            currentBvid: p.currentSong?.bvid,
            playlistId: p.currentPlaylistId,
            onPlay: (s) { p.playSong(s); Navigator.pop(context); },
            onRemove: (i) { p.removeFromQueue(i); setState(() {}); },
          )),
    ]));
  }
}