import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
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
    _tmpDir = Directory.systemTemp.createTempSync('go_group_batch_');
    Directory.current = _tmpDir;
    SharedPreferences.setMockInitialValues({});
    SongGroupService.resetForTest();
    SongGroupService.init();
    injectFakePlayer();
  });

  tearDown(() {
    Directory.current = _origDir;
    SongGroupService.resetForTest();
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  Song _local(String bv, String t) {
    final f = File('${_tmpDir.path}/$bv.mp3');
    f.writeAsStringSync('x');
    return _song(bv, t, path: f.path);
  }

  test('组队后组内歌曲在歌单中真实相邻（groupSongs 保持成员顺序）', () async {
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    SongGroupService.groupSongs([a1, a2, a3], playlistId: 'local');

    final g = SongGroupService.groupOf(a2, playlistId: 'local');
    expect(g, isNotNull);
    expect(g!.songPaths, ['BV1', 'BV2', 'BV3']);
  });

  test('批量添加保留组：源歌单同组选中≥2首时目标歌单建同名组', () async {
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    // 源歌单 playlist=local：BV1,BV2 成组
    SongGroupService.groupSongs([a1, a2], playlistId: 'local');

    // 模拟批量添加：只选中其中 2 首（同组），目标歌单 pid=pl1
    final sel = [a1, a2];
    // 页面逻辑：按源歌单组聚合选中歌曲，≥2 首时在目标歌单调用 groupSongs 并保留组名
    final srcGroups = <String, List<Song>>{};
    final names = <String, String>{};
    for (final s in sel) {
      final g = SongGroupService.groupOf(s, playlistId: 'local');
      if (g != null) {
        srcGroups.putIfAbsent(g.id, () => []).add(s);
        names[g.id] = g.name;
      }
    }
    for (final e in srcGroups.entries) {
      if (e.value.length >= 2) {
        SongGroupService.groupSongs(e.value, playlistId: 'pl1', name: names[e.key]);
      }
    }

    final gInTarget = SongGroupService.groupOf(a1, playlistId: 'pl1');
    expect(gInTarget, isNotNull);
    expect(gInTarget!.songPaths, containsAll(['BV1', 'BV2']));
    // 组名保留
    expect(gInTarget.name, names.values.first);
    // 目标歌单中只有选中这 2 首（BV3 未加入）
    expect(gInTarget.songPaths, isNot(contains('BV3')));
  });

  test('批量添加保留组：选中的同组歌曲不足2首不建组', () async {
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    final a3 = _local('BV3', 'C');
    SongGroupService.groupSongs([a1, a2, a3], playlistId: 'local');

    // 只选中 1 首同组歌曲 → 不建组
    final sel = [a1];
    final srcGroups = <String, List<Song>>{};
    for (final s in sel) {
      final g = SongGroupService.groupOf(s, playlistId: 'local');
      if (g != null) srcGroups.putIfAbsent(g.id, () => []).add(s);
    }
    for (final e in srcGroups.entries) {
      if (e.value.length >= 2) {
        SongGroupService.groupSongs(e.value, playlistId: 'pl1');
      }
    }
    expect(SongGroupService.groupOf(a1, playlistId: 'pl1'), isNull);
  });

  test('组信息 flush 后重新初始化仍保留目标歌单和组名', () async {
    final a1 = _local('BV1', 'A');
    final a2 = _local('BV2', 'B');
    await SongGroupService.ensureReady();
    SongGroupService.groupSongs([a1, a2], playlistId: 'target', name: '原组');
    await SongGroupService.flush();

    SongGroupService.resetForTest();
    await SongGroupService.init();
    final restored = SongGroupService.groupOf(a1, playlistId: 'target');
    expect(restored, isNotNull);
    expect(restored!.name, '原组');
    expect(restored.songPaths, ['BV1', 'BV2']);
  });

  test('自定义歌单排序持久化后重新读取仍保持新顺序', () async {
    await PlaylistService.addPlaylist('目标歌单');
    final playlists = await PlaylistService.getPlaylists();
    final pid = playlists.single.id;
    await PlaylistService.addSongsToPlaylist(pid, ['BV1', 'BV2', 'BV3']);
    await PlaylistService.reorderSongsInPlaylist(pid, ['BV2', 'BV3', 'BV1']);

    final restored = (await PlaylistService.getPlaylists()).single;
    expect(restored.songs.map((s) => s.bvid).toList(), ['BV2', 'BV3', 'BV1']);
  });
}