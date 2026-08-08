import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  String sep = Platform.pathSeparator;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('gomusic_meta_');
    await SongManager.init(tmpDir.path);
  });

  tearDown(() {
    try { tmpDir.deleteSync(recursive: true); } catch (_) {}
  });

  test('混合分隔符路径注册后扫描能查回标题（回归：BV号问题）', () {
    // 模拟下载页：Windows 反斜杠目录 + 正斜杠文件名拼接 → 混合分隔符
    final mixedPath = '${tmpDir.path}/BV1test12345.m4a';
    File(mixedPath).writeAsBytesSync(List.filled(1024, 0));

    SongManager.registerSong(
      filePath: mixedPath,
      title: '测试歌曲标题',
      uploader: 'UP主',
      durationSec: 180,
      bvid: 'BV1test12345',
      url: 'https://www.bilibili.com/video/BV1test12345',
    );

    final songs = SongManager.scanLocalSongs();
    expect(songs.length, 1);
    // 关键断言：标题必须来自元数据，而不是回退成文件名（BV号）
    expect(songs.first.title, '测试歌曲标题');
    expect(songs.first.bvid, 'BV1test12345');
  });

  test('历史混合分隔符 metadata_map.json 自动迁移后标题可查回', () {
    // 构造历史数据：key 为混合分隔符（模拟旧版本写入）
    final legacy = <String, dynamic>{
      '${tmpDir.path}/BV1legacy0001.m4a': {
        'title': '旧数据歌曲',
        'uploader': '老UP',
        'duration': 90,
        'bvid': 'BV1legacy0001',
        'url': '',
        'coverPath': '',
        'videoPath': '',
      },
    };
    File('${tmpDir.path}$sep${'metadata_map.json'}').writeAsStringSync(
      legacy.keys.first.replaceAll('\\', '/').isEmpty ? '' : legacy.toString(),
    );
    // 直接写混合分隔符的 JSON
    final mixedKey = '${tmpDir.path}/BV1legacy0001.m4a';
    File('${tmpDir.path}$sep${'metadata_map.json'}').writeAsStringSync(
      '{"${mixedKey.replaceAll('\\', r'\\')}":{"title":"旧数据歌曲","uploader":"老UP","duration":90,"bvid":"BV1legacy0001","url":"","coverPath":"","videoPath":""}}',
    );
    File(mixedKey).writeAsBytesSync(List.filled(512, 0));

    final songs = SongManager.scanLocalSongs();
    expect(songs.length, 1);
    expect(songs.first.title, '旧数据歌曲');
    expect(songs.first.bvid, 'BV1legacy0001');
  });

  test('updateDuration/unregisterSong 用归一化 key 命中', () {
    final path = '${tmpDir.path}/BV1update0002.m4a';
    File(path).writeAsBytesSync(List.filled(256, 0));
    SongManager.registerSong(
      filePath: path,
      title: '时长测试',
      uploader: 'u',
      durationSec: 10,
      bvid: 'BV1update0002',
      url: '',
    );
    SongManager.updateDuration(path, 999);
    // 时长已更新
    var songs = SongManager.scanLocalSongs();
    expect(songs.first.duration.inSeconds, 999);
    // 注销登记后：文件仍在但元数据已删，标题回退为文件名（无 BV 信息）
    SongManager.unregisterSong(path);
    songs = SongManager.scanLocalSongs();
    expect(songs.length, 1);
    expect(songs.first.bvid, isEmpty);
    expect(songs.first.title, 'BV1update0002');
  });
}
