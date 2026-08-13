import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/bilibili_api.dart';

void main() {
  test('视频下载进度链路实测', () async {
    final api = BilibiliApi();
    final durl = await api.resolveVideoDurl('BV1RVKd6YERS', 39522274217, 80);
    // ignore: avoid_print
    print('DURL=$durl');
    expect(durl, isNotNull);

    final events = <String>[];
    final ok = await StreamDownloader.download(
      url: durl!,
      savePath: 'build_test/out.mp4',
      onProgress: (p) => events.add('p=${p.toStringAsFixed(3)}'),
      onSize: (r, t) => events.add('s=$r/$t'),
    );
    // ignore: avoid_print
    print('OK=$ok events=${events.take(8).toList()} total=${events.length}');
  });
}
