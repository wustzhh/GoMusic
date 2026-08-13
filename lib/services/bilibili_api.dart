import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 单个视频流（一种画质）
class VideoStream {
  final int id;
  final int bandwidth;
  final int width;
  final int height;
  final String codecs;
  final String? baseUrl;
  int size;

  VideoStream({
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
  static String? _buvid3;

  /// 获取 buvid3（B站匿名标识，缺失会导致 wbi/playurl 返回 412）
  static Future<void> ensureBuvid3() async {
    if (_buvid3 != null) return;
    try {
      final r = await http.get(
        Uri.parse('https://api.bilibili.com/x/frontend/finger/spi'),
        headers: {'User-Agent': _ua, 'Referer': 'https://www.bilibili.com/'},
      );
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        final b3 = d['data']?['b_3'] as String?;
        if (b3 != null && b3.isNotEmpty) _buvid3 = 'buvid3=$b3';
      }
    } catch (_) {}
  }

  Map<String, String> get _headers {
    var ck = cookie ?? '';
    if (_buvid3 != null && _buvid3!.isNotEmpty) {
      ck = ck.isEmpty ? _buvid3! : '$ck; $_buvid3';
    }
    return {
      'User-Agent': _ua,
      'Referer': 'https://www.bilibili.com/',
      if (ck.isNotEmpty) 'Cookie': ck,
    };
  }

  static String? extractBvid(String url) {
    final m = RegExp(r'BV[a-zA-Z0-9]{10}').firstMatch(url);
    return m?.group(0);
  }

  /// 解析 b23.tv 短链：跟随重定向返回真实 URL（含 BV 号/合集ID）。
  /// 非短链直接返回原 URL；失败也返回原 URL（由后续逻辑兜底）。
  static Future<String> resolveShortUrl(String url) async {
    final t = url.trim();
    if (!t.contains('b23.tv')) return t;
    try {
      final c = HttpClient();
      final req = await c.getUrl(Uri.parse(t));
      req.headers.set('User-Agent', _ua);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      // 最终地址：重定向链最后一个（HttpClient 自动跟随重定向）
      var finalUrl = resp.redirects.isNotEmpty
          ? resp.redirects.last.location.toString()
          : t;
      // location 可能是相对路径（如 /video/BVxxx），补全为完整 URL
      if (finalUrl.startsWith('/')) {
        final base = resp.redirects.isNotEmpty ? resp.redirects.first.location : Uri.parse(t);
        final host = base.host.isEmpty ? Uri.parse(t).host : base.host;
        finalUrl = 'https://$host$finalUrl';
      }
      c.close();
      await resp.drain<void>();
      return finalUrl;
    } catch (_) {
      return t;
    }
  }

  // ---- wbi 签名 ----

  Future<String> _mixin() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_mixinKey != null && now < _mixinKeyExpire) return _mixinKey!;
    try {
      final r = await http.get(
        Uri.parse('https://api.bilibili.com/x/web-interface/nav'),
        headers: _headers,
      ).timeout(const Duration(seconds: 5));
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
    // b23.tv 短链：先解析出真实 URL 再提取 BV 号
    var bvid = extractBvid(url);
    if (bvid == null && url.contains('b23.tv')) {
      final real = await resolveShortUrl(url);
      bvid = extractBvid(real);
    }
    if (bvid == null) return null;

    try {
      final p = await _signed({'bvid': bvid});
      final uri = Uri.parse('https://api.bilibili.com/x/web-interface/view')
          .replace(queryParameters: p);

      final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
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

  /// 请求播放地址（wbi 接口失败时降级到非 wbi），返回解析后的 JSON
  Future<Map<String, dynamic>?> _playUrl(Map<String, String> params) async {
    try {
      var p = await _signed(params);
      var uri = Uri.parse('https://api.bilibili.com/x/player/wbi/playurl')
          .replace(queryParameters: p);
      var r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      // 签名可能过期/被风控：刷新 mixinKey 重试一次（不降级到无签名接口，避免清晰度受限）
      if (r.statusCode != 200 || (jsonDecode(r.body)['code'] != 0 && r.body.isNotEmpty)) {
        _mixinKey = null;
        _mixinKeyExpire = 0;
        p = await _signed(params);
        uri = Uri.parse('https://api.bilibili.com/x/player/wbi/playurl')
            .replace(queryParameters: p);
        r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      }
      if (r.statusCode != 200) return null;
      final d = jsonDecode(r.body);
      if (d['code'] != 0) return null;
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 下载视频时按需取带音轨的 durl 合并流 URL（MP4 自带音轨）
  /// 解析期不请求，避免批量解析慢；找不到 durl 时返回 null（调用方退回 DASH 无声流）
  Future<String?> resolveVideoDurl(String bvid, int cid, int qn) async {
    try {
      final p = {
        'bvid': bvid,
        'cid': cid.toString(),
        'fnver': '0',
        'fnval': '1',
        'fourk': '1',
        'qn': qn.toString(),
      };
      final d = await _playUrl(p);
      if (d == null) return null;
      final durls = (d['data']['durl'] as List?) ?? [];
      if (durls.isEmpty) return null;
      final u = (durls.first['url'] as String? ?? '').replaceAll('http:', 'https:');
      return u.isEmpty ? null : u;
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchStreams(BilibiliVideoInfo info) async {
    if (info.cid == 0) return;
    try {
      // 解析期只发 1 次 DASH 请求：同时拿视频分辨率列表 + 最佳音频流（m4a）。
      // durl（带音轨 MP4）不在解析时逐清晰度请求——批量解析必须快；
      // 真正下载视频时才按选中清晰度调用 resolveVideoDurl 换取带音轨 URL。
      final base = {
        'bvid': info.bvid,
        'cid': info.cid.toString(),
        'fnver': '0',
        'fnval': '1',
        'fourk': '1',
      };
      final pDash = Map<String, String>.from(base)..['fnval'] = '4048';
      final dDash = await _playUrl(pDash);
      if (dDash == null) return;
      final dash = dDash['data']['dash'];
      if (dash == null) return;

      // 视频分辨率列表（DASH 无声流，解析期仅用于展示；下载时换 durl 带音轨）
      final videos = (dash['video'] as List?) ?? [];
      info.videoStreams = videos.map((v) => VideoStream(
        id: (v['id'] as int?) ?? 0,
        bandwidth: (v['bandwidth'] as int?) ?? 0,
        width: (v['width'] as int?) ?? 0,
        height: (v['height'] as int?) ?? 0,
        codecs: (v['codecs'] as String?) ?? '',
        baseUrl: ((v['baseUrl'] ?? v['base_url']) as String?)?.replaceAll('http:', 'https:'),
        size: (v['size'] as int?) ?? 0,
      )).toList()
        ..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));

      // 最佳音频流（DASH m4a）
      Map<String, dynamic>? best;
      final audios = (dash['audio'] as List?) ?? [];
      if (audios.isNotEmpty) {
        audios.sort((a, b) =>
            ((b['bandwidth'] as int?) ?? 0).compareTo((a['bandwidth'] as int?) ?? 0));
        final b = audios.first as Map<String, dynamic>;
        best = b;
        final bestUrl = (b['baseUrl'] ?? b['base_url']) as String?;
        info.audioUrl = bestUrl?.replaceAll('http:', 'https:');
        info.audioSize = (b['size'] as int?) ?? 0;
      // 探测音视频真实体积（Range bytes=0-0 读 Content-Range）
      final probeHeaders = {
        'User-Agent': _ua,
        'Referer': 'https://www.bilibili.com/',
        'Range': 'bytes=0-0',
        if (cookie != null && cookie!.isNotEmpty) 'Cookie': cookie!,
      };
      Future<void> probe(String? url, void Function(int) setSize) async {
        if (url == null || url.isEmpty) return;
        try {
          final req = http.Request('GET', Uri.parse(url));
          req.headers.addAll(probeHeaders);
          final r = await req.send().timeout(const Duration(seconds: 5));
          final cr = r.headers['content-range'];
          if (cr != null && cr.contains('/')) {
            final len = int.tryParse(cr.split('/').last);
            if (len != null && len > 0) setSize(len);
          }
          r.stream.drain<void>();
        } catch (_) {}
      }
      final probes = <Future<void>>[
        probe(info.audioUrl, (v) => info.audioSize = v),
        ...info.videoStreams.map((vs) => probe(vs.baseUrl, (v) => vs.size = v)),
      ];
      await Future.wait(probes);
      // 探测失败：用码率×时长估算
      if (info.audioSize <= 0 && info.durationSeconds > 0) {
        final bw = best?['bandwidth'] as int? ?? 0;
        if (bw > 0) info.audioSize = (bw ~/ 8) * info.durationSeconds;
      }
      for (final vs in info.videoStreams) {
        if (vs.size <= 0 && info.durationSeconds > 0 && vs.bandwidth > 0) {
          vs.size = (vs.bandwidth ~/ 8) * info.durationSeconds;
        }
      }
      }
    } catch (_) {}
  }

  /// 解析收藏夹/合集链接，返回视频列表
  Future<List<BilibiliVideoInfo>?> getCollectionVideos(String url) async {
    try {
      // b23.tv 短链：先解析出真实 URL（可能是合集链接）
      if (url.contains('b23.tv')) {
        url = await resolveShortUrl(url);
      }
      // 提取 ml 合集ID / favlist fid / lists合集 season_id
      final mlMatch = RegExp(r'ml(\d+)').firstMatch(url);
      final fidMatch = RegExp(r'[?&]fid=(\d+)').firstMatch(url);
      final uidMatch = RegExp(r'space\.bilibili\.com/(\d+)').firstMatch(url);
      final seriesMatch = RegExp(r'lists/(\d+)').firstMatch(url);

      List<dynamic> videoList = [];

      if (seriesMatch != null && uidMatch != null) {
        // 合集(space): https://space.bilibili.com/{uid}/lists/{season_id}
        final seasonId = seriesMatch.group(1)!;
        final uid = uidMatch.group(1)!;
        var pn = 1;
        while (true) {
          final uri = Uri.parse('https://api.bilibili.com/x/polymer/web-space/seasons_archives_list')
              .replace(queryParameters: {'mid': uid, 'season_id': seasonId, 'page_num': pn.toString(), 'page_size': '30'});
          final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
          if (r.statusCode != 200) break;
          final d = jsonDecode(r.body);
          if (d['code'] != 0) break;
          final arcs = d['data']?['archives'] as List?;
          if (arcs == null || arcs.isEmpty) break;
          videoList.addAll(arcs);
          final isEnd = d['data']?['is_end'] as bool? ?? true;
          if (isEnd == true) break;
          pn++;
        }
      } else if (mlMatch != null) {
        // 合集: https://api.bilibili.com/x/v1/medialist/info?type=1&biz_id=xxx
        final mlId = int.parse(mlMatch.group(1)!);
        final p = await _signed({'type': '1', 'biz_id': mlId.toString()});
        final uri = Uri.parse('https://api.bilibili.com/x/v1/medialist/info')
            .replace(queryParameters: p);
        final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          if (d['code'] == 0) {
            videoList = d['data']['medias'] ?? [];
          }
        }
      } else if (fidMatch != null && uidMatch != null) {
        // 收藏夹: https://api.bilibili.com/x/v3/fav/resource/list?media_id=xxx&ps=20
        final fid = fidMatch.group(1)!;
        var pn = 1;
        var fails = 0;
        while (true) {
          try {
            final uri = Uri.parse('https://api.bilibili.com/x/v3/fav/resource/list')
                .replace(queryParameters: {'media_id': fid, 'ps': '20', 'pn': pn.toString()});
            final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
            if (r.statusCode != 200) { if (++fails >= 3) break; continue; }
            final d = jsonDecode(r.body);
            if (d['code'] != 0) { if (++fails >= 3) break; continue; }
            final medias = d['data']['medias'] as List?;
            if (medias != null && medias.isNotEmpty) videoList.addAll(medias);
            fails = 0;
            if (!(d['data']['has_more'] as bool? ?? false)) break;
            pn++;
          } catch (_) {
            if (++fails >= 3) break;
          }
        }
      }

      if (videoList.isEmpty) return null;

      return videoList
          .where((v) => (v['bvid'] as String? ?? '').isNotEmpty) // 过滤空 bvid（失效视频）
          .map((v) {
        final bvid = v['bvid'] as String? ?? '';
        final baseUrl = 'https://www.bilibili.com/video/$bvid';
        return BilibiliVideoInfo(
          bvid: bvid,
          title: v['title'] as String? ?? '',
          author: v['upper']?['name'] as String? ?? v['owner']?['name'] as String? ?? '',
          coverUrl: (v['cover'] as String? ?? '').replaceAll('http:', 'https:'),
          durationSeconds: v['duration'] as int? ?? 0,
          url: baseUrl,
          // 收藏夹 API 的 cid 在 ugc.first_cid 里（v['cid'] 不存在）
          cid: (v['ugc'] as Map?)?['first_cid'] as int? ?? 0,
        );
      }).toList();
    } catch (_) {
      return null;
    }
}

  /// 快速探测音频大小（收藏夹/合集条目已有 cid，省去 view API）
  Future<int> probeAudioSizeQuick(String bvid, int cid) async {
    void log(String msg) {
      try {
        File('${Directory.systemTemp.path}/gomusic_debug.log')
            .writeAsStringSync('[${DateTime.now().toIso8601String().substring(11, 19)}] [probe] $msg\n', mode: FileMode.append);
      } catch (_) {}
    }
    try {
      // durl 模式：一次请求直接返回 size（带音轨的视频文件大小，即歌曲总体积）
      final d = await _playUrl({'bvid': bvid, 'cid': '$cid', 'qn': '64'});
      final durls = (d?['data']?['durl'] as List?) ?? [];
      log('$bvid cid=$cid code=${d?['code']} durls=${durls.length}');
      if (durls.isNotEmpty) {
        final size = (durls.first['size'] as int?) ?? 0;
        if (size > 0) return size;
      }
    } catch (_) {}
    return 0;
  }
}

/// 下载工具：带进度的流式下载
class StreamDownloader {
  static Future<bool> download({
    required String url,
    required String savePath,
    required void Function(double progress) onProgress,
    void Function(int received, int total)? onSize, // 可选：上报已下载/总字节
    ValueNotifier<bool>? cancel,
    int? expectedSize,
  }) async {
    try {
      // 缓存区：下载到独立临时目录，完成后才移动到目标目录并命名
      final saveFile = File(savePath);
      final tmpDir = Directory('${saveFile.parent.path}${Platform.pathSeparator}.tmp');
      tmpDir.createSync(recursive: true);
      final partFile = File('${tmpDir.path}${Platform.pathSeparator}${saveFile.uri.pathSegments.last}.part');
      var existing = partFile.existsSync() ? partFile.lengthSync() : 0;

      var attempt = 0;
      while (attempt < 2) {
        attempt++;
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
        try {
          final uri = Uri.parse(url);
          final request = await client.getUrl(uri);
          request.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
          request.headers.set('Referer', 'https://www.bilibili.com/');
          if (existing > 0) request.headers.set('Range', 'bytes=$existing-');
          if (BilibiliApi.cookie != null && BilibiliApi.cookie!.isNotEmpty) {
            request.headers.set('Cookie', BilibiliApi.cookie!);
          }
          // cancel 触发瞬间立即断开连接（不等下一个数据块）
          void onCancel() {
            if (cancel?.value == true) client.close(force: true);
          }
          cancel?.addListener(onCancel);
          final streamed = await request.close().timeout(const Duration(seconds: 30));
          if (cancel?.value == true) {
            try { if (partFile.existsSync()) partFile.deleteSync(); } catch (_) {}
            return false;
          }
          try {
            File('${saveFile.parent.path}/debug.log').writeAsStringSync('[${DateTime.now().toIso8601String().substring(11, 19)}] dl status=${streamed.statusCode} len=${streamed.contentLength} range=$existing part=${partFile.path}\n', mode: FileMode.append);
          } catch (_) {}
          if (streamed.statusCode == 416) {
            // Range 越界：缓存损坏，删除后从头重下
            cancel?.removeListener(onCancel);
            if (partFile.existsSync()) partFile.deleteSync();
            existing = 0;
            continue;
          }
          // 206=续传成功；200=服务器不支持 Range 或需重头下
          final append = (streamed.statusCode == 206) && existing > 0;
          if (streamed.statusCode != 200 && streamed.statusCode != 206) {
            cancel?.removeListener(onCancel);
            return false;
          }
          final total = (streamed.contentLength ?? expectedSize ?? 0) + (append ? existing : 0);
          var received = append ? existing : 0;

          final sink = partFile.openWrite(mode: append ? FileMode.append : FileMode.write);
          var lastLog = DateTime.now();
          try {
            await for (final chunk in streamed) {
              if (cancel?.value == true) {
                await sink.close();
                try { if (partFile.existsSync()) partFile.deleteSync(); } catch (_) {}
                return false;
              }
              sink.add(chunk);
              received += chunk.length;
              onSize?.call(received, total);
              if (total > 0) {
                onProgress(received / total);
              } else {
                onProgress(received > 0 ? 0.5 : 0.0);
              }
              // 进度日志（每2秒一条，用于排查进度为0）
              final now = DateTime.now();
              if (now.difference(lastLog).inSeconds >= 2) {
                lastLog = now;
                try {
                  File('${saveFile.parent.path}/debug.log').writeAsStringSync('[${now.toIso8601String().substring(11, 19)}] prog recv=$received total=$total cl=${streamed.contentLength} exp=$expectedSize\n', mode: FileMode.append);
                } catch (_) {}
              }
            }
          } finally {
            cancel?.removeListener(onCancel);
          }
          await sink.close();
          if (cancel?.value == true) {
            try { if (partFile.existsSync()) partFile.deleteSync(); } catch (_) {}
            return false;
          }
          if (total > 0 && received < total) {
            // 连接中断但文件不完整：重试续传
            existing = received;
            continue;
          }
          // 下载完成：移动到正式目录并命名
          onProgress(1.0);
          if (saveFile.existsSync()) saveFile.deleteSync();
          await saveFile.parent.create(recursive: true);
          await partFile.rename(savePath);
          return true;
        } finally {
          client.close(force: true);
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
