import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'dart:io';
import 'package:gomusic/models/music_data.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    injectFakePlayer();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
  });

  test('default volume is 100', () {
    final s = AudioPlayerService();
    expect(s.volume, 100.0);
    expect(s.volumeNotifier.value, 100.0);
  });

  test('setVolume clamps to 5..200', () async {
    final s = AudioPlayerService();
    await s.setVolume(240);
    expect(s.volume, 200.0);
    await s.setVolume(0);
    expect(s.volume, 5.0);
    await s.setVolume(66);
    expect(s.volume, 66.0);
    expect(s.volumeNotifier.value, 66.0);
  });

  test('changeVolume steps by 5', () async {
    final s = AudioPlayerService();
    await s.changeVolume(5);
    expect(s.volume, 105.0);
    await s.setVolume(50);
    await s.changeVolume(5);
    expect(s.volume, 55.0);
    await s.changeVolume(-10);
    expect(s.volume, 45.0);
    await s.changeVolume(-100);
    expect(s.volume, 5.0);
  });

  test('restoreVolume restores persisted value', () async {
    SharedPreferences.setMockInitialValues({'windows_volume': 137.0});
    final s = AudioPlayerService();
    await s.restoreVolume();
    expect(s.volume, 137.0);
    expect(s.volumeNotifier.value, 137.0);
  });

  test('restoreVolume defaults to 100 when nothing persisted', () async {
    final s = AudioPlayerService();
    await s.restoreVolume();
    expect(s.volume, 100.0);
  });

  test('setVolume persists value', () async {
    final s = AudioPlayerService();
    await s.setVolume(142);
    final p = await SharedPreferences.getInstance();
    expect(p.getDouble('windows_volume'), 142.0);
  });

  test('setVolume applies boosted value directly to the player', () async {
    final file = File('build/volume-backend-test.m4a')
      ..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final s = AudioPlayerService();
    await s.playSong(
      Song(
        id: 'volume-backend-test',
        title: 'volume-backend-test',
        uploader: 'test',
        duration: Duration.zero,
        filePath: file.path,
        bvid: 'BV-volume-backend-test',
      ),
    );
    await s.setVolume(200);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(lastFakePlayer?.appliedVolume, 200.0);
  });

  test('rapid boosted-volume changes apply only the latest volume', () async {
    final file = File('build/volume-test.m4a')..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final s = AudioPlayerService();
    await s.playSong(
      Song(
        id: 'volume-test',
        title: 'volume-test',
        uploader: 'test',
        duration: Duration.zero,
        filePath: file.path,
        bvid: 'BV-volume-test',
      ),
    );
    lastFakePlayer!.appliedVolume = null;

    await Future.wait([
      s.setVolume(110),
      s.setVolume(130),
      s.setVolume(160),
      s.setVolume(200),
    ]);

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(lastFakePlayer!.appliedVolume, 200.0);
  });

  test('boosted volume defers apply until slider settles', () async {
    final file = File('build/volume-debounce-test.m4a')
      ..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final s = AudioPlayerService();
    await s.playSong(
      Song(
        id: 'volume-debounce-test',
        title: 'volume-debounce-test',
        uploader: 'test',
        duration: Duration.zero,
        filePath: file.path,
        bvid: 'BV-volume-debounce-test',
      ),
    );
    lastFakePlayer!.appliedVolume = null;

    await s.setVolume(200);
    expect(lastFakePlayer!.appliedVolume, isNull);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(lastFakePlayer!.appliedVolume, 200.0);
  });

  test('player volume-max is configured when player is attached', () async {
    final file = File('build/volume-limiter-test.m4a')
      ..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final s = AudioPlayerService();
    await s.playSong(
      Song(
        id: 'volume-limiter-test',
        title: 'volume-limiter-test',
        uploader: 'test',
        duration: Duration.zero,
        filePath: file.path,
        bvid: 'BV-volume-limiter-test',
      ),
    );

    expect(
      lastFakePlayer!.setPropertyValues,
      contains('volume-max=200'),
    );
  });

  test('restoreVolume does not apply volume before media is loaded', () async {
    SharedPreferences.setMockInitialValues({'windows_volume': 137.0});
    final s = AudioPlayerService();

    await s.restoreVolume();

    expect(lastFakePlayer?.appliedVolume, isNull);
  });
}
