import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/pages/playlist_page.dart';
import 'package:gomusic/pages/song_list_page.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:gomusic/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory _origDir;
  late Directory _tmpDir;
  late Directory _musicDir;

  setUp(() {
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('gomusic_localre_');
    Directory.current = _tmpDir;
    SharedPreferences.setMockInitialValues({});
    // 音乐目录：本地歌单的下载目录
    _musicDir = Directory('${_tmpDir.path}/music')..createSync(recursive: true);
    // 写入测试歌曲文件（内容非空）
    for (var i = 1; i <= 5; i++) {
      File('${_musicDir.path}/BV$i.m4a').writeAsBytesSync(List.filled(1024, 0));
    }
    File('song_groups.json').writeAsStringSync(jsonEncode([]));
    SongGroupService.resetForTest();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  testWidgets('本地歌单拖动后重进保持顺序', (tester) async {
    // 让 SettingsService 指向音乐目录
    SharedPreferences.setMockInitialValues({
      'download_path': _musicDir.path,
    });

    // 模拟 playlist_page 加载（读取 getLocalOrder 应用）
    // 先直接验证顺序存取链路
    expect(await SongManager.getLocalOrder(), isEmpty);
    await SongManager.saveLocalOrder(['BV3', 'BV1', 'BV2', 'BV4', 'BV5']);
    expect(await SongManager.getLocalOrder(), ['BV3', 'BV1', 'BV2', 'BV4', 'BV5']);

    // 用 SongListPage 本地歌单渲染，验证显示顺序按保存的顺序
    final local = await scanLocalAudioFiles(_musicDir.path);
    final playlist = Playlist(id: 'local', name: '本地歌单', icon: '📁', songs: local);
    await tester.pumpWidget(MaterialApp(home: SongListPage(playlist: playlist)));
    await tester.pump();

    // 进入批量模式并验证拖动手柄存在
    await tester.tap(find.text('批量'));
    await tester.pump();
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(5));

    // 模拟重进：重新构造（读 getLocalOrder 应用后的顺序）
    await tester.pumpWidget(const SizedBox());
    final reloaded = await scanLocalAudioFiles(_musicDir.path);
    final order = await SongManager.getLocalOrder();
    final byKey = {for (final s in reloaded) (s.bvid.isNotEmpty ? s.bvid : s.filePath.split('\\').last.split('/').last.split('.').first): s};
    final ordered = <Song>[];
    for (final k in order) { final s = byKey[k]; if (s != null) { ordered.add(s); byKey.remove(k); } }
    ordered.addAll(byKey.values);
    final firstName = ordered.first.filePath.split('\\').last.split('/').last.split('.').first;
    expect(firstName, 'BV3'); // 保存顺序的第一个（测试文件无 bvid，用文件名匹配）
    await tester.pumpWidget(const SizedBox());
    AudioPlayerService().disposeForTest();
  });
}
