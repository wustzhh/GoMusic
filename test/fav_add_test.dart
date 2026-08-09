import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fakes.dart';

Song _song(String bvid) => Song(
  id: bvid, title: '歌$bvid', uploader: 'u',
  duration: const Duration(seconds: 60), bvid: bvid, filePath: 'C:/x/$bvid.mp3',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() { SharedPreferences.setMockInitialValues({}); injectFakePlayer(); });
  tearDown(() { AudioPlayerService().disposeForTest(); });

  test('批量添加纯添加：重复添加不取消，新歌在最上', () async {
    // 模拟批量：第3/4/5首（整体插最上，保持顺序）
    await AudioPlayerService.addFavoritesBatch([_song('BV3'), _song('BV4'), _song('BV5')]);
    expect(await AudioPlayerService.getFavorites(), ['BV3', 'BV4', 'BV5']);

    // 模拟批量：前5首（含已在的3/4/5；新加的1/2在最上）
    final all = [_song('BV1'), _song('BV2'), _song('BV3'), _song('BV4'), _song('BV5')];
    await AudioPlayerService.addFavoritesBatch(all);
    final favs = await AudioPlayerService.getFavorites();
    print('最终收藏: $favs');
    expect(favs.length, 5, reason: '前5首添加后应共5首（已在的不取消）');
    expect(favs, containsAll(['BV1', 'BV2', 'BV3', 'BV4', 'BV5']));
    expect(favs.sublist(0, 2), containsAll(['BV1', 'BV2']), reason: '新添加的 BV1/BV2 在最上');
  });

  test('toggleFavorite 仍可取消（单曲菜单语义不变）', () async {
    final s = _song('BV1');
    await AudioPlayerService.toggleFavorite(s);
    expect(await AudioPlayerService.getFavorites(), ['BV1']);
    await AudioPlayerService.toggleFavorite(s);
    expect(await AudioPlayerService.getFavorites(), isEmpty);
  });
}
