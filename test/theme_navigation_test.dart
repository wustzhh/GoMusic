import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/ui/skin.dart';
import 'package:gomusic/ui/theme_components.dart';
import 'package:gomusic/widgets/animated_bottom_navigation_bar.dart';
import 'package:gomusic/pages/player_page.dart';

void main() {
  test('每套主题都声明独立字体、按钮反馈和导航指示器', () {
    for (final skin in Skins.all) {
      expect(skin.ui.fontFamily, isNotEmpty, reason: '${skin.name} 缺少字体风格');
      expect(
        skin.ui.buttonFeedback,
        isNotNull,
        reason: '${skin.name} 缺少按钮点击反馈',
      );
      expect(skin.ui.navIndicator, isNotNull, reason: '${skin.name} 缺少底部栏选中样式');
    }
    expect(
      Skins.all.map((skin) => skin.ui.fontFamily).toSet().length,
      greaterThan(1),
    );
    expect(
      Skins.all.map((skin) => skin.ui.buttonFeedback).toSet().length,
      greaterThan(1),
    );
  });

  test('主题按钮形状和页面背景装饰确实随主题变化', () {
    final shapes = Skins.all
        .map((skin) => ThemeComponents.shapeFor(skin))
        .toSet();
    expect(shapes.length, greaterThan(2));
    expect(ThemeComponents.hasBackdrop(Skins.cyberNeon), isTrue);
    expect(ThemeComponents.hasBackdrop(Skins.plainLight), isTrue);
  });

  testWidgets('底部栏切换时使用统一动画入口且不显示文字', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AnimatedBottomNavigationBar(
            currentIndex: 0,
            onTap: (_) {},
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AnimatedBottomNavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('bottom-nav-indicator')), findsOneWidget);
    expect(find.text('首页'), findsNothing);
    expect(find.text('设置'), findsNothing);
    final cell = find.byKey(const ValueKey('bottom-nav-cell-0'));
    expect(cell, findsOneWidget);
    expect(tester.getSize(cell).height, 68);
    expect(find.byType(InkWell), findsWidgets);
    final ink = tester.widget<InkWell>(find.byType(InkWell).first);
    expect(ink.customBorder, isA<RoundedRectangleBorder>());
    final indicatorAnimation = tester.widget<AnimatedPositioned>(
      find.byKey(const ValueKey('bottom-nav-indicator')),
    );
    expect(indicatorAnimation.curve, Curves.easeOutCubic);

    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AnimatedBottomNavigationBar(
            currentIndex: 1,
            onTap: (_) {},
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
              BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
            ],
          ),
        ),
      ),
    );
    final indicator = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-indicator')),
    );
    final bar = tester.getRect(find.byType(AnimatedBottomNavigationBar));
    expect(indicator.top, greaterThanOrEqualTo(bar.top));
    expect(indicator.bottom, lessThanOrEqualTo(bar.bottom));
  });

  testWidgets('底部栏特效在有底部安全区时仍锚定完整按钮区', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          padding: EdgeInsets.only(bottom: 20),
        ),
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AnimatedBottomNavigationBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
                BottomNavigationBarItem(icon: Icon(Icons.settings), label: '设置'),
              ],
            ),
          ),
        ),
      ),
    );

    final bar = tester.getRect(find.byType(AnimatedBottomNavigationBar));
    final cell = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-cell-0')),
    );
    final indicator = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-indicator')),
    );
    final selectedCell = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-cell-0')),
    );

    expect(bar.height, 88);
    expect(cell.height, 68);
    expect(cell.top, bar.top);
    expect(indicator, selectedCell);

    await tester.pumpAndSettle(const Duration(seconds: 1));
    final settledIndicator = tester.getRect(
      find.byKey(const ValueKey('bottom-nav-indicator')),
    );
    expect(settledIndicator, selectedCell);
  });

  testWidgets('播放控制按钮在所有主题下保持圆形外轮廓', (tester) async {
    final before = skinNotifier.value;
    skinNotifier.value = Skins.cyberNeon;
    addTearDown(() => skinNotifier.value = before);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlayerControlButton(
            icon: Icons.play_arrow,
            size: 84,
            onPressed: null,
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(
      find.byKey(const ValueKey('player-control-material')),
    );
    expect(material.shape, isA<CircleBorder>());
  });
}
