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
    _tmpDir = Directory.systemTemp.createTempSync('gomusic_pn2_');
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

  test('整组跟随：目标组插到当前组最后成员之后，且目标歌是第一首', () async {
    final svc = AudioPlayerService();
    // 当前组 {BV1,BV2}，目标组 {BV3,BV4,BV5}
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    final a4 = _local('BV4', 'D');
    final a5 = _local('BV5', 'E');
    SongGroupService.groupSongs([a1, a2], playlistId: 'local');
    SongGroupService.groupSongs([a3, a4, a5], playlistId: 'local');

    // 歌单顺序：当前组、目标组
    final songs = [a1, a2, a3, a4, a5];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(a1); // 播当前组第一首

    // 对 BV3 点"下一首播放"：整组 {BV3,BV4,BV5} 跟随
    svc.playNext(a3, groupMembers: [a3, a4, a5]);

    // 队列 = [BV1, BV2, BV3, BV4, BV5]（当前组播完才到目标组，目标歌 BV3 第一）
    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV2', 'BV3', 'BV4', 'BV5']);
    expect(svc.queueIndex, 0);
  });

  test('下一首播放：目标组插到当前歌之后（当前无组）', () async {
    final svc = AudioPlayerService();
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    final a4 = _local('BV4', 'D');
    SongGroupService.groupSongs([a3, a4], playlistId: 'local');

    final songs = [a1, a2, a3, a4];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(a1);

    svc.playNext(a3, groupMembers: [a3, a4]);

    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV3', 'BV4', 'BV2']);
    expect(svc.queueIndex, 0);
  });

  test('目标组员部分缺失：从 _queue 补齐，目标歌排第一', () async {
    final svc = AudioPlayerService();
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    final a4 = _local('BV4', 'D');
    SongGroupService.groupSongs([a3, a4], playlistId: 'local');

    final songs = [a1, a2, a3, a4];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(a1);

    // 调用方只传了目标歌 BV3（模拟 rest 匹配失败的极端情况），BV4 应从 _queue 补齐
    svc.playNext(a3, groupMembers: [a3]);

    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV3', 'BV4', 'BV2']);
  });

  test('当前歌在组内且目标组在其后：整组插到当前组最后成员之后', () async {
    final svc = AudioPlayerService();
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    final a4 = _local('BV4', 'D');
    SongGroupService.groupSongs([a1, a2], playlistId: 'local');
    SongGroupService.groupSongs([a3, a4], playlistId: 'local');

    final songs = [a1, a2, a3, a4];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(a1);

    // 目标组员 BV3 缺失（groupMembers 只传 BV4），BV3 应从 _queue 补齐
    svc.playNext(a4, groupMembers: [a4]);

    // 目标组 {BV4,BV3}（BV4 用户选的排第一，BV3 补齐）插到当前组最后成员 BV2 之后
    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV2', 'BV4', 'BV3']);
  });

  test('目标歌不在传入组员里：强制排第一，其余组员补齐在后', () async {
    final svc = AudioPlayerService();
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    final a4 = _local('BV4', 'D');
    SongGroupService.groupSongs([a3, a4], playlistId: 'local');

    final songs = [a1, a2, a3, a4];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    await svc.playSong(a1);

    // groupMembers 传了 BV3，但用户选的目标歌是 BV4
    svc.playNext(a4, groupMembers: [a3]);

    // 目标歌 BV4 强制排第一，组员 BV3 补齐在后
    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV4', 'BV3', 'BV2']);
  });
}
