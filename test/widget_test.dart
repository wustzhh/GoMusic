import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/main.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  testWidgets('App renders without errors', (WidgetTester tester) async {
    // 测试环境 mock SharedPreferences，避免 SettingsService 初始化失败
    SharedPreferences.setMockInitialValues({});
    // 注入假播放内核：App 启动会访问 media_kit（测试环境无法加载 libmpv）
    injectFakePlayer();
    // 隔离到临时目录：避免 restoreLastSong 读写真实 save_state.json
    final orig = Directory.current;
    final tmp = Directory.systemTemp.createTempSync('widget_');
    Directory.current = tmp;
    try {
      await tester.pumpWidget(const GoMusicApp());
      expect(find.text('下载'), findsWidgets);
      expect(find.text('播放'), findsWidgets);
      expect(find.text('设置'), findsWidgets);
    } finally {
      // 释放播放服务中的进度轮询定时器，避免测试结束时有 pending timer
      AudioPlayerService().disposeForTest();
      Directory.current = orig;
      try { tmp.deleteSync(recursive: true); } catch (_) {}
    }
  });
}
