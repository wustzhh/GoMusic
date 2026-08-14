import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/main.dart';
import 'package:gomusic/pages/settings_page.dart';
import 'package:gomusic/ui/dynamic_background.dart';
import 'package:gomusic/ui/skin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SkinBackgroundPainter：不同时间点输出不同（动画确实在动）', (tester) async {
    Future<Uint8List> render(double t) async {
      final painter = SkinBackgroundPainter(skin: Skins.aurora, tSeconds: t);
      final recorder = ui.PictureRecorder();
      painter.paint(ui.Canvas(recorder), const Size(200, 400));
      final img = await recorder.endRecording().toImage(50, 100);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    }

    // toImage 需要真实异步（raster 线程），必须用 runAsync 避免 FakeAsync 挂起
    Uint8List? f1, f2;
    await tester.runAsync(() async {
      f1 = await render(10.0);
      f2 = await render(15.0);
    });
    var diff = 0;
    for (var i = 0; i < f1!.length; i++) {
      if (f1![i] != f2![i]) diff++;
    }
    expect(diff, greaterThan(0), reason: '光晕漂移应使两个时间点的画面不同');
  });

  testWidgets('全部 6 套动态皮肤在两个时间点输出都不同', (tester) async {
    for (final skin in Skins.all.where((s) => s.animated)) {
      Future<Uint8List> render(double t) async {
        final painter = SkinBackgroundPainter(skin: skin, tSeconds: t);
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), const Size(120, 200));
        final img = await recorder.endRecording().toImage(30, 50);
        final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List();
      }

      Uint8List? f1, f2;
      await tester.runAsync(() async {
        f1 = await render(3.0);
        f2 = await render(9.0);
      });
      var diff = 0;
      for (var i = 0; i < f1!.length; i++) {
        if (f1![i] != f2![i]) diff++;
      }
      expect(diff, greaterThan(0), reason: '${skin.name} 应有动画');
    }
  });

  testWidgets('设置页皮肤区块：显示 3 套预览 + 更多主题入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump(const Duration(milliseconds: 300)); // 等异步加载
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('界面皮肤'), findsOneWidget);
    expect(find.text('更多主题'), findsOneWidget);
    // 区块内显示前 3 套
    expect(find.text('素·浅色'), findsOneWidget);
    expect(find.text('素·深色'), findsOneWidget);
    expect(find.text('极光'), findsOneWidget);
    // 其余 5 套不在设置页
    expect(find.text('赛博霓虹'), findsNothing);
    expect(find.text('烈焰'), findsNothing);
  });

  testWidgets('更多主题弹窗：展示全部 8 套（可竖向滚动）+确定取消，选择后确定生效', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    // 打开弹窗
    await tester.tap(find.text('更多主题'));
    await tester.pump(const Duration(milliseconds: 400)); // 实时动画不会 settle，用固定时长
    await tester.pump(const Duration(milliseconds: 100));

    // 弹窗结构
    expect(find.text('选择主题'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);

    // 网格区域滚动（弹窗贴底，网格区在 y 250-760），露出第 2 行
    await tester.dragFrom(const Offset(400, 500), const Offset(0, -350));
    await tester.pump(const Duration(milliseconds: 300));

    // 选择"赛博霓虹"（第 2 行）并确定
    await tester.tap(find.text('赛博霓虹').last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('确定'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(skinNotifier.value.id, 'cyber_neon');

    // 再次打开：滚动到网格底部，最后两套（烈焰/电光）可见
    await tester.tap(find.text('更多主题'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.dragFrom(const Offset(400, 500), const Offset(0, -800));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('烈焰'), findsWidgets);
    expect(find.text('电光'), findsWidgets);
  });

  testWidgets('更多主题弹窗：取消不改变皮肤', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final before = skinNotifier.value.id;

    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('更多主题'));
    await tester.pump(const Duration(milliseconds: 400)); // 实时动画不会 settle，用固定时长
    await tester.dragFrom(const Offset(400, 500), const Offset(0, -800));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('烈焰').last);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('取消'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(skinNotifier.value.id, before);
  });
}
