import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('reorderSongsInPlaylist 重排并持久化歌单顺序', () async {
    // 创建歌单：3 首歌
    await PlaylistService.addPlaylist('测试歌单');
    final pls = await PlaylistService.getPlaylists();
    final pl = pls.first;
    await PlaylistService.addSongsToPlaylist(pl.id, ['BV1', 'BV2', 'BV3']);
    var got = await PlaylistService.getPlaylists();
    expect(got.first.songs.map((s) => s.bvid).toList(), ['BV1', 'BV2', 'BV3']);

    // 重排：BV3 移到最前
    await PlaylistService.reorderSongsInPlaylist(pl.id, ['BV3', 'BV1', 'BV2']);
    got = await PlaylistService.getPlaylists();
    expect(got.first.songs.map((s) => s.bvid).toList(), ['BV3', 'BV1', 'BV2']);
  });
}
