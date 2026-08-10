import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Song _song(String bvid, String title) => Song(
      id: bvid,
      title: title,
      uploader: 'u',
      duration: const Duration(seconds: 100),
      bvid: bvid,
      filePath: 'C:/x/$bvid.mp3',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory _origDir;
  late Directory _tmpDir;

  setUp(() {
    // 隔离到临时工作目录：所有测试（含 save_state.json / song_groups.json 读写）
    // 绝不触碰项目根目录的真实数据文件
    _origDir = Directory.current;
    _tmpDir = Directory.systemTemp.createTempSync('gomusic_qltest_');
    Directory.current = _tmpDir;

    SharedPreferences.setMockInitialValues({});
    // 注入假播放内核：测试环境无法加载 libmpv（media_kit 用 FFI）
    injectFakePlayer();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = _origDir;
    try { _tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  test('非随机模式 setQueue keepOrder 保持列表顺序', () {
    final svc = AudioPlayerService();
    // 默认 loopList 模式
    expect(svc.playMode, isNot(PlayMode.shuffle));
    final songs = [_song('BV1', 'A'), _song('BV2', 'B'), _song('BV3', 'C')];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    expect(svc.queue.map((s) => s.bvid).toList(), ['BV1', 'BV2', 'BV3']);
    expect(svc.queueIndex, 0);
  });

  test('随机模式 setQueue 播放全部后队列已随机化且索引指向随机后第一首', () {
    final svc = AudioPlayerService();
    svc.setPlayMode(PlayMode.shuffle);
    final songs = [_song('BV1', 'A'), _song('BV2', 'B'), _song('BV3', 'C'), _song('BV4', 'D')];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    // 随机化后：队列包含全部 4 首（顺序随机），索引=0（随机后第一首）
    expect(svc.queue.length, 4);
    expect(svc.queue.map((s) => s.bvid).toSet(), {'BV1', 'BV2', 'BV3', 'BV4'});
    expect(svc.queueIndex, 0);
  });

  test('切回非随机模式恢复原顺序队列', () {
    final svc = AudioPlayerService();
    final songs = [_song('BV1', 'A'), _song('BV2', 'B'), _song('BV3', 'C')];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    svc.setPlayMode(PlayMode.shuffle);
    svc.setPlayMode(PlayMode.loopList);
    expect(svc.queue.map((s) => s.bvid).toSet(), {'BV1', 'BV2', 'BV3'});
  });

  test('随机模式：切换一次随机化后队列固定，后续 setPlayMode 幂等不重新随机', () {
    final svc = AudioPlayerService();
    final songs = [_song('BV1', 'A'), _song('BV2', 'B'), _song('BV3', 'C'), _song('BV4', 'D'), _song('BV5', 'E')];
    svc.setQueue(songs, startIndex: 0, playlistId: 'local', keepOrder: true);
    // 切到随机：整体随机化一次
    svc.setPlayMode(PlayMode.shuffle);
    final shuffled1 = List<Song>.from(svc.queue);
    expect(shuffled1.map((s) => s.bvid).toSet(), {'BV1', 'BV2', 'BV3', 'BV4', 'BV5'});
    expect(svc.queueIndex, 0);
    // 已是 shuffle 时再次 setPlayMode：幂等，不重新随机化（队列保持不变）
    svc.setPlayMode(PlayMode.shuffle);
    expect(svc.queue.map((s) => s.bvid).toList(), shuffled1.map((s) => s.bvid).toList());
  });

  test('restoreLastSong 恢复上次播放进度（杀进程后续播，回归）', () async {
    final svc = AudioPlayerService();
    // 构造 save_state.json：position=125秒
    final f = File('save_state.json');
    f.writeAsStringSync(jsonEncode({
      'song': 'C:/x/BV1.m4a', 'title': '歌1', 'uploader': 'u',
      'duration': 300, 'bvid': 'BV1', 'cover': '',
      'position': 125000, 'queue': ['BV1', 'BV2'], 'queue_index': 0,
    }));
    final restored = await svc.restoreLastSong();
    expect(restored, isNotNull);
    expect(restored!.bvid, 'BV1');
    // 恢复上次保存的进度：125 秒（用户要求杀进程/退出后从上次位置续播）
    expect(svc.currentPosition.inMilliseconds, 125000);
    // 清理测试文件
    try { f.deleteSync(); } catch (_) {}
    try { File('song_groups.json').deleteSync(); } catch (_) {}
  });
}
