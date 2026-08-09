import 'dart:async';

import 'package:gomusic/services/audio_player_service.dart';
import 'package:media_kit/media_kit.dart' as mk;

/// 测试用假播放内核：覆盖 service 用到的 open/play/pause/seek/state/stream，
/// 避免测试环境加载 libmpv（media_kit 用 FFI）失败。
class FakeMediaKitPlayer extends mk.PlatformPlayer {
  FakeMediaKitPlayer() : super(configuration: const mk.PlayerConfiguration());

  bool completed = false;
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = const Duration(seconds: 100);

  @override
  late mk.PlayerState state = mk.PlayerState(
    playing: playing,
    completed: completed,
    position: position,
    duration: duration,
    volume: 1.0,
    rate: 1.0,
    pitch: 1.0,
    buffering: false,
    buffer: Duration.zero,
    bufferingPercentage: 0,
    playlistMode: mk.PlaylistMode.loop,
    shuffle: false,
  );

  final _positionCtl = StreamController<Duration>.broadcast();
  final _durationCtl = StreamController<Duration>.broadcast();
  final _playingCtl = StreamController<bool>.broadcast();
  final _completedCtl = StreamController<bool>.broadcast();

  @override
  late mk.PlayerStream stream = mk.PlayerStream(
    StreamController<mk.Playlist>.broadcast().stream,
    _playingCtl.stream,
    _completedCtl.stream,
    _positionCtl.stream,
    _durationCtl.stream,
    StreamController<double>.broadcast().stream,
    StreamController<double>.broadcast().stream,
    StreamController<double>.broadcast().stream,
    StreamController<bool>.broadcast().stream,
    StreamController<double>.broadcast().stream,
    StreamController<Duration>.broadcast().stream,
    StreamController<mk.PlaylistMode>.broadcast().stream,
    StreamController<bool>.broadcast().stream,
    StreamController<mk.AudioParams>.broadcast().stream,
    StreamController<mk.VideoParams>.broadcast().stream,
    StreamController<double?>.broadcast().stream,
    StreamController<mk.AudioDevice>.broadcast().stream,
    StreamController<List<mk.AudioDevice>>.broadcast().stream,
    StreamController<mk.Track>.broadcast().stream,
    StreamController<mk.Tracks>.broadcast().stream,
    StreamController<int?>.broadcast().stream,
    StreamController<int?>.broadcast().stream,
    StreamController<List<String>>.broadcast().stream,
    StreamController<mk.PlayerLog>.broadcast().stream,
    StreamController<String>.broadcast().stream,
  );

  void emitCompleted() {
    completed = true;
    playing = false;
    state = mk.PlayerState(
      playing: false,
      completed: true,
      position: duration,
      duration: duration,
      volume: 1.0,
      rate: 1.0,
      pitch: 1.0,
      buffering: false,
      buffer: Duration.zero,
      bufferingPercentage: 0,
      playlistMode: mk.PlaylistMode.loop,
      shuffle: false,
    );
    _completedCtl.add(true);
  }

  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    completed = false;
    state = mk.PlayerState(
      playing: play,
      completed: false,
      position: Duration.zero,
      duration: duration,
      volume: 1.0,
      rate: 1.0,
      pitch: 1.0,
      buffering: false,
      buffer: Duration.zero,
      bufferingPercentage: 0,
      playlistMode: mk.PlaylistMode.loop,
      shuffle: false,
    );
    _durationCtl.add(duration);
    if (play) {
      playing = true;
      _playingCtl.add(true);
    }
  }

  @override
  Future<void> play() async {
    playing = true;
    _playingCtl.add(true);
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playingCtl.add(false);
  }

  @override
  Future<void> seek(Duration d) async {
    position = d;
    state = mk.PlayerState(
      playing: playing,
      completed: false,
      position: d,
      duration: duration,
      volume: 1.0,
      rate: 1.0,
      pitch: 1.0,
      buffering: false,
      buffer: Duration.zero,
      bufferingPercentage: 0,
      playlistMode: mk.PlaylistMode.loop,
      shuffle: false,
    );
    _positionCtl.add(d);
  }
}

/// 最近一次注入的 fake 播放器（测试可触发 complete 流模拟滞后事件）
FakeMediaKitPlayer? lastFakePlayer;

/// 注入假播放内核到 AudioPlayerService 单例（测试环境无法加载 libmpv）。
void injectFakePlayer() {
  lastFakePlayer = FakeMediaKitPlayer();
  AudioPlayerService.resetForTest(
    player: mk.Player(platformPlayer: lastFakePlayer!),
  );
}
