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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('popscope_');
    Directory.current = _tmpDir; // 隔离：避免 _saveState 写真实 save_state.json
    for (var i = 1; i <= 3; i++) {
      File('${_tmpDir.path}/BV$i.mp3').writeAsBytesSync(List.filled(1024, 0));
    }
  });
  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  testWidgets('批量模式按返回键 = 取消批量，不退出页面', (tester) async {
    final songs = List.generate(3, (i) => Song(
      id: 'BV${i+1}', title: '歌${i+1}', uploader: 'u',
      duration: const Duration(seconds: 60), bvid: 'BV${i+1}',
      filePath: '${_tmpDir.path}/BV${i+1}.mp3',
    ));
    // 构建一个导航栈：主页 → SongListPage
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => Scaffold(
        body: Center(child: ElevatedButton(
          onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => SongListPage(
            playlist: Playlist(id: 'local', name: '本地歌单', icon: '', songs: songs),
          ))),
          child: const Text('进入歌单'),
        )),
      )),
    ));
    await tester.tap(find.text('进入歌单'));
    await tester.pumpAndSettle();

    // 进入批量模式
    await tester.tap(find.text('批量'));
    await tester.pump();
    expect(find.text('取消选择'), findsOneWidget, reason: '批量模式开启');

    // 按返回键（批量模式下 leading 是"取消批量"按钮）
    await tester.tap(find.byTooltip('取消批量'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 应取消批量：仍在歌单页，且批量按钮恢复为"批量"
    expect(find.text('批量'), findsOneWidget, reason: '返回键应取消批量');
    expect(find.text('取消选择'), findsNothing, reason: '批量模式应已退出');
    expect(find.text('本地歌单 (3首)'), findsOneWidget, reason: '仍停留在歌单页');
  });
}
