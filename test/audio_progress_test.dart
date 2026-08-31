import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory originalDirectory;
  late Directory tempDirectory;

  setUp(() {
    originalDirectory = Directory.current;
    tempDirectory = Directory.systemTemp.createTempSync('gomusic_progress_');
    Directory.current = tempDirectory;
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    Directory.current = originalDirectory;
    try {
      tempDirectory.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('实时 position 事件更新当前播放进度，而不是依赖过期 state.position', () async {
    final audioFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}song.mp3',
    )..writeAsBytesSync(const <int>[0]);
    final song = Song(
      id: 'progress-test',
      title: 'Progress test',
      uploader: 'test',
      duration: const Duration(minutes: 3),
      bvid: 'BV-progress-test',
      filePath: audioFile.path,
    );
    final service = AudioPlayerService();

    await service.playSong(song);
    expect(service.currentPosition, Duration.zero);

    lastFakePlayer!.emitPosition(const Duration(seconds: 12));
    await Future<void>.delayed(Duration.zero);

    expect(service.currentPosition, const Duration(seconds: 12));
  });

  test('恢复上次歌曲后首次播放会重新加载媒体文件', () async {
    final audioFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}restored.m4a',
    )..writeAsBytesSync(const <int>[0]);
    File('save_state.json').writeAsStringSync(
      jsonEncode({
        'song': audioFile.path,
        'title': 'Restored song',
        'uploader': 'test',
        'duration': 180,
        'bvid': 'BV-restored',
        'cover': '',
        'position': 0,
        'queue': <String>[],
        'queue_index': 0,
      }),
    );

    final service = AudioPlayerService();
    final restored = await service.restoreLastSong();
    expect(restored, isNotNull);

    await service.playSong(restored!);

    expect(lastFakePlayer!.openCount, 1);
    expect(lastFakePlayer!.playCount, 1);
  });

  test('暂停时保留实时播放进度，不使用过期 state.position 清零', () async {
    final audioFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}pause.m4a',
    )..writeAsBytesSync(const <int>[0]);
    final song = Song(
      id: 'pause-test',
      title: 'Pause test',
      uploader: 'test',
      duration: const Duration(minutes: 3),
      bvid: 'BV-pause-test',
      filePath: audioFile.path,
    );
    final service = AudioPlayerService();

    await service.playSong(song);
    lastFakePlayer!.emitPosition(const Duration(seconds: 12));
    await Future<void>.delayed(Duration.zero);
    service.togglePause();
    await Future<void>.delayed(Duration.zero);

    expect(service.currentPosition, const Duration(seconds: 12));
    expect(service.isPlaying, isFalse);
  });
}
