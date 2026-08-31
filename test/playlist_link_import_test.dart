import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/bilibili_api.dart';
import 'package:gomusic/services/playlist_link_importer.dart';
import 'package:gomusic/models/music_data.dart';

void main() {
  test('歌单链接导入按链接顺序匹配本地歌曲并去重', () {
    final local = [
      const Song(
        id: 'two',
        title: '第二首',
        uploader: '',
        duration: Duration.zero,
        bvid: 'BV2222222222',
        filePath: 'two.m4a',
      ),
      const Song(
        id: 'one',
        title: '第一首',
        uploader: '',
        duration: Duration.zero,
        bvid: 'BV1111111111',
        filePath: 'one.m4a',
      ),
    ];
    final links = [
      'https://www.bilibili.com/video/BV1111111111',
      'https://www.bilibili.com/video/BV9999999999',
      'https://www.bilibili.com/video/BV2222222222?p=1',
      'https://www.bilibili.com/video/BV1111111111',
    ];

    final result = PlaylistLinkImporter.matchLocalSongs(links, local);

    expect(result.songs.map((s) => s.bvid), ['BV1111111111', 'BV2222222222']);
    expect(result.missingBvids, ['BV9999999999']);
  });

  test('连续粘贴的多个链接仍能按顺序提取', () {
    final links = BilibiliApi.extractUrls(
      'https://www.bilibili.com/video/BV1111111111https://www.bilibili.com/video/BV2222222222',
    );
    expect(links, [
      'https://www.bilibili.com/video/BV1111111111',
      'https://www.bilibili.com/video/BV2222222222',
    ]);
  });
  test('b23.tv 短链接解析后按顺序匹配本地歌曲', () async {
    const local = [
      Song(
        id: 'short',
        title: '短链歌曲',
        uploader: '',
        duration: Duration.zero,
        bvid: 'BV3333333333',
        filePath: 'short.m4a',
      ),
    ];
    final result = await PlaylistLinkImporter.matchLocalSongsAsync(
      ['https://b23.tv/abc'],
      local,
      resolveShortUrl: (_) async =>
          'https://www.bilibili.com/video/BV3333333333?p=1',
    );

    expect(result.songs.map((s) => s.bvid), ['BV3333333333']);
    expect(result.missingBvids, isEmpty);
  });
}
