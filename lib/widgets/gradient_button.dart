import 'package:flutter/material.dart';

/// 渐变主操作按钮：颜色随当前皮肤的主题渐变（解析/下载/确定等关键按钮）
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final List<Color> colors;
  final double radius;
  final double height;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    required this.colors,
    this.radius = 12,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.45 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onPressed,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
