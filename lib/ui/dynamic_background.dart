import 'dart:math';

import 'package:flutter/material.dart';

import '../main.dart';
import 'skin.dart';

/// 全局动态背景：全 app 唯一实例（注入 MaterialApp.builder），
/// 位于页面层之下，随皮肤切换实时变化。
/// 纯 Canvas 绘制（无 blur/BackdropFilter），光晕 ≤6 团、粒子 ≤60 颗，保证 60fps。
class DynamicBackground extends StatelessWidget {
  const DynamicBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SkinStyle>(
      valueListenable: skinNotifier,
      builder: (context, skin, _) {
        // 素皮肤：纯色无动画，不需要 controller
        if (!skin.animated) {
          return ColoredBox(color: skin.background);
        }
        return _AnimatedSkinBackground(skin: skin);
      },
    );
  }
}

class _AnimatedSkinBackground extends StatefulWidget {
  final SkinStyle skin;
  const _AnimatedSkinBackground({required this.skin});
  @override
  State<_AnimatedSkinBackground> createState() => _AnimatedSkinBackgroundState();
}

class _AnimatedSkinBackgroundState extends State<_AnimatedSkinBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return RepaintBoundary(
          child: CustomPaint(
            painter: SkinBackgroundPainter(
              skin: widget.skin,
              tSeconds: _controller.value * 120,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

/// 皮肤缩略图/预览：动态皮肤用共享 Animation 驱动实时动画（画廊里每张都流动），
/// 素皮肤显示纯色。
class SkinPreview extends StatelessWidget {
  final SkinStyle skin;
  final Animation<double>? animation; // 可选：共享动画驱动（设置页画廊）
  const SkinPreview({super.key, required this.skin, this.animation});

  @override
  Widget build(BuildContext context) {
    if (!skin.animated || animation == null) {
      return ColoredBox(color: skin.background);
    }
    final anim = animation!;
    return AnimatedBuilder(
      animation: anim,
      builder: (context, _) {
        return CustomPaint(
          painter: SkinBackgroundPainter(skin: skin, tSeconds: anim.value * 120),
          size: Size.infinite,
        );
      },
    );
  }
}

// ==================== 粒子数据 ====================

/// 粒子生成用随机种子（每套皮肤固定，粒子布局稳定）
class _Rand {
  final Random _r;
  _Rand(int seed) : _r = Random(seed);
  double nextDouble() => _r.nextDouble();
}

class _Star {
  final double x, y, size, speed, phase;
  _Star(_Rand r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        size = 0.6 + r.nextDouble() * 1.4,
        speed = 0.4 + r.nextDouble() * 1.2,
        phase = r.nextDouble() * pi * 2;
}

class _Meteor {
  final double startX, startY, dx, dy, speed, period, phase;
  _Meteor(_Rand r)
      : startX = 0.05 + r.nextDouble() * 0.9,
        startY = 0.02 + r.nextDouble() * 0.4,
        dx = 0.30 + r.nextDouble() * 0.25,
        dy = 0.22 + r.nextDouble() * 0.18,
        speed = 0.25 + r.nextDouble() * 0.2,
        period = 5 + r.nextDouble() * 6,
        phase = r.nextDouble() * pi * 2;
}

class _Ember {
  final double x, size, speed, phase;
  final int colorIdx;
  _Ember(_Rand r)
      : x = r.nextDouble(),
        size = 1.0 + r.nextDouble() * 2.2,
        speed = 0.10 + r.nextDouble() * 0.25,
        phase = r.nextDouble() * pi * 2,
        colorIdx = r.nextDouble() < 0.6 ? 0 : 1;
}

class _Spark {
  final double x, y, size, phase;
  _Spark(_Rand r)
      : x = r.nextDouble(),
        y = r.nextDouble(),
        size = 1.0 + r.nextDouble() * 1.6,
        phase = r.nextDouble() * pi * 2;
}

/// 每套皮肤的粒子集合（按 skin id 静态缓存，painter 每帧重建也不重复生成）
class _ParticleSet {
  final List<_Star> stars;
  final List<_Meteor> meteors;
  final List<_Ember> embers;
  final List<_Spark> sparks;
  _ParticleSet(String id)
      : stars = _gen(id, 55, (r) => _Star(r)),
        meteors = _gen(id, 5, (r) => _Meteor(r)),
        embers = _gen(id, 28, (r) => _Ember(r)),
        sparks = _gen(id, 10, (r) => _Spark(r));

  static List<T> _gen<T>(String id, int n, T Function(_Rand) make) {
    final r = _Rand(id.hashCode.abs());
    return List.generate(n, (_) => make(r));
  }
}

final Map<String, _ParticleSet> _particleCache = {};

_ParticleSet _particlesFor(String skinId) {
  return _particleCache.putIfAbsent(skinId, () => _ParticleSet(skinId));
}

// ==================== 绘制器 ====================

/// 皮肤背景绘制器（公开：可测试）。
/// 每次调用传入当前时间 tSeconds，由调用方（AnimatedBuilder）驱动重绘。
class SkinBackgroundPainter extends CustomPainter {
  final SkinStyle skin;
  final double tSeconds;
  late final _ParticleSet _particles;

  SkinBackgroundPainter({required this.skin, required this.tSeconds}) {
    _particles = _particlesFor(skin.id);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = skin.background);
    final t = tSeconds;
    final short = size.shortestSide;

    // 1. 漂移光晕（径向渐变，GPU 合成，无 blur）
    for (final orb in skin.orbs) {
      final rawPx = orb.cx * size.width +
          sin(t / orb.period * pi * 2 + orb.phase) * orb.ampX * short;
      final rawPy = orb.cy * size.height +
          cos(t / orb.period * pi * 2 + orb.phase) * orb.ampY * short;
      // 防御：shader 中心必须保持在画布内（部分渲染路径不绘制画布外的中心）
      final px = rawPx.clamp(size.width * 0.05, size.width * 0.95);
      final py = rawPy.clamp(size.height * 0.05, size.height * 0.95);
      final r = orb.radius * short;
      final center = Offset(px, py);
      // 电光皮肤：整体呼吸脉冲（光晕明暗随周期起伏）
      double alphaMul = 1.0;
      if (skin.id == 'electric') {
        final pulse = (sin(t / 2.5 * pi * 2) + 1) / 2;
        alphaMul = 0.45 + 0.55 * pulse;
      }
      // 外层柔光：1.6 倍大，让光晕在深色背景上更显眼
      final softRect = Rect.fromCircle(center: center, radius: r * 1.6);
      final softAlpha = orb.color.a * 0.55 * alphaMul;
      final softPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            orb.color.withValues(alpha: softAlpha),
            orb.color.withValues(alpha: softAlpha * 0.35),
            orb.color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(softRect);
      canvas.drawRect(softRect, softPaint);
      // 核心光晕
      final rect = Rect.fromCircle(center: center, radius: r);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            orb.color.withValues(alpha: orb.color.a * alphaMul),
            orb.color.withValues(alpha: orb.color.a * 0.45 * alphaMul),
            orb.color.withValues(alpha: 0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }

    // 2. 科技元素（按皮肤专属效果）
    switch (skin.id) {
      case 'cyber_neon':
        _paintCyberGrid(canvas, size, t);
        _paintScanline(canvas, size, t);
      case 'electric':
        _paintCircuit(canvas, size, t);
        _paintScanline(canvas, size, t);
      case 'aurora':
      case 'rainbow':
        _paintRibbons(canvas, size, t);
      case 'galaxy':
        _paintSpiral(canvas, size, t);
    }

    // 3. 粒子特效
    switch (skin.particles) {
      case SkinParticle.star:
        _paintStars(canvas, size, t);
      case SkinParticle.meteor:
        _paintStars(canvas, size, t);
        _paintMeteors(canvas, size, t);
      case SkinParticle.ember:
        _paintEmbers(canvas, size, t);
      case SkinParticle.spark:
        _paintSparks(canvas, size, t);
      case SkinParticle.none:
        break;
    }
  }

  /// 赛博朋克透视网格：地平线发光 + 放射线 + 滚动水平线（前进感）
  void _paintCyberGrid(Canvas canvas, Size size, double t) {
    final w = size.width, h = size.height;
    final horizon = h * 0.40;
    final vp = Offset(w / 2, horizon);
    final lineColor = skin.accent.withValues(alpha: 0.20);
    final glowColor = skin.accent.withValues(alpha: 0.65);
    // 滚动水平线：近地平线密（平方分布），周期循环产生前进感
    final scroll = (t * 0.18) % 1.0;
    for (var i = 0; i < 12; i++) {
      final p = (i + scroll) / 12;
      final y = horizon + (h - horizon) * p * p;
      canvas.drawLine(Offset(0, y), Offset(w, y),
          Paint()..color = lineColor..strokeWidth = 1);
    }
    // 放射线（通向消失点）
    for (var i = 0; i <= 16; i++) {
      final x = w * i / 16;
      canvas.drawLine(vp, Offset(x, h),
          Paint()..color = lineColor..strokeWidth = 1);
    }
    // 地平线：亮线 + 光晕
    canvas.drawLine(Offset(0, horizon), Offset(w, horizon),
        Paint()..color = glowColor..strokeWidth = 2);
    final haloRect = Rect.fromCenter(
        center: Offset(w / 2, horizon), width: w * 0.9, height: h * 0.14);
    canvas.drawRect(
        haloRect,
        Paint()
          ..shader = RadialGradient(colors: [
            skin.accent.withValues(alpha: 0.30),
            skin.accent.withValues(alpha: 0),
          ]).createShader(haloRect));
  }

  /// 扫描线：亮带从上到下循环扫描（科技感）
  void _paintScanline(Canvas canvas, Size size, double t) {
    final cycle = (t * 0.16) % 1.0;
    final y = cycle * size.height;
    final rect = Rect.fromLTWH(0, y - 34, size.width, 68);
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              skin.accent.withValues(alpha: 0),
              skin.accent.withValues(alpha: 0.22),
              skin.accent.withValues(alpha: 0),
            ],
          ).createShader(rect));
  }

  /// 电路纹路：曼哈顿风格折线 + 呼吸节点（电光皮肤）
  void _paintCircuit(Canvas canvas, Size size, double t) {
    final r = _Rand(skin.id.hashCode);
    final breath = (sin(t * 1.1) + 1) / 2;
    final lineAlpha = 0.12 + 0.22 * breath;
    for (var i = 0; i < 7; i++) {
      var x = r.nextDouble() * size.width * 0.25;
      var y = r.nextDouble() * size.height;
      final path = Path()..moveTo(x, y);
      final segs = 5 + (r.nextDouble() * 4).toInt();
      for (var s = 0; s < segs; s++) {
        if (s.isEven) {
          x += size.width * (0.08 + r.nextDouble() * 0.18);
        } else {
          y = r.nextDouble() * size.height;
        }
        path.lineTo(x, y);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = skin.accent.withValues(alpha: lineAlpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
      canvas.drawCircle(
          Offset(x, y),
          2.4,
          Paint()
            ..color = skin.accent.withValues(alpha: 0.25 + 0.5 * breath));
    }
  }

  /// 流光丝带：多层正弦波动光带（极光/幻彩彩虹）
  void _paintRibbons(Canvas canvas, Size size, double t) {
    final colors = skin.id == 'rainbow'
        ? const [
            Color(0xFFFF5252), Color(0xFFFFA726), Color(0xFFFFEE58),
            Color(0xFF66BB6A), Color(0xFF29B6F6), Color(0xFFAB47BC),
          ]
        : [skin.accent, const Color(0xFF00E5A0), const Color(0xFFB388FF)];
    for (var i = 0; i < colors.length; i++) {
      final baseY = size.height * (0.22 + 0.50 * i / colors.length);
      final path = Path();
      const steps = 64;
      for (var s = 0; s <= steps; s++) {
        final x = size.width * s / steps;
        final y = baseY +
            sin(x / size.width * pi * 2.2 + t * 0.45 + i * 1.7) *
                size.height * 0.055 +
            sin(x / size.width * pi * 5.0 + t * 0.28 + i) * size.height * 0.018;
        if (s == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = colors[i].withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9.0 + i * 1.6
            ..strokeCap = StrokeCap.round);
    }
  }

  /// 星云旋涡：旋转的螺旋光带（星河皮肤）
  void _paintSpiral(Canvas canvas, Size size, double t) {
    final cx = size.width * 0.5, cy = size.height * 0.44;
    final maxR = size.shortestSide * 0.60;
    final rot = t * 0.12;
    final path = Path();
    const steps = 220;
    const turns = 3.4;
    for (var s = 0; s <= steps; s++) {
      final p = s / steps;
      final angle = rot + p * turns * pi * 2;
      final rr = maxR * p;
      final x = cx + cos(angle) * rr * 1.35;
      final y = cy + sin(angle) * rr;
      if (s == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF8C9EFF).withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20
          ..strokeCap = StrokeCap.round);
    canvas.drawPath(
        path,
        Paint()
          ..color = skin.accent.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round);
  }

  void _paintStars(Canvas canvas, Size size, double t) {
    final paint = Paint()..color = Colors.white;
    for (final s in _particles.stars) {
      final tw = (sin(t * s.speed + s.phase) + 1) / 2; // 0~1
      paint.color = Colors.white.withValues(alpha: 0.15 + 0.55 * tw);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size * tw.clamp(0.2, 1.0),
        paint,
      );
    }
  }

  void _paintMeteors(Canvas canvas, Size size, double t) {
    for (final m in _particles.meteors) {
      final cycle = t * m.speed + m.phase;
      final local = cycle % m.period;
      if (local > 2.0) continue; // 只在窗口期内出现
      final p = local / 2.0; // 0→1
      final sx = m.startX * size.width + p * m.dx * size.width;
      final sy = m.startY * size.height + p * m.dy * size.height;
      final fade = sin(p * pi); // 中段最亮
      final tail = Offset(sx - m.dx * size.width * 0.16, sy - m.dy * size.height * 0.16);
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.85 * fade),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromPoints(tail, Offset(sx, sy)));
      paint.strokeWidth = 2;
      paint.strokeCap = StrokeCap.round;
      canvas.drawLine(tail, Offset(sx, sy), paint);
    }
  }

  void _paintEmbers(Canvas canvas, Size size, double t) {
    for (final e in _particles.embers) {
      final cycle = (t * e.speed + e.phase) % 1.0;
      final y = 1.0 - cycle * 0.85; // 从底部上升到 15% 高度
      final fade = sin(cycle * pi);
      final color = e.colorIdx == 0
          ? const Color(0xFFFFA040)
          : const Color(0xFFFF5A30);
      final paint = Paint()..color = color.withValues(alpha: 0.5 * fade);
      canvas.drawCircle(
        Offset(e.x * size.width, y * size.height),
        e.size,
        paint,
      );
    }
  }

  void _paintSparks(Canvas canvas, Size size, double t) {
    // 随机小光点高频闪烁（电光感）
    for (final s in _particles.sparks) {
      final flash = pow(max(0.0, sin(t * 3.0 + s.phase)), 12).toDouble();
      if (flash <= 0.02) continue;
      final paint = Paint()
        ..color = skin.accent.withValues(alpha: 0.75 * flash);
      canvas.drawCircle(
        Offset(s.x * size.width, s.y * size.height),
        s.size + 1.5 * flash,
        paint,
      );
    }
    // 周期性"闪电"折线：每 7 秒一闪，极短窗口
    final flashT = t % 7.0;
    if (flashT < 0.30) {
      final k = flashT / 0.30; // 0→1
      final alpha = sin(k * pi) * 0.55;
      final r = _Rand(skin.id.hashCode);
      final stroke = Paint()
        ..color = skin.accent.withValues(alpha: alpha)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      double x = (0.25 + r.nextDouble() * 0.5) * size.width;
      double y = 0.05 * size.height;
      final path = Path()..moveTo(x, y);
      while (y < size.height * 0.7) {
        x += (r.nextDouble() - 0.5) * 0.18 * size.width;
        y += 0.08 * size.height * (1 + r.nextDouble());
        path.lineTo(x, y);
      }
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant SkinBackgroundPainter oldDelegate) {
    return oldDelegate.skin.id != skin.id ||
        oldDelegate.tSeconds != tSeconds;
  }
}
