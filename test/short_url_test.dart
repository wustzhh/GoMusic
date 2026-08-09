import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/bilibili_api.dart';

void main() {
  test('b23.tv 短链解析出 BV 号（真实网络）', () async {
    final url = 'https://b23.tv/8auwofV';
    final real = await BilibiliApi.resolveShortUrl(url);
    print('解析后: $real');
    final bvid = BilibiliApi.extractBvid(real);
    print('BV号: $bvid');
    expect(bvid, isNotNull);
    expect(bvid, startsWith('BV'));
    expect(bvid!.length, 12);
  });

  test('普通链接直接返回原 URL', () async {
    final url = 'https://www.bilibili.com/video/BV1Ubjc6FEfr/';
    final real = await BilibiliApi.resolveShortUrl(url);
    expect(real, url);
  });
}
