import 'package:flutter/material.dart';

import 'skin.dart';

/// 统一主题组件：页面不再各自复制按钮、卡片和输入框样式。
class ThemeComponents {
  const ThemeComponents._();

  static ShapeBorder buttonShape(BuildContext context) {
    final shape = Theme.of(context).filledButtonTheme.style?.shape?.resolve({}) ??
        const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)));
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
        : FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: child);
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
