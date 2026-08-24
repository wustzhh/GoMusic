import 'package:flutter/material.dart';

import 'skin.dart';

/// 统一主题组件：页面不再各自复制按钮、卡片和输入框样式。
class ThemeComponents {
  const ThemeComponents._();

  static ShapeBorder shapeFor(SkinStyle skin) {
    switch (skin.ui.buttonShape) {
      case SkinButtonShape.capsule:
        return const StadiumBorder();
      case SkinButtonShape.cutCorner:
        return const BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(3)),
        );
      case SkinButtonShape.hexagon:
        return const BeveledRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        );
      case SkinButtonShape.pixel:
        return const BeveledRectangleBorder();
      case SkinButtonShape.rounded:
        return RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin.ui.radius),
        );
    }
  }

  static bool hasBackdrop(SkinStyle skin) =>
      skin.textureAsset != null || skin.orbs.isNotEmpty;

  static BoxDecoration panelDecoration(BuildContext context) {
    final skin = skinNotifier.value;
    final scheme = Theme.of(context).colorScheme;
    final borderColor = skin.ui.neonGlow
        ? skin.accent.withValues(alpha: 0.82)
        : skin.accent.withValues(alpha: skin.ui.glassy ? 0.35 : 0.22);
    return BoxDecoration(
      color: skin.ui.glassy
          ? scheme.surface.withValues(alpha: 0.52)
          : scheme.surface.withValues(alpha: 0.86),
      borderRadius: BorderRadius.circular(skin.ui.radius),
      border: Border.all(color: borderColor, width: skin.ui.neonGlow ? 1.4 : 1),
      boxShadow: skin.ui.buttonShadow == Colors.transparent
          ? null
          : [
              BoxShadow(
                color: skin.ui.buttonShadow.withValues(alpha: 0.24),
                blurRadius: skin.ui.neonGlow ? 16 : 8,
              ),
            ],
    );
  }

  static Widget panel(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry margin = EdgeInsets.zero,
  }) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: panelDecoration(context),
      child: child,
    );
  }

  static ShapeBorder buttonShape(BuildContext context) {
    final shape =
        Theme.of(context).filledButtonTheme.style?.shape?.resolve({}) ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        );
    return shape;
  }

  static Widget filledButton(
    BuildContext context, {
    required Widget child,
    required VoidCallback? onPressed,
    IconData? icon,
  }) {
    final theme = Theme.of(context);
    final button = icon == null
        ? FilledButton(onPressed: onPressed, child: child)
        : FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: child,
          );
    // 触发主题读取，确保组件在 ValueListenableBuilder 重建后使用最新皮肤。
    assert(theme.colorScheme.primary != Colors.transparent);
    return AnimatedScale(
      scale: onPressed == null ? 1 : 1,
      duration: const Duration(milliseconds: 120),
      child: button,
    );
  }

  static Widget card(
    BuildContext context, {
    required Widget child,
    EdgeInsetsGeometry? padding,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: padding == null ? child : Padding(padding: padding, child: child),
    );
  }

  static InputDecoration inputDecoration(
    BuildContext context, {
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Theme.of(context).inputDecorationTheme.fillColor,
    );
  }
}

/// 页面内容层的主题场景：把每套主题已有的纹理资源和专属线条/光带放到页面上，
/// 不再只依赖最底层低透明度背景，因此播放页、歌单页和下载页都能看见主题差异。
class ThemeBackdrop extends StatelessWidget {
  const ThemeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SkinStyle>(
      valueListenable: skinNotifier,
      builder: (context, skin, _) => IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: skin.background.withValues(alpha: 0.70)),
            if (skin.textureAsset != null)
              Opacity(
                opacity: skin.ui.neonGlow ? 0.34 : 0.28,
                child: Image.asset(
                  skin.textureAsset!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            CustomPaint(painter: _ThemeAtmospherePainter(skin)),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    skin.background.withValues(alpha: 0.28),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeAtmospherePainter extends CustomPainter {
  final SkinStyle skin;
  const _ThemeAtmospherePainter(this.skin);

  @override
  void paint(Canvas canvas, Size size) {
    final accent = skin.accent;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = skin.ui.neonGlow ? 1.4 : 1;
    switch (skin.id) {
      case 'cyber_neon':
        paint.color = accent.withValues(alpha: 0.22);
        for (var i = -4; i < 12; i++) {
          final x = size.width * i / 8;
          canvas.drawLine(
            Offset(x, size.height),
            Offset(size.width / 2, size.height * 0.46),
            paint,
          );
        }
        for (var i = 1; i < 8; i++) {
          final y = size.height * (0.46 + i * i * 0.009);
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
        break;
      case 'electric':
        paint.color = accent.withValues(alpha: 0.28);
        for (var i = 0; i < 5; i++) {
          final path = Path()..moveTo(size.width * (0.08 + i * 0.21), 0);
          path.lineTo(size.width * (0.18 + i * 0.18), size.height * 0.25);
          path.lineTo(size.width * (0.10 + i * 0.20), size.height * 0.54);
          path.lineTo(size.width * (0.22 + i * 0.16), size.height);
          canvas.drawPath(path, paint);
        }
        break;
      case 'rainbow':
      case 'aurora':
        paint.color = accent.withValues(alpha: 0.20);
        for (var i = 0; i < 4; i++) {
          final rect = Rect.fromCenter(
            center: Offset(size.width * 0.5, size.height * (0.35 + i * 0.14)),
            width: size.width * (0.8 + i * 0.08),
            height: size.height * 0.24,
          );
          canvas.drawArc(rect, 3.2, 2.4, false, paint);
        }
        break;
      case 'galaxy':
        paint.color = accent.withValues(alpha: 0.24);
        final center = Offset(size.width * 0.5, size.height * 0.38);
        for (var i = 0; i < 4; i++) {
          canvas.drawOval(
            Rect.fromCenter(
              center: center,
              width: size.width * (0.35 + i * 0.16),
              height: size.height * (0.12 + i * 0.05),
            ),
            paint,
          );
        }
        break;
      case 'flame':
        paint.color = accent.withValues(alpha: 0.18);
        for (var i = 0; i < 7; i++) {
          final path = Path()..moveTo(size.width * i / 7, size.height);
          path.cubicTo(
            size.width * (i + 0.2) / 7,
            size.height * 0.68,
            size.width * (i - 0.1) / 7,
            size.height * 0.38,
            size.width * (i + 0.45) / 7,
            size.height * 0.12,
          );
          canvas.drawPath(path, paint);
        }
        break;
      default:
        paint.color = accent.withValues(alpha: 0.10);
        canvas.drawLine(
          Offset(0, size.height * 0.18),
          Offset(size.width, size.height * 0.08),
          paint,
        );
        canvas.drawLine(
          Offset(0, size.height * 0.82),
          Offset(size.width, size.height * 0.92),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _ThemeAtmospherePainter oldDelegate) =>
      oldDelegate.skin.id != skin.id;
}
