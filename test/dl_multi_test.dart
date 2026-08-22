import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/bilibili_api.dart';

void main() {
  test('多链接批量解析实测(用户提供的7个)', () async {
    const raw = '''
https://www.bilibili.com/video/BV13M3U6HEBr
https://www.bilibili.com/video/BV186GU6WEDV
https://www.bilibili.com/video/BV1UNL56FEm3
https://www.bilibili.com/video/BV1GmME6aEWi
https://www.bilibili.com/video/BV1qMs9eeEF2
https://www.bilibili.com/video/BV1Sc411A7yn
https://www.bilibili.com/video/BV1ox6zBuE4b
''';
    final urls = RegExp(r'https?://\S+').allMatches(raw.trim()).map((m) {
      var u = m.group(0)!;
      return u.replaceFirst(RegExp(r'[^A-Za-z0-9/:_?=&.%-]+$'), '');
    }).toList();
    // ignore: avoid_print
    print('提取到 ${urls.length} 个URL: $urls');
    final api = BilibiliApi();
    var ok = 0;
    final fails = <String>[];
    for (final u in urls) {
      final info = await api.getVideoInfo(u);
      if (info != null) {
        ok++;
      } else {
        fails.add(u);
      }
    }
    // ignore: avoid_print
    print('解析成功=$ok/${urls.length} 失败=${fails.length}');
    if (fails.isNotEmpty) {
      // ignore: avoid_print
      print('失败: ${fails.join('\n')}');
    }
    expect(fails, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
