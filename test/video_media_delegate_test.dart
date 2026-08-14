import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/audio_handler.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// 记录媒体控制调用的假视频委托
class _Recorder implements VideoMediaDelegate {
  final calls = <String>[];
  @override
  Future<void> mediaPlay() async { calls.add('play'); }
  @override
  Future<void> mediaPause() async { calls.add('pause'); }
  @override
  Future<void> mediaNext() async { calls.add('next'); }
  @override
  Future<void> mediaPrevious() async { calls.add('prev'); }
  @override
  Future<void> mediaSeek(Duration p) async { calls.add('seek:${p.inSeconds}'); }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
  });

  test('视频委托注册期间：通知栏/耳机键控制路由到视频播放器', () async {
    final handler = GoMusicAudioHandler();
    final rec = _Recorder();
    handler.attachVideoDelegate(rec);
    await handler.play();
    await handler.pause();
    await handler.skipToNext();
    await handler.skipToPrevious();
    await handler.seek(const Duration(seconds: 30));
    expect(rec.calls, ['play', 'pause', 'next', 'prev', 'seek:30'],
        reason: '视频激活时所有媒体控制应路由到视频，而不是音频服务');
  });

  test('注销委托后：媒体控制恢复路由到音频服务（视频操作清零）', () async {
    final handler = GoMusicAudioHandler();
    final rec = _Recorder();
    handler.attachVideoDelegate(rec);
    handler.detachVideoDelegate(rec);
    // 音频未播放：pause 不抛异常、不触碰视频委托
    await handler.pause();
    await handler.play();
    expect(rec.calls, isEmpty,
        reason: '视频退出后媒体控制不应再路由到视频');
  });

  test('notifyVideoMedia 驱动 playing=true：通知栏显示播放态（前台服务保活前提）', () async {
    final handler = GoMusicAudioHandler();
    handler.notifyVideoMedia(
      id: 'BV123',
      title: '测试视频',
      artist: 'UP主',
      duration: const Duration(seconds: 100),
      playing: true,
      position: const Duration(seconds: 10),
    );
    expect(handler.mediaItem.value?.title, '测试视频');
    expect(handler.playbackState.value.playing, true,
        reason: 'playing=true 是 audio_service 启动前台服务、后台保活的关键');
    // 位置高频同步不应改变媒体信息
    handler.notifyVideoPosition(const Duration(seconds: 20));
    expect(handler.playbackState.value.updatePosition, const Duration(seconds: 20));
    expect(handler.mediaItem.value?.title, '测试视频');
  });
}
