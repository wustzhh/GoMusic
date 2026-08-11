import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/pages/song_list_page.dart';
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
    _tmpDir = Directory.systemTemp.createTempSync('slist_');
    Directory.current = _tmpDir; // 隔离：避免 _saveState 写真实 save_state.json
    // 用真实下载目录的歌曲（只读扫描）
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  testWidgets('真实歌单：点击第3首播放第3首', (tester) async {
    // 测试环境加大尺寸，避免 mini bar 布局溢出
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 真实下载目录
    final realDir = r'D:\GitHubProject\GoMusic\downloads';
    final songs = await scanLocalAudioFiles(realDir);
    if (songs.length < 3) { markTestSkipped('真实歌单不足3首'); return; }
    final realPlaylist = Playlist(id: 'local', name: '本地歌单', icon: '', songs: songs);

    await tester.pumpWidget(MaterialApp(home: SongListPage(playlist: realPlaylist)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // 点击第 3 首歌的行（限定在 ListTile 内，避免命中 mini bar 同名标题）
    final third = songs[2].title;
    final tile = find.ancestor(of: find.text(third), matching: find.byType(ListTile)).first;
    expect(tile, findsOneWidget, reason: '第3首标题应在歌单列表行中');
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final svc = AudioPlayerService();
    print('点击第3首(${songs[2].bvid}) 后 currentSong: ${svc.currentSong?.bvid}, queueIndex: ${svc.queueIndex}');
    expect(svc.currentSong?.bvid, songs[2].bvid, reason: '点击第3首应播放第3首');
    // 队列按歌单显示顺序（标题序），点击的歌应定位到其在队列中的位置
    final expectIdx = svc.queue.indexWhere((s) => s.bvid == songs[2].bvid);
    expect(expectIdx, greaterThanOrEqualTo(0), reason: '点击的歌应在队列中');
    expect(svc.queueIndex, expectIdx, reason: '队列索引应指向点击的歌');
  });

  testWidgets('真实歌单：点击第1首播放第1首', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final realDir = r'D:\GitHubProject\GoMusic\downloads';
    final songs = await scanLocalAudioFiles(realDir);
    if (songs.length < 1) { markTestSkipped('真实歌单为空'); return; }
    final realPlaylist = Playlist(id: 'local', name: '本地歌单', icon: '', songs: songs);

    await tester.pumpWidget(MaterialApp(home: SongListPage(playlist: realPlaylist)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    final first = songs[0].title;
    final tile = find.ancestor(of: find.text(first), matching: find.byType(ListTile)).first;
    expect(tile, findsOneWidget, reason: '第1首标题应在歌单列表行中');
    await tester.tap(tile);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final svc = AudioPlayerService();
    print('点击第1首(${songs[0].bvid}) 后 currentSong: ${svc.currentSong?.bvid}');
    expect(svc.currentSong?.bvid, songs[0].bvid, reason: '点击第1首应播放第1首');
    final expectIdx = svc.queue.indexWhere((s) => s.bvid == songs[0].bvid);
    expect(expectIdx, greaterThanOrEqualTo(0));
    expect(svc.queueIndex, expectIdx);
  });
}
