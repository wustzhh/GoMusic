import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'audio_player_service.dart';

/// 媒体会话处理器：桥接系统媒体控制（耳机键/通知栏/锁屏）与播放器。
/// 音乐播放走 AudioPlayerService；视频页切换时通过 notifyMediaChanged 更新媒体信息。
class GoMusicAudioHandler extends BaseAudioHandler {
  /// 全局单例（video_player_page 等通过它更新媒体信息）
  static GoMusicAudioHandler? instance;

  void _log(String msg) {
    try {
      File('${Directory.systemTemp.path}/gomusic_debug.log')
          .writeAsStringSync('[${DateTime.now().toIso8601String().substring(11, 19)}] [MS] $msg\n', mode: FileMode.append);
    } catch (_) {}
  }

  GoMusicAudioHandler() {
    instance = this;
    // 监听音乐播放器状态变化，同步媒体会话
    AudioPlayerService().currentSongNotifier.addListener(_syncFromPlayer);
    AudioPlayerService().onPlayingChanged.listen((_) => _syncFromPlayer());
    // 进度实时同步（播放中每 500ms 一次）
    AudioPlayerService().onPositionChanged.listen((p) {
      final svc = AudioPlayerService();
      final song = svc.currentSong;
      if (song == null) return;
      playbackState.add(playbackState.value.copyWith(updatePosition: p));
    });
    // 时长变化同步到 mediaItem
    AudioPlayerService().onDurationChanged.listen((d) {
      final svc = AudioPlayerService();
      final song = svc.currentSong;
      if (song == null || d.inMilliseconds <= 0) return;
      mediaItem.add(mediaItem.value?.copyWith(duration: d));
    });
    // 立即同步一次当前状态（启动恢复的歌曲/播放状态）
    _syncFromPlayer();
  }

  void _syncFromPlayer() {
    final svc = AudioPlayerService();
    final song = svc.currentSong;
    if (song == null) return;
    mediaItem.add(MediaItem(
      id: song.bvid.isNotEmpty ? song.bvid : song.filePath,
      title: song.title,
      artist: song.uploader,
      duration: song.duration,
      artUri: (song.coverUrl != null && song.coverUrl!.isNotEmpty && File(song.coverUrl!).existsSync())
          ? Uri.file(song.coverUrl!)
          : null,
    ));
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (svc.isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: AudioProcessingState.ready,
      playing: svc.isPlaying,
      updatePosition: svc.currentPosition,
      speed: 1.0,
    ));
  }

  /// 视频页调用：更新媒体信息为当前视频（视频播放时也支持耳机键/锁屏）
  void notifyVideoMedia({
    required String id,
    required String title,
    required String artist,
    required Duration duration,
    required bool playing,
    required Duration position,
    String? coverUrl,
  }) {
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      artist: artist,
      duration: duration,
      artUri: (coverUrl != null && coverUrl.isNotEmpty && File(coverUrl).existsSync())
          ? Uri.file(coverUrl)
          : null,
    ));
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      speed: 1.0,
    ));
  }

  @override
  Future<void> play() async {
    final svc = AudioPlayerService();
    _log('play: isPlaying=${svc.isPlaying} pos=${svc.currentPosition.inMilliseconds}ms dur=${svc.currentSong?.duration.inSeconds}s');
    if (svc.currentSong != null) {
      if (svc.isPlaying) {
        // 已在播放：什么都不做
      } else if (svc.currentPosition >= const Duration(seconds: 1) &&
          svc.currentSong!.duration.inMilliseconds > 0 &&
          svc.currentPosition >= svc.currentSong!.duration - const Duration(seconds: 1)) {
        // 播完了：从头播放
        _log('play: 播完重播 ${svc.currentSong!.title}');
        await svc.playSong(svc.currentSong!, forceRestart: true);
      } else {
        _log('play: resume');
        svc.resume();
      }
    }
    _syncFromPlayer();
    _log('play: done isPlaying=${svc.isPlaying}');
  }

  @override
  Future<void> pause() async {
    final svc = AudioPlayerService();
    _log('pause: isPlaying=${svc.isPlaying}');
    if (svc.isPlaying) {
      svc.togglePause();
    }
    _syncFromPlayer();
    _log('pause: done isPlaying=${svc.isPlaying}');
  }

  @override
  Future<void> skipToNext() async {
    await AudioPlayerService().next();
    _syncFromPlayer();
  }

  @override
  Future<void> skipToPrevious() async {
    await AudioPlayerService().prev();
    _syncFromPlayer();
  }

  @override
  Future<void> seek(Duration position) async {
    await AudioPlayerService().seek(position);
    _syncFromPlayer();
  }

  @override
  Future<void> stop() async {
    await super.stop();
    mediaItem.add(null);
    playbackState.add(playbackState.value.copyWith(
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }
}
