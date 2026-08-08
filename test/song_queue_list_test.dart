import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/widgets/song_queue_list.dart';

Song _song(String bvid, String title) => Song(
      id: bvid,
      title: title,
      uploader: 'u',
      duration: const Duration(seconds: 60),
      bvid: bvid,
      filePath: 'C:/x/$bvid.mp3',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory _origDir;
  late Directory _tmpDir;

  setUp(() {
    // 切换到隔离的临时工作目录，避免 song_groups.json 读写污染项目根目录
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('gomusic_sqltest_');
    Directory.current = _tmpDir;
    // 写入测试用的组数据（SongGroupService 读进程工作目录 song_groups.json）
    final groups = [
      {'id': 'g1', 'pl': 'local', 'name': '组A', 'paths': ['BV1', 'BV2', 'BV3'], 'shuffle': false},
      {'id': 'g2', 'pl': 'local', 'name': '组B', 'paths': ['BV4', 'BV5'], 'shuffle': false},
    ];
    File('song_groups.json').writeAsStringSync(jsonEncode(groups));
    // 重置 SongGroupService 缓存
    SongGroupService.resetForTest();
  });

  tearDown(() {
    try { File('song_groups.json').deleteSync(); } catch (_) {}
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  testWidgets('队列弹窗中每个组只显示一次（回归：重复组问题）', (tester) async {
    final queue = [
      _song('BV1', '歌1'), _song('BV2', '歌2'), _song('BV3', '歌3'),
      _song('BV4', '歌4'), _song('BV5', '歌5'),
      _song('BV6', '歌6'), // 单曲
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SongQueueList(
          queue: queue,
          currentIndex: 0,
          playlistId: 'local',
          onPlay: (_) {},
          onRemove: (_) {},
        ),
      ),
    ));
    await tester.pump();

    // 组名应恰好各出现 1 次（修复前：组内每首歌都会重复渲染整组 → 组A出现3次、组B出现2次）
    expect(find.text('组A'), findsOneWidget);
    expect(find.text('组B'), findsOneWidget);
    // 单曲歌6出现1次
    expect(find.text('歌6'), findsOneWidget);
  });
}
