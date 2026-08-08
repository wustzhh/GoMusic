import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/pages/song_list_page.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Song _song(String bvid, String title) => Song(
        id: bvid,
        title: title,
        uploader: 'u',
        duration: const Duration(seconds: 60),
        bvid: bvid,
        filePath: 'C:/x/$bvid.mp3',
      );

  late Directory _origDir;
  late Directory _tmpDir;

  setUp(() {
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('gomusic_drag_');
    Directory.current = _tmpDir;
    SharedPreferences.setMockInitialValues({});
    File('song_groups.json').writeAsStringSync(jsonEncode([]));
    SongGroupService.resetForTest();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  testWidgets('批量模式拖动三横杠后顺序变化并持久化', (tester) async {
    // 自定义歌单 5 首
    await PlaylistService.addPlaylist('拖动测试');
    var pls = await PlaylistService.getPlaylists();
    await PlaylistService.addSongsToPlaylist(pls.first.id, ['BV1', 'BV2', 'BV3', 'BV4', 'BV5']);
    pls = await PlaylistService.getPlaylists();
    final playlist = pls.first;

    await tester.pumpWidget(MaterialApp(home: SongListPage(playlist: playlist)));
    await tester.pump();

    // 进入批量模式
    await tester.tap(find.text('批量'));
    await tester.pump();

    // 应有 5 个拖动手柄
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(5));

    // 长按第一个拖动手柄并拖到第三个位置
    final firstHandle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(firstHandle));
    await tester.pump(const Duration(milliseconds: 600)); // 触发拖动手势
    await gesture.moveBy(const Offset(0, 120)); // 向下拖约 2 行
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // 验证顺序已改变（BV1 不再是第一个）
    final order = await PlaylistService.getPlaylists();
    expect(order.first.songs.map((s) => s.bvid).toList(), isNot(['BV1', 'BV2', 'BV3', 'BV4', 'BV5']));
    expect(order.first.songs.map((s) => s.bvid).toSet(), {'BV1', 'BV2', 'BV3', 'BV4', 'BV5'});

    // 模拟返回主界面再进入歌单：从存储重新加载并渲染新页面
    await tester.pumpWidget(const SizedBox()); // 卸载
    final reloaded = await PlaylistService.getPlaylists();
    await tester.pumpWidget(MaterialApp(home: SongListPage(playlist: reloaded.first)));
    await tester.pump();

    // 重进后应保持拖动后的顺序
    final reorderAgain = await PlaylistService.getPlaylists();
    expect(reorderAgain.first.songs.map((s) => s.bvid).toList(),
        order.first.songs.map((s) => s.bvid).toList());

    // 卸载页面并释放服务定时器，避免 pending timer
    await tester.pumpWidget(const SizedBox());
    AudioPlayerService().disposeForTest();
  });

  testWidgets('我喜欢歌单拖动后重进保持顺序（回归）', (tester) async {
    // 构造收藏：BV1..BV5
    await AudioPlayerService.saveFavoritesOrder(['BV1', 'BV2', 'BV3', 'BV4', 'BV5']);
    expect(await AudioPlayerService.getFavorites(), ['BV1', 'BV2', 'BV3', 'BV4', 'BV5']);

    // 模拟拖动：把第3首(BV3)拖到第1位 → 保存
    await AudioPlayerService.saveFavoritesOrder(['BV3', 'BV1', 'BV2', 'BV4', 'BV5']);
    expect(await AudioPlayerService.getFavorites(), ['BV3', 'BV1', 'BV2', 'BV4', 'BV5']);

    // 用 SongListPage 渲染"我喜欢"并验证重进应用顺序
    final songs = [for (var i = 1; i <= 5; i++) _song('BV$i', '歌$i')];
    final favPlaylist = Playlist(id: 'fav', name: '我喜欢', icon: '❤️', songs: songs);
    await tester.pumpWidget(MaterialApp(home: SongListPage(playlist: favPlaylist)));
    await tester.pump(const Duration(milliseconds: 200)); // 等待 _applyPersistedOrder

    // 第一首应为 BV3（拖动后的顺序）
    final firstRow = find.byType(ListTile).first;
    final titleText = firstRow.evaluate().isEmpty ? null : tester.widget<Text>(find.descendant(of: firstRow, matching: find.byType(Text)).first);
    // 歌3 应排在列表第一行（第一个 ListTile 的标题）
    final firstTile = find.byType(ListTile).first;
    final firstTitle = tester.widget<Text>(
      find.descendant(of: firstTile, matching: find.byType(Text)).first,
    );
    expect(firstTitle.data, '歌3');

    await tester.pumpWidget(const SizedBox());
    AudioPlayerService().disposeForTest();
  });
}
