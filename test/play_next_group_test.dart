import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Song _song(String bvid, String title, {String? path}) => Song(
      id: bvid,
      title: title,
      uploader: 'u',
      duration: const Duration(seconds: 100),
      bvid: bvid,
      filePath: path ?? 'C:/x/$bvid.mp3',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory _origDir;
  late Directory _tmpDir;

  setUp(() {
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('gomusic_pn_');
    Directory.current = _tmpDir;
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    // 清空测试中创建的组缓存（song_groups.json 在临时目录，安全）
    SongGroupService.removeMissing(const {});
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  test('整组跟随：组员一起插到当前歌之后，原位置移除不拆分', () {
    final svc = AudioPlayerService();
    final songs = [_song('BV1', 'A'), _song('BV2', 'B'), _song('BV3', 'C'), _song('BV4', 'D')];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    expect(svc.queueIndex, 0); // 当前 BV1

    // 对组内 BV3 点"下一首播放"，整组 [BV3, BV4] 跟随
    svc.playNext(_song('BV3', 'C'), groupMembers: [_song('BV3', 'C'), _song('BV4', 'D')]);

    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV3', 'BV4', 'BV2']);
    expect(svc.queueIndex, 0); // 当前歌仍为 BV1
  });

  test('目标已在队列中：先移除再插入当前后，不重复', () {
    final svc = AudioPlayerService();
    final songs = [_song('BV1', 'A'), _song('BV2', 'B'), _song('BV3', 'C'), _song('BV4', 'D')];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);

    svc.playNext(_song('BV4', 'D')); // 无组：单曲移动

    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV4', 'BV2', 'BV3']);
    expect(svc.queueIndex, 0);
  });

  test('目标不在队列：直接插到当前歌之后', () {
    final svc = AudioPlayerService();
    final songs = [_song('BV1', 'A'), _song('BV2', 'B')];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);

    svc.playNext(_song('BV9', 'Z'), groupMembers: [_song('BV9', 'Z'), _song('BV8', 'Y')]);

    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV9', 'BV8', 'BV2']);
  });

  test('当前歌在组内：整组插到当前组最后一个成员之后（不拆散当前组）', () async {
    final svc = AudioPlayerService();
    // 真实文件 + 真实播放态（playSong 要求文件存在才能设置 _currentSong）
    Song local(String bv, String t) {
      final f = File('${_tmpDir.path}/$bv.mp3');
      f.writeAsStringSync('x');
      return _song(bv, t, path: f.path);
    }

    final a1 = local('BV1', 'A');
    final a2 = local('BV2', 'B');
    // 真实建组 {BV1, BV2}，当前播放 BV1（组内）
    SongGroupService.groupSongs([a1, a2], playlistId: 'local');
    final songs = [a1, a2, local('BV3', 'C'), local('BV4', 'D')];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(a1); // 真正播放 → 设置 _currentSong
    expect(SongGroupService.groupOf(a1, playlistId: 'local'), isNotNull);

    // 对 BV3/BV4 整组"下一首播放"：插入点应=当前组最后一个成员(BV2)之后
    svc.playNext(songs[2], groupMembers: [songs[2], songs[3]]);

    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV2', 'BV3', 'BV4']);
    expect(svc.queueIndex, 0);
  });
}
