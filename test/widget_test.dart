import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/main.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App renders without errors', (WidgetTester tester) async {
    // 测试环境 mock SharedPreferences，避免 SettingsService 初始化失败
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const GoMusicApp());
    expect(find.text('下载'), findsWidgets);
    expect(find.text('播放'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    // 释放播放服务中的进度轮询定时器，避免测试结束时有 pending timer
    AudioPlayerService().disposeForTest();
  });
}
