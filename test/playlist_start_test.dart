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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('plstart_');
    Directory.current = _tmpDir; // 隔离：避免 _saveState 写真实 save_state.json
  });
  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  test('真实歌单：非随机模式点击第3首，新队列从第3首开始', () async {
    final svc = AudioPlayerService();
    final songs = await scanLocalAudioFiles(r'D:\GitHubProject\GoMusic\downloads');
    if (songs.length < 3) { markTestSkipped('真实歌单不足3首'); return; }
    svc.setQueue(songs, startIndex: 2, playlistId: 'local', keepOrder: true);
    await svc.playSong(songs[2]);
    expect(svc.currentSong?.bvid, songs[2].bvid);
    expect(svc.queueIndex, 2);
    expect(svc.queue.first.bvid, songs[0].bvid); // 队列整体仍是歌单顺序
  });

  test('真实歌单：随机模式点击的歌必须放队列第一首', () async {
    final svc = AudioPlayerService();
    final songs = await scanLocalAudioFiles(r'D:\GitHubProject\GoMusic\downloads');
    if (songs.length < 3) { markTestSkipped('真实歌单不足3首'); return; }
    // 模拟 _playSong 真实路径：随机模式 setQueue（内部随机化）→ moveToFront → playSong
    svc.setPlayMode(PlayMode.shuffle);
    svc.setQueue(songs, startIndex: 2, playlistId: 'local', keepOrder: true);
    svc.moveToFront(songs[2]);
    await svc.playSong(songs[2]);
    expect(svc.currentSong?.bvid, songs[2].bvid);
    expect(svc.queue.first.bvid, songs[2].bvid, reason: '随机模式点击的歌必须在队列第一首');
    expect(svc.queueIndex, 0);
  });
}
