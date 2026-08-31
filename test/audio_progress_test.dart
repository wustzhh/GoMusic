import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory originalDirectory;
  late Directory tempDirectory;

  setUp(() {
    originalDirectory = Directory.current;
    tempDirectory = Directory.systemTemp.createTempSync('gomusic_progress_');
    Directory.current = tempDirectory;
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
}
