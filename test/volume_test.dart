import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
  });

  test('默认音量 100', () {
    final s = AudioPlayerService();
    expect(s.volume, 100.0);
    expect(s.volumeNotifier.value, 100.0);
  });

  test('setVolume 钳位到 5~100', () async {
    final s = AudioPlayerService();
    await s.setVolume(150);
    expect(s.volume, 100.0);
    await s.setVolume(0);
    expect(s.volume, 5.0);
    await s.setVolume(66);
    expect(s.volume, 66.0);
    expect(s.volumeNotifier.value, 66.0);
  });

  test('changeVolume 步进 5', () async {
    final s = AudioPlayerService();
    await s.changeVolume(5);
    expect(s.volume, 100.0); // 已是上限，不再增加
    await s.setVolume(50);
    await s.changeVolume(5);
    expect(s.volume, 55.0);
    await s.changeVolume(-10);
    expect(s.volume, 45.0);
    await s.changeVolume(-100);
    expect(s.volume, 5.0); // 下限 5
  });

  test('restoreVolume 从持久化恢复（Windows）', () async {
    SharedPreferences.setMockInitialValues({
      'windows_volume': 37.0,
    });
    final s = AudioPlayerService();
    await s.restoreVolume();
    expect(s.volume, 37.0);
    expect(s.volumeNotifier.value, 37.0);
  });

  test('restoreVolume 无持久化时默认 100', () async {
    final s = AudioPlayerService();
    await s.restoreVolume();
    expect(s.volume, 100.0);
  });

  test('setVolume 持久化保存（Windows）', () async {
    final s = AudioPlayerService();
    await s.setVolume(42);
    final p = await SharedPreferences.getInstance();
    expect(p.getDouble('windows_volume'), 42.0);
  });
}
