import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/bilibili_api.dart';
import 'package:gomusic/services/download_file_matcher.dart';

void main() {
  test('extractUrls returns every unique Bilibili link in pasted text', () {
    const pasted = '''
https://www.bilibili.com/video/BV1ds411f7Hy
some text https://www.bilibili.com/video/BV1np4y1N74z\n
https://www.bilibili.com/video/BV1ds411f7Hy
''';

    expect(BilibiliApi.extractUrls(pasted), [
      'https://www.bilibili.com/video/BV1ds411f7Hy',
      'https://www.bilibili.com/video/BV1np4y1N74z',
    ]);
  });

  test('extractUrls splits copied links even when newlines are lost', () {
    const pasted =
        'https://www.bilibili.com/video/BV1ds411f7Hy'
        'https://www.bilibili.com/video/BV1np4y1N74z'
        'https://www.bilibili.com/video/BV1Ut411D7rY';

    expect(BilibiliApi.extractUrls(pasted), [
      'https://www.bilibili.com/video/BV1ds411f7Hy',
      'https://www.bilibili.com/video/BV1np4y1N74z',
      'https://www.bilibili.com/video/BV1Ut411D7rY',
    ]);
  });

  test('hasMediaFile recognizes downloaded video files', () async {
    final dir = await Directory.systemTemp.createTemp(
      'gomusic_download_match_',
    );
    addTearDown(() => dir.delete(recursive: true));

    File('${dir.path}/BVvideo.mp4').writeAsBytesSync([1]);

    expect(
      DownloadFileMatcher.hasMediaFile(
        directory: dir.path,
        bvid: 'BVvideo',
        title: '未使用的标题',
      ),
      isTrue,
    );
  });
}
