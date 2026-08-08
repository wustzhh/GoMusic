import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SongManager.init(Directory.systemTemp.createTempSync('gm_').path);
  });

  test('本地歌单拖动顺序保存与读取（持久化）', () async {
    expect(await SongManager.getLocalOrder(), isEmpty);
    await SongManager.saveLocalOrder(['BV3', 'BV1', 'BV2']);
    final order = await SongManager.getLocalOrder();
    expect(order, ['BV3', 'BV1', 'BV2']);
  });

  test('重新进入后仍保持拖动顺序', () async {
    await SongManager.saveLocalOrder(['BV5', 'BV4']);
    final order = await SongManager.getLocalOrder();
    expect(order, ['BV5', 'BV4']);
  });
}
