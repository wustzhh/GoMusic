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

  test('changing volume keeps the current media and position', () async {
    final file = File('build/volume-no-reload-test.m4a')..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final s = AudioPlayerService();
    await s.playSong(
      Song(
        id: 'volume-no-reload-test',
        title: 'volume-no-reload-test',
        uploader: 'test',
        duration: Duration.zero,
        filePath: file.path,
        bvid: 'BV-volume-no-reload-test',
      ),
    );
    await s.seek(const Duration(seconds: 12));
    final player = lastFakePlayer!;
    final opensBefore = player.openCount;

    await s.setVolume(200);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(player.openCount, opensBefore);
    expect(player.position, const Duration(seconds: 12));
    expect(player.appliedVolume, 200.0);
  });

  test('setVolume applies the full boosted value to the player', () async {
    final file = File('build/volume-backend-test.m4a')..writeAsBytesSync([1]);
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

  test(
    'boosted playback opens normally and applies the value without a filter',
    () async {
      final file = File('build/volume-before-open-test.m4a')
        ..writeAsBytesSync([1]);
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final s = AudioPlayerService();
      await s.setVolume(200);
      await s.playSong(
        Song(
          id: 'volume-before-open-test',
          title: 'volume-before-open-test',
          uploader: 'test',
          duration: Duration.zero,
          filePath: file.path,
          bvid: 'BV-volume-before-open-test',
        ),
      );

      expect(lastFakePlayer!.lastOpenPlay, isTrue);
      expect(lastFakePlayer!.appliedVolume, 200.0);
    },
  );

  test('rapid boosted-volume changes apply only the latest value', () async {
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

  test('boosted volume is debounced until the slider settles', () async {
    final file = File('build/volume-debounce-test.m4a')..writeAsBytesSync([1]);
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
    lastFakePlayer!.setPropertyValues.clear();
    lastFakePlayer!.appliedVolume = null;

    await s.setVolume(200);
    expect(lastFakePlayer!.appliedVolume, isNull);

    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(lastFakePlayer!.appliedVolume, 200.0);
    expect(lastFakePlayer!.setPropertyValues, hasLength(1));
  });

  test('changing volume does not reload current media', () async {
    final file = File('build/volume-reconfigure-test.m4a')
      ..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final s = AudioPlayerService();
    await s.playSong(
      Song(
        id: 'volume-reconfigure-test',
        title: 'volume-reconfigure-test',
        uploader: 'test',
        duration: Duration.zero,
        filePath: file.path,
        bvid: 'BV-volume-reconfigure-test',
      ),
    );
    await s.seek(const Duration(seconds: 12));
    final player = lastFakePlayer!;
    player.operationLog.clear();
    player.setPropertyValues.clear();

    await s.setVolume(200);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(player.openCount, 1);
    expect(player.position, const Duration(seconds: 12));
    expect(player.appliedVolume, 200.0);
  });

  test('slider settling during a boost never reloads the media', () async {
    final file = File('build/volume-settle-reload-test.m4a')
      ..writeAsBytesSync([1]);
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final s = AudioPlayerService();
    await s.playSong(
      Song(
        id: 'volume-settle-reload-test',
        title: 'volume-settle-reload-test',
        uploader: 'test',
        duration: Duration.zero,
        filePath: file.path,
        bvid: 'BV-volume-settle-reload-test',
      ),
    );
    final player = lastFakePlayer!;

    await s.setVolume(200);
    await s.setVolume(150);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(player.openCount, 1);

    await s.setVolume(200);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(player.openCount, 1);
  });

  test('player volume-max is configured when player is attached', () async {
    final file = File('build/volume-limiter-test.m4a')..writeAsBytesSync([1]);
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

    expect(lastFakePlayer!.setPropertyValues, contains('volume-max=200'));
  });

  test('restoreVolume does not apply volume before media is loaded', () async {
    SharedPreferences.setMockInitialValues({'windows_volume': 137.0});
    final s = AudioPlayerService();

    await s.restoreVolume();

    expect(lastFakePlayer?.appliedVolume, isNull);
  });
}
