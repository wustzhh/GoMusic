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
    _tmpDir = Directory.systemTemp.createTempSync('gomusic_pn3_');
    Directory.current = _tmpDir;
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    SongGroupService.removeMissing(const {});
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  Song _local(String bv, String t) {
    final f = File('${_tmpDir.path}/$bv.mp3');
    f.writeAsStringSync('x');
    return _song(bv, t, path: f.path);
  }

  test('播完当前组自动切到目标组第一首（整组跟随播放路径）', () async {
    final svc = AudioPlayerService();
    // 当前组 {BV1,BV2}，目标组 {BV3,BV4}
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    final a4 = _local('BV4', 'D');
    SongGroupService.groupSongs([a1, a2], playlistId: 'local');
    SongGroupService.groupSongs([a3, a4], playlistId: 'local');

    final songs = [a1, a2, a3, a4];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(a1);
    expect(svc.currentSong?.bvid, 'BV1');

    // 对 BV3 点"下一首播放"：整组 {BV3,BV4} 跟随
    svc.playNext(a3);
    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV2', 'BV3', 'BV4']);

    // 等 2.2s 越过 BV1 手动播放的 2 秒防抖，再模拟播完
    await Future.delayed(const Duration(milliseconds: 2200));
    lastFakePlayer!.emitCompleted();
    await Future.delayed(const Duration(milliseconds: 200));
    expect(svc.currentSong?.bvid, 'BV2');

    // 旧源滞后的 completed 事件到达时，新媒体已打开，不能再次跳到 BV3
    lastFakePlayer!.emitStaleCompleted();
    await Future.delayed(const Duration(milliseconds: 200));
    expect(svc.currentSong?.bvid, 'BV2');

    // BV2 complete → 自动切 BV3（目标组第一首；自动切歌不刷新防抖，连播不卡）
    lastFakePlayer!.emitCompleted();
    await Future.delayed(const Duration(milliseconds: 200));
    expect(svc.currentSong?.bvid, 'BV3');
  });
}