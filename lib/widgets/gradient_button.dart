import 'dart:async';

import 'package:flutter/material.dart';

import '../ui/skin.dart';

/// 渐变主操作按钮：颜色随当前皮肤的主题渐变（解析/下载/确定等关键按钮）。
/// 自动跟随主题：形状（随 buttonShape）、霓虹描边/辉光（buttonBorder/buttonShadow）、
/// 渐变（colors，默认取皮肤 buttonGradient），并带流光扫过动画。
class GradientButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final List<Color>? colors;
  final double radius;
  final double height;
  final bool animated; // 是否启用流光扫过动画

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.colors,
    this.radius = 12,
    this.height = 44,
    this.animated = true,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  Timer? _restart;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _sheen.repeat();
    }
  }

  @override
  void dispose() {
    _restart?.cancel();
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui = skinNotifier.value.ui;
    final shape = switch (ui.buttonShape) {
      SkinButtonShape.capsule => StadiumBorder(),
      SkinButtonShape.cutCorner => BeveledRectangleBorder(
        borderRadius: BorderRadius.circular(2),
      ),
      SkinButtonShape.hexagon => BeveledRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      SkinButtonShape.pixel => BeveledRectangleBorder(),
      SkinButtonShape.rounded => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    };
    final borderColor = ui.buttonBorder == Colors.transparent
        ? (ui.neonGlow
              ? skinNotifier.value.accent.withValues(alpha: 0.9)
              : Colors.transparent)
        : ui.buttonBorder;
    final glow = ui.buttonShadow == Colors.transparent
        ? (ui.neonGlow ? skinNotifier.value.accent : null)
        : ui.buttonShadow;
    final colors = widget.colors ?? skinNotifier.value.buttonGradient;
    final pressScale = switch (ui.buttonFeedback) {
      SkinButtonFeedback.bounce => _pressed ? 0.92 : 1.0,
      SkinButtonFeedback.lift => _pressed ? 0.97 : 1.0,
      SkinButtonFeedback.scanline => _pressed ? 0.98 : 1.0,
      _ => _pressed ? 0.96 : 1.0,
    };
    final glowBoost = switch (ui.buttonFeedback) {
      SkinButtonFeedback.glowPulse => 1.35,
      SkinButtonFeedback.scanline => 1.15,
      _ => 1.0,
    };

    return Opacity(
      opacity: widget.onPressed == null ? 0.45 : 1.0,
      child: AnimatedScale(
        scale: pressScale,
        duration: ui.buttonFeedback == SkinButtonFeedback.bounce
            ? const Duration(milliseconds: 90)
            : const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: AnimatedBuilder(
          animation: _sheen,
          builder: (context, _) => Material(
            color: Colors.transparent,
            child: Ink(
              height: widget.height,
              decoration: ShapeDecoration(
                shape: shape,
                gradient: LinearGradient(colors: colors),
                shadows: glow == null
                    ? null
                    : [
                        BoxShadow(
                          color: glow.withValues(alpha: 0.55),
                          blurRadius: (_sheen.value * 18 + 4) * glowBoost,
                          spreadRadius: _sheen.value * 3,
                        ),
                      ],
              ),
              child: CustomPaint(
                painter: _SheenPainter(_sheen.value, colors),
                child: InkWell(
                  customBorder: shape,
                  onTap: widget.onPressed,
                  onHighlightChanged: (pressed) {
                    if (mounted) setState(() => _pressed = pressed);
                  },
                  child: Center(child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 划过按钮表面的流光带
class _SheenPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  _SheenPainter(this.t, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    // 一条斜向亮带从左扫到右
    final x = t * (size.width + 160) - 80;
    final rect = Rect.fromLTRB(x, 0, x + 60, size.height);
    final light = colors.first.withValues(alpha: 0.28);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [light.withValues(alpha: 0), light, light.withValues(alpha: 0)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.t != t;
}
