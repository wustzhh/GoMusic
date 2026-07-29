import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// B站视频信息
class BilibiliVideoInfo {
  final String bvid;
  final String title;
  final String author;
  final String coverUrl;
  final int durationSeconds;
  final String url;

  const BilibiliVideoInfo({
    required this.bvid,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.durationSeconds,
    required this.url,
  });

  String get durationText {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

/// B站 API 服务（wbi 签名 + 视频信息获取）
class BilibiliApi {
  static String? _mixinKey;
  static int _mixinKeyExpire = 0;

  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  /// 从 URL 中提取 BV 号
  static String? extractBvid(String url) {
    // 匹配 BV 号：BV + 10位字母数字
    final regex = RegExp(r'BV[a-zA-Z0-9]{10}');
    final match = regex.firstMatch(url);
    return match?.group(0);
  }

  /// 获取 mixin_key（用于 wbi 签名）
  static Future<String> _getMixinKey() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_mixinKey != null && now < _mixinKeyExpire) {
      return _mixinKey!;
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
        headers: {
          'User-Agent': _userAgent,
          'Referer': 'https://www.bilibili.com/',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final wbiImg = data['data']['wbi_img'] ?? {};
        final imgKey = (wbiImg['img_url'] as String? ?? '')
            .split('/')
            .last
            .split('.')
            .first;
        final subKey = (wbiImg['sub_url'] as String? ?? '')
            .split('/')
            .last
            .split('.')
            .first;

        final mixed = imgKey + subKey;
        // 固定映射表（B站 wbi 签名标准映射）
        const mapping = [
          46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
          27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
          37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
          22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52,
        ];

        final keyBuilder = StringBuffer();
        for (final idx in mapping) {
          if (idx < mixed.length) {
            keyBuilder.write(mixed[idx]);
          }
        }
        _mixinKey = keyBuilder.toString().substring(0, 32);
        _mixinKeyExpire = now + 3600; // 缓存1小时
        return _mixinKey!;
      }
    } catch (_) {
      // 降级：返回空 key
    }
    return '';
  }

  /// wbi 签名
  static String _wbiSign(Map<String, String> params, String mixinKey) {
    // 按 key 排序
    final sortedKeys = params.keys.toList()..sort();
    final query = sortedKeys.map((k) => '$k=${Uri.encodeComponent(params[k]!)}').join('&');
    final signStr = query + mixinKey;
    return md5.convert(utf8.encode(signStr)).toString();
  }

  /// 获取视频信息
  static Future<BilibiliVideoInfo?> getVideoInfo(String url) async {
    final bvid = extractBvid(url);
    if (bvid == null) return null;

    try {
      final mixinKey = await _getMixinKey();
      final wts = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final params = <String, String>{'bvid': bvid};
      if (mixinKey.isNotEmpty) {
        params['wts'] = wts.toString();
        params['w_rid'] = _wbiSign(params, mixinKey);
      }

      final uri = Uri.parse('https://api.bilibili.com/x/web-interface/view')
          .replace(queryParameters: params);

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Referer': 'https://www.bilibili.com/',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 0) {
          final videoData = data['data'];
          return BilibiliVideoInfo(
            bvid: bvid,
            title: videoData['title'] as String? ?? '',
            author: videoData['owner']?['name'] as String? ?? '',
            coverUrl: (videoData['pic'] as String? ?? '').replaceAll('http:', 'https:'),
            durationSeconds: videoData['duration'] as int? ?? 0,
            url: url,
          );
        }
      }
    } catch (_) {
      // 网络错误
    }
    return null;
  }
}
