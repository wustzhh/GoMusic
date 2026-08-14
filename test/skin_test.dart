import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/settings_service.dart';
import 'package:gomusic/ui/skin.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Skins.byId：已知 id 返回对应皮肤，未知 id 回退素·深色', () {
    final aurora = Skins.byId('aurora');
    expect(aurora.name, '极光');
    expect(aurora.animated, true);
    expect(aurora.dark, true);
    expect(aurora.orbs, isNotEmpty);

    expect(Skins.byId('not_exist').id, 'plain_dark');
    expect(Skins.byId('').dark, true);
  });

  test('皮肤全集：8 套（2 素 + 6 动态），id 唯一', () {
    expect(Skins.all.length, 8);
    final ids = Skins.all.map((s) => s.id).toSet();
    expect(ids.length, 8);
    // 素皮肤无动画，动态皮肤都有光晕
    expect(Skins.plainLight.animated, false);
    expect(Skins.plainDark.animated, false);
    for (final s in Skins.all.where((s) => s.animated)) {
      expect(s.orbs, isNotEmpty, reason: '${s.name} 应有光晕');
    }
  });

  test('SettingsService 皮肤持久化：默认极光，可保存读取', () async {
    final svc = await SettingsService.getInstance();
    expect(svc.getSkin(), 'aurora');
    await svc.setSkin('cyber_neon');
    expect(svc.getSkin(), 'cyber_neon');
  });
}
