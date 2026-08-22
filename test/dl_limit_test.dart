import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/bilibili_api.dart';

/// 验证 playurl 全局限速 + 失败重试：连续解析 12 个不同视频，
/// 应全部成功（限速后不再触发风控失败），且请求间隔 ≥ 1.5s（2s 限速生效）。
/// 注意：真实下载链路是 getVideoInfo(拿cid) → resolveVideoDurl(bvid, cid)，
/// 测试必须先用真实 cid，cid=0 会导致 playurl 返回 -404。
void main() {
  test('playurl 批量解析限速+重试实测(12个BV全成功)', () async {
    final api = BilibiliApi();
    // 取 downloads/debug.log 里真实下载过的视频（不同 UP 主）
    const bvs = [
      'BV1EP9qY5EcX', 'BV1hs411W7uR', 'BV1Ubjc6FEfr', 'BV1JA411o7Yh',
      'BV1eVfmY1E7e', 'BV1WL4y1p73A', 'BV1SLBmYQEdW', 'BV17K4y1w7NQ',
      'BV1xo3UzZERm', 'BV1Kr421t7LG', 'BV1ox411w753', 'BV1uM411G7hM',
    ];
    final fails = <String>[];
    var lastTs = 0;
    var minGap = 999999;
    var totalMs = 0;
    for (final bv in bvs) {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      // 与真实下载链路一致：getVideoInfo 拿真实 cid → resolveVideoDurl
      final info = await api.getVideoInfo(bv);
      String? durl;
      if (info != null && info.cid > 0) {
        durl = await api.resolveVideoDurl(bv, info.cid, 80);
      }
      final dt = DateTime.now().millisecondsSinceEpoch - t0;
      totalMs += dt;
      final gap = t0 - lastTs;
      if (lastTs > 0 && gap < minGap) minGap = gap;
      lastTs = t0;
      if (durl == null) fails.add('$bv (${dt}ms)');
    }
    // ignore: avoid_print
    print('成功=${bvs.length - fails.length}/${bvs.length} 失败=${fails.length} '
        'minGap=${minGap}ms 总耗时=${totalMs}ms');
    if (fails.isNotEmpty) {
      // ignore: avoid_print
      print('失败项: ${fails.join(', ')}');
    }
    // 全部成功（限速+重试后不再被风控打死）
    expect(fails, isEmpty, reason: '批量解析不应有失败');
    // 限速生效：相邻请求最小间隔应接近 2s（允许网络抖动，>1.5s 即视为生效）
    expect(minGap, greaterThanOrEqualTo(1500),
        reason: '连续请求间隔应 ≥ 1.5s（2s 限速生效），实际最小 $minGap ms');
  }, timeout: const Timeout(Duration(minutes: 5)));
}