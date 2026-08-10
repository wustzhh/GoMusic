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
    _tmpDir = Directory.systemTemp.createTempSync('play_test_');
    Directory.current = _tmpDir; // 隔离：避免 _saveState 写真实 save_state.json
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  test('真实歌单：点击第3首播放第3首', () async {
    final svc = AudioPlayerService();
    final songs = await scanLocalAudioFiles(r'D:\GitHubProject\GoMusic\downloads');
    if (songs.length < 3) { markTestSkipped('真实歌单不足3首'); return; }
    svc.setQueue(songs, startIndex: 2, playlistId: 'local', keepOrder: true);
    await svc.playSong(songs[2]);
    expect(svc.currentSong?.bvid, songs[2].bvid, reason: '点击第3首应播放第3首');
    expect(svc.queueIndex, 2);
  });

  test('真实歌单：点击首首播放首首', () async {
    final svc = AudioPlayerService();
    final songs = await scanLocalAudioFiles(r'D:\GitHubProject\GoMusic\downloads');
    if (songs.isEmpty) { markTestSkipped('真实歌单为空'); return; }
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(songs[0]);
    expect(svc.currentSong?.bvid, songs[0].bvid);
    expect(svc.queueIndex, 0);
  });

  test('点击 filePath 无效的歌：跳过并播下一首，不播旧歌', () async {
    final svc = AudioPlayerService();
    final songs = await scanLocalAudioFiles(r'D:\GitHubProject\GoMusic\downloads');
    if (songs.length < 3) { markTestSkipped('真实歌单不足3首'); return; }
    // 在真实歌单前插入一首无效路径的歌（模拟自定义歌单未补全）
    final bad = Song(id: 'BAD1', title: 'bad', uploader: '', duration: Duration.zero, bvid: 'BAD1', filePath: '');
    final withBad = [songs[0], bad, songs[1], songs[2]];
    svc.setQueue(withBad, startIndex: 0, playlistId: 'pl1', keepOrder: true);
    await svc.playSong(withBad[0]);
    expect(svc.currentSong?.bvid, withBad[0].bvid);
    // 点无效路径的歌：应跳过（从当前位置往后，播 withBad[2]）
    await svc.playSong(bad);
    await Future.delayed(const Duration(milliseconds: 600));
    print('点无效歌后 currentSong: ${svc.currentSong?.bvid}');
    expect(svc.currentSong?.bvid, withBad[2].bvid, reason: '无效路径应跳过，播下一首有效歌');
  });
}
