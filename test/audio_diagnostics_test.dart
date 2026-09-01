import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
    tempDirectory = Directory.systemTemp.createTempSync('gomusic_diagnostics_');
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    try {
      tempDirectory.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('records local file facts after a playback open completes', () async {
    final file = File('${tempDirectory.path}${Platform.pathSeparator}song.m4a')
      ..writeAsBytesSync(const <int>[1, 2, 3, 4]);
    final song = Song(
      id: 'diagnostics-test',
      title: 'Diagnostics test',
      uploader: 'test',
      duration: const Duration(minutes: 3),
      bvid: 'BV-diagnostics-test',
      filePath: file.path,
    );

    final service = AudioPlayerService();
    await service.playSong(song);

    final diagnostics = service.playbackDiagnosticsNotifier.value;
    expect(diagnostics, isNotNull);
    expect(diagnostics!.path, file.path);
    expect(diagnostics.fileExists, isTrue);
    expect(diagnostics.fileSize, 4);
    expect(diagnostics.openCompleted, isTrue);
    expect(diagnostics.lastError, isNull);
    expect(diagnostics.duration, const Duration(seconds: 100));
  });

  test('keeps the selected song and records a missing local file', () async {
    final song = Song(
      id: 'missing-test',
      title: 'Missing test',
      uploader: 'test',
      duration: const Duration(minutes: 3),
      bvid: 'BV-missing-test',
      filePath: '${tempDirectory.path}${Platform.pathSeparator}missing.m4a',
    );

    final service = AudioPlayerService();
    await service.playSong(song);

    expect(service.currentSong, same(song));
    final diagnostics = service.playbackDiagnosticsNotifier.value;
    expect(diagnostics, isNotNull);
    expect(diagnostics!.fileExists, isFalse);
    expect(diagnostics.phase, 'file missing');
  });
}
