import 'package:audio_service/audio_service.dart';
import 'audio_player_service.dart';

/// 媒体会话处理器：桥接系统媒体控制（耳机键/通知栏/锁屏）与播放器。
/// 音乐播放走 AudioPlayerService；视频页切换时通过 notifyMediaChanged 更新媒体信息。
class GoMusicAudioHandler extends BaseAudioHandler {
  /// 全局单例（video_player_page 等通过它更新媒体信息）
  static GoMusicAudioHandler? instance;

  GoMusicAudioHandler() {
    instance = this;
    // 监听音乐播放器状态变化，同步媒体会话
    AudioPlayerService().currentSongNotifier.addListener(_syncFromPlayer);
    AudioPlayerService().onPlayingChanged.listen((_) => _syncFromPlayer());
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
  }) {
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      artist: artist,
      duration: duration,
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
    if (svc.currentSong != null) {
      svc.resume();
    }
    _syncFromPlayer();
  }

  @override
  Future<void> pause() async {
    final svc = AudioPlayerService();
    if (svc.isPlaying) {
      svc.togglePause();
    }
    _syncFromPlayer();
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
