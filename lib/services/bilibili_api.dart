import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// 单个视频流（一种画质）
class VideoStream {
  final int id;
  final int bandwidth;
  final int width;
  final int height;
  final String codecs;
  final String? baseUrl;
  final int size;

  const VideoStream({
    required this.id,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.codecs,
    this.baseUrl,
    this.size = 0,
  });

  String get qualityLabel {
    if (width >= 7680) return '8K';
    if (width >= 3840) return '4K';
    if (width >= 2560) return '2K';
    if (width >= 1920) {
      if (height >= 1080) return '1080P';
      return '1080P';
    }
    if (width >= 1280) return '720P';
    if (width >= 852) return '480P';
    return '360P';
  }

  String get sizeText {
    if (size <= 0) return '未知';
    if (size < 1048576) return '${(size / 1024).toStringAsFixed(0)}KB';
    return '${(size / 1048576).toStringAsFixed(1)}MB';
  }

  String get description => '$qualityLabel · ${width}x$height · $sizeText';
}

/// B站视频信息（含流信息）
class BilibiliVideoInfo {
  final String bvid;
  final String title;
  final String author;
  final String coverUrl;
  final int durationSeconds;
  final String url;
  final int cid;

  String? audioUrl;
  int audioSize = 0;
  List<VideoStream> videoStreams = [];

  BilibiliVideoInfo({
    required this.bvid,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.durationSeconds,
    required this.url,
    required this.cid,
  });

  String get durationText {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get audioSizeText {
    if (audioSize <= 0) return '未知';
    if (audioSize < 1048576) return '${(audioSize / 1024).toStringAsFixed(0)}KB';
    return '${(audioSize / 1048576).toStringAsFixed(1)}MB';
  }
}

/// B站 API 服务
class BilibiliApi {
  static String? _mixinKey;
  static int _mixinKeyExpire = 0;

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

  /// 设置 B站 Cookie
  static String? cookie;
  Map<String, String> get _headers => {
        'User-Agent': _ua,
        'Referer': 'https://www.bilibili.com/',
        if (cookie != null && cookie!.isNotEmpty) 'Cookie': cookie!,
      };

  static String? extractBvid(String url) {
    final m = RegExp(r'BV[a-zA-Z0-9]{10}').firstMatch(url);
    return m?.group(0);
  }

  // ---- wbi 签名 ----

  Future<String> _mixin() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_mixinKey != null && now < _mixinKeyExpire) return _mixinKey!;
    try {
      final r = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
        headers: _headers,
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        final w = d['data']['wbi_img'] ?? {};
        final a = (w['img_url'] as String? ?? '').split('/').last.split('.').first;
        final b = (w['sub_url'] as String? ?? '').split('/').last.split('.').first;
        final s = a + b;
        const map = [
          46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,
          27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,
          37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,
          22,25,54,21,56,59,6,63,57,62,11,36,20,34,44,52,
        ];
        final buf = StringBuffer();
        for (final i in map) {
          if (i < s.length) buf.write(s[i]);
        }
        _mixinKey = buf.toString().substring(0, 32);
        _mixinKeyExpire = now + 3600;
        return _mixinKey!;
      }
    } catch (_) {}
    return '';
  }

  String _sign(Map<String, String> p, String k) {
    final keys = p.keys.toList()..sort();
    final q = keys.map((x) => '$x=${Uri.encodeComponent(p[x]!)}').join('&');
    return md5.convert(utf8.encode(q + k)).toString();
  }

  Future<Map<String, String>> _signed(Map<String, String> base) async {
    final k = await _mixin();
    if (k.isEmpty) return base;
    final wts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    base['wts'] = wts.toString();
    base['w_rid'] = _sign(Map.from(base), k);
    return base;
  }

  // ---- API ----

  /// 获取视频信息（含流大小）
  Future<BilibiliVideoInfo?> getVideoInfo(String url) async {
    final bvid = extractBvid(url);
    if (bvid == null) return null;

    try {
      final p = await _signed({'bvid': bvid});
      final uri = Uri.parse('https://api.bilibili.com/x/web-interface/view')
          .replace(queryParameters: p);

      final r = await http.get(uri, headers: _headers);
      if (r.statusCode != 200) return null;

      final d = jsonDecode(r.body);
      if (d['code'] != 0) return null;

      final v = d['data'];
      final info = BilibiliVideoInfo(
        bvid: bvid,
        title: v['title'] as String? ?? '',
        author: v['owner']?['name'] as String? ?? '',
        coverUrl: (v['pic'] as String? ?? '').replaceAll('http:', 'https:'),
        durationSeconds: v['duration'] as int? ?? 0,
        url: url,
        cid: v['cid'] as int? ?? (v['pages']?[0]?['cid'] as int? ?? 0),
      );

      await _fetchStreams(info);
      return info;
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchStreams(BilibiliVideoInfo info) async {
    if (info.cid == 0) return;
    try {
      final p = await _signed({
        'bvid': info.bvid,
        'cid': info.cid.toString(),
        'fnver': '0',
        'fnval': '4048',  // DASH + HDR + 杜比 + 4K
        'fourk': '1',
        'qn': '127',       // 请求最高画质 (127=8K, 120=4K, 116=1080P60)
      });

      final uri = Uri.parse('https://api.bilibili.com/x/player/wbi/playurl')
          .replace(queryParameters: p);

      final r = await http.get(uri, headers: _headers);
      if (r.statusCode != 200) return;

      final d = jsonDecode(r.body);
      if (d['code'] != 0) return;

      final dash = d['data']['dash'];
      if (dash == null) return;

      // 音频流：按码率降序取最高质量
      final audios = (dash['audio'] as List?) ?? [];
      if (audios.isNotEmpty) {
        audios.sort((a, b) =>
            ((b['bandwidth'] as int?) ?? 0).compareTo((a['bandwidth'] as int?) ?? 0));
        final best = audios.first;
        info.audioUrl = (best['baseUrl'] ?? best['base_url']) as String?;
        info.audioSize = (best['size'] as int?) ?? 0;
      }

      // 视频流：全部保存，按码率降序排列
      final videos = (dash['video'] as List?) ?? [];
      info.videoStreams = videos.map((v) => VideoStream(
        id: (v['id'] as int?) ?? 0,
        bandwidth: (v['bandwidth'] as int?) ?? 0,
        width: (v['width'] as int?) ?? 0,
        height: (v['height'] as int?) ?? 0,
        codecs: (v['codecs'] as String?) ?? '',
        baseUrl: (v['baseUrl'] ?? v['base_url']) as String?,
        size: (v['size'] as int?) ?? 0,
      )).toList()
        ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    } catch (_) {}
  }
}

/// 下载工具：带进度的流式下载
class StreamDownloader {
  static Future<bool> download({
    required String url,
    required String savePath,
    required void Function(double progress) onProgress,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll({
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://www.bilibili.com/',
        if (BilibiliApi.cookie != null && BilibiliApi.cookie!.isNotEmpty)
          'Cookie': BilibiliApi.cookie!,
      });

      final streamed = await request.send();
      final total = streamed.contentLength ?? 0;
      var received = 0;

      // 确保目录存在
      final file = File(savePath);
      await file.parent.create(recursive: true);

      final sink = file.openWrite();
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        sink.add(chunk);
        if (total > 0) {
          onProgress(received / total);
        }
      }
      await sink.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
