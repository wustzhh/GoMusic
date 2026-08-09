import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory _tmpDir;
  late Directory _origDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('shuffle_click_');
    Directory.current = _tmpDir; // 隔离：避免 _saveState 写真实 save_state.json
    for (var i = 1; i <= 5; i++) {
      File('${_tmpDir.path}/BV$i.mp3').writeAsBytesSync(List.filled(1024, 0));
    }
  });
  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  test('随机模式点击第3首：播放第3首且不被自动切走', () async {
    final svc = AudioPlayerService();
    final songs = List.generate(5, (i) => Song(
      id: 'BV${i+1}', title: '歌${i+1}', uploader: 'u',
      duration: const Duration(seconds: 300), bvid: 'BV${i+1}',
      filePath: '${_tmpDir.path}/BV${i+1}.mp3',
    ));
    // 模拟 _playSong：先播一首（制造旧源），再随机模式点击第3首
    svc.setPlayMode(PlayMode.shuffle);
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(songs[0]);
    expect(svc.currentSong?.bvid, 'BV1');

    // 点击第3首（BV3）
    svc.setQueue(songs, startIndex: 2, playlistId: 'local', keepOrder: true);
    svc.moveToFront(songs[2]);
    await svc.playSong(songs[2]);
    expect(svc.currentSong?.bvid, 'BV3', reason: '随机模式点击 BV3 应播放 BV3');
    expect(svc.queue.first.bvid, 'BV3', reason: 'BV3 必须在队列第一首');
    expect(svc.queueIndex, 0);

    // 模拟旧源 BV1 的 complete 滞后到达（换源后 0.3 秒触发，应被防抖忽略）
    await Future.delayed(const Duration(milliseconds: 300));
    lastFakePlayer?.emitCompleted();
    await Future.delayed(const Duration(milliseconds: 500));

    print('滞后complete后 currentSong: ${svc.currentSong?.bvid}, queueIndex: ${svc.queueIndex}');
    expect(svc.currentSong?.bvid, 'BV3', reason: '旧源滞后 complete 不应切走 BV3');
    expect(svc.queueIndex, 0, reason: '队列索引应保持 0（第一首）');
  });
}
