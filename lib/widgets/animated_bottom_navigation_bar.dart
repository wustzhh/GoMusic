import 'package:flutter/material.dart';

import '../ui/skin.dart';

/// 主题无关的底部栏动画入口：背景、指示器形状可变，但选中位置始终以同一套
/// AnimatedPositioned + AnimatedScale 驱动，避免 BottomNavigationBar 的 type 分支导致
/// 某些皮肤有 shifting 动效、某些皮肤完全没有动效。
class AnimatedBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<BottomNavigationBarItem> items;

  const AnimatedBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skin = skinNotifier.value;
    final nav = theme.bottomNavigationBarTheme;
    final selected = nav.selectedItemColor ?? theme.colorScheme.primary;
    final unselected =
        nav.unselectedItemColor ?? theme.colorScheme.onSurfaceVariant;
    final indicator = skin.ui.navIndicator;

    return Material(
      color: nav.backgroundColor ?? theme.colorScheme.surface,
      elevation: nav.elevation ?? 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / items.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    key: const ValueKey('bottom-nav-indicator'),
                    duration: const Duration(milliseconds: 280),
                    // 不使用会越过目标位置的 easeOutBack，避免切换时光效短暂跑出当前单元格。
                    curve: Curves.easeOutCubic,
                    left: itemWidth * currentIndex,
                    top: 0,
                    width: itemWidth,
                    height: constraints.maxHeight,
                    child: ClipRect(
                      child: _Indicator(type: indicator, color: selected),
                    ),
                  ),
                  Row(
                    children: [
                      for (var index = 0; index < items.length; index++)
                        Expanded(
                          child: _NavItem(
                            index: index,
                            item: items[index],
                            selected: index == currentIndex,
                            selectedColor: selected,
                            unselectedColor: unselected,
                            onTap: () => onTap(index),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final int index;
  final BottomNavigationBarItem item;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.index,
    required this.item,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        key: ValueKey('bottom-nav-cell-$index'),
        onTap: onTap,
        customBorder: const RoundedRectangleBorder(),
        splashColor: selectedColor.withValues(alpha: 0.24),
        highlightColor: selectedColor.withValues(alpha: 0.12),
        child: SizedBox.expand(
          child: Center(
            child: AnimatedScale(
              scale: selected ? 1.06 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: IconTheme(
                data: IconThemeData(
                  color: selected ? selectedColor : unselectedColor,
                  size: selected ? 28 : 24,
                ),
                child: selected ? item.activeIcon : item.icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Indicator extends StatelessWidget {
  final SkinNavIndicator type;
  final Color color;

  const _Indicator({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case SkinNavIndicator.underline:
        return Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: 3,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        );
      case SkinNavIndicator.bracket:
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color, width: 2),
              right: BorderSide(color: color, width: 2),
            ),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10),
            ],
          ),
        );
      case SkinNavIndicator.diamond:
        return Center(
          child: FractionallySizedBox(
            widthFactor: 0.56,
            heightFactor: 0.56,
            child: Transform.rotate(
              angle: 0.7853981633974483,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  border: Border.all(
                    color: color.withValues(alpha: 0.75),
                    width: 1.2,
                  ),
                  shape: BoxShape.rectangle,
                ),
              ),
            ),
          ),
        );
      case SkinNavIndicator.glow:
        return Center(
          child: FractionallySizedBox(
            widthFactor: 0.72,
            heightFactor: 0.62,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.75)),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        );
      case SkinNavIndicator.pill:
        return Center(
          child: FractionallySizedBox(
            widthFactor: 0.72,
            heightFactor: 0.62,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: color.withValues(alpha: 0.55)),
              ),
            ),
          ),
        );
    }
  }
}
