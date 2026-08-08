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
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('gomusic_loc_');
    Directory.current = _tmpDir;
    SongGroupService.resetForTest();
  });

  tearDown(() {
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  testWidgets('当前歌曲在组内时播放列表高亮并定位', (tester) async {
    // 组1：BV1,BV2,BV3；单曲 BV4；当前歌曲=BV3（组内第三个）
    File('song_groups.json').writeAsStringSync(jsonEncode([
      {'id': 'g1', 'pl': 'local', 'name': '组A', 'paths': ['BV1', 'BV2', 'BV3'], 'shuffle': false},
    ]));
    final queue = [_song('BV1', '歌1'), _song('BV2', '歌2'), _song('BV3', '歌3'), _song('BV4', '歌4')];
    final currentIndex = 2; // BV3

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SongQueueList(
          queue: queue,
          currentIndex: currentIndex,
          currentTitle: '歌3', // 用歌曲名字定位
          playlistId: 'local',
          onPlay: (_) {},
          onRemove: (_) {},
        ),
      ),
    ));
    await tester.pump();

    // 当前歌曲行应高亮（红色标题）
    final tile = tester.widget<Text>(find.text('歌3'));
    expect(tile.style?.color, Colors.red);
    // 组名只显示一次
    expect(find.text('组A'), findsOneWidget);
    // 4 首歌全部渲染
    expect(find.text('歌1'), findsOneWidget);
    expect(find.text('歌2'), findsOneWidget);
    expect(find.text('歌4'), findsOneWidget);
  });

  testWidgets('按歌曲名字定位：currentIndex 错误时仍高亮 title 匹配的歌曲', (tester) async {
    File('song_groups.json').writeAsStringSync(jsonEncode([
      {'id': 'g1', 'pl': 'local', 'name': '组A', 'paths': ['BV1', 'BV2', 'BV3'], 'shuffle': false},
    ]));
    final queue = [_song('BV1', '歌1'), _song('BV2', '歌2'), _song('BV3', '歌3'), _song('BV4', '歌4')];
    // currentIndex 故意指向 BV4，但 currentTitle 是歌2 → 应高亮歌2
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SongQueueList(
          queue: queue,
          currentIndex: 3,
          currentTitle: '歌2',
          playlistId: 'local',
          onPlay: (_) {},
          onRemove: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.widget<Text>(find.text('歌2')).style?.color, Colors.red);
    expect(tester.widget<Text>(find.text('歌4')).style?.color, isNot(Colors.red));
  });

  testWidgets('title 与队列不一致时 bvid 兜底高亮（恢复场景）', (tester) async {
    File('song_groups.json').writeAsStringSync(jsonEncode([
      {'id': 'g1', 'pl': 'local', 'name': '组A', 'paths': ['BV1', 'BV2'], 'shuffle': false},
    ]));
    // 队列里 title 是 BV 号占位；currentTitle 是真实标题（不匹配），currentBvid 匹配
    final queue = [_song('BV1', 'BV1'), _song('BV2', 'BV2'), _song('BV3', 'BV3')];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SongQueueList(
          queue: queue,
          currentIndex: 2, // 故意错误
          currentTitle: '某真实标题', // 队列中不存在
          currentBvid: 'BV2', // bvid 兜底命中
          playlistId: 'local',
          onPlay: (_) {},
          onRemove: (_) {},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.widget<Text>(find.text('BV2')).style?.color, Colors.red);
    expect(tester.widget<Text>(find.text('BV3')).style?.color, isNot(Colors.red));
  });

  testWidgets('当前歌曲为单曲时定位正常', (tester) async {
    File('song_groups.json').writeAsStringSync(jsonEncode([
      {'id': 'g1', 'pl': 'local', 'name': '组A', 'paths': ['BV1', 'BV2'], 'shuffle': false},
    ]));
    final queue = [_song('BV1', '歌1'), _song('BV2', '歌2'), _song('BV3', '歌3')];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SongQueueList(
          queue: queue,
          currentIndex: 2, // BV3 单曲
          playlistId: 'local',
          onPlay: (_) {},
          onRemove: (_) {},
        ),
      ),
    ));
    await tester.pump();
    final tile = tester.widget<Text>(find.text('歌3'));
    expect(tile.style?.color, Colors.red);
  });

  testWidgets('长队列（含组）打开后定位到当前歌曲（滚动后目标可见）', (tester) async {
    File('song_groups.json').writeAsStringSync(jsonEncode([
      {'id': 'g1', 'pl': 'local', 'name': '组A', 'paths': ['BV1', 'BV2', 'BV3'], 'shuffle': false},
    ]));
    // 40 首：组A(3首) + 37 首单曲，当前歌曲在尾部（BV40）
    final queue = <Song>[
      _song('BV1', '歌1'), _song('BV2', '歌2'), _song('BV3', '歌3'),
      for (var i = 4; i <= 40; i++) _song('BV$i', '歌$i'),
    ];
    final currentIndex = 39; // BV40
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300, // 限制视口触发滚动
          child: SongQueueList(
            queue: queue,
            currentIndex: currentIndex,
            playlistId: 'local',
            onPlay: (_) {},
            onRemove: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump(); // 首帧
    await tester.pump(const Duration(milliseconds: 100)); // postFrame 定位
    await tester.pump(const Duration(milliseconds: 100));
    // 当前歌曲（BV40）应已滚动到可见区域
    expect(find.text('歌40'), findsOneWidget);
    final tile = tester.widget<Text>(find.text('歌40'));
    expect(tile.style?.color, Colors.red);
  });
}
