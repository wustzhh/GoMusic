import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/main.dart';

void main() {
  testWidgets('App renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(const GoMusicApp());
    expect(find.text('下载'), findsWidgets);
    expect(find.text('播放'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
  });
}
