import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File firstFile;
  late File secondFile;

  setUp(() {
    firstFile = File('${Directory.systemTemp.path}\\gomusic-previous-first.m4a')
      ..writeAsBytesSync(const <int>[0]);
    secondFile = File(
      '${Directory.systemTemp.path}\\gomusic-previous-second.m4a',
    )..writeAsBytesSync(const <int>[0]);
    injectFakePlayer();
  });

  tearDown(() {
    AudioPlayerService().disposeForTest();
    for (final file in [firstFile, secondFile]) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  });

  test(
    'prev always switches to the previous queue item after 3 seconds',
    () async {
      final first = Song(
        id: 'first',
        title: 'First',
        uploader: 'Test',
        duration: const Duration(seconds: 30),
        bvid: 'BVfirst',
        filePath: firstFile.path,
      );
      final second = Song(
        id: 'second',
        title: 'Second',
        uploader: 'Test',
        duration: const Duration(seconds: 30),
        bvid: 'BVsecond',
        filePath: secondFile.path,
      );
      final service = AudioPlayerService();
      service.setQueue([first, second], startIndex: 1, keepOrder: true);
      var songNotifications = 0;
      service.currentSongNotifier.addListener(() => songNotifications++);

      await service.playSong(second);
      await service.seek(const Duration(seconds: 10));
      await service.prev();

      expect(service.currentSong?.bvid, first.bvid);
      expect(service.queueIndex, 0);
      expect(
        lastFakePlayer!.lastOpenedUri,
        firstFile.path.replaceAll('\\', '/'),
      );
      expect(songNotifications, greaterThan(0));
    },
  );

  test('next switches the player to the next queue item', () async {
    final first = Song(
      id: 'first',
      title: 'First',
      uploader: 'Test',
      duration: const Duration(seconds: 30),
      bvid: 'BVfirst',
      filePath: firstFile.path,
    );
    final second = Song(
      id: 'second',
      title: 'Second',
      uploader: 'Test',
      duration: const Duration(seconds: 30),
      bvid: 'BVsecond',
      filePath: secondFile.path,
    );
    final service = AudioPlayerService();
    service.setQueue([first, second], startIndex: 0, keepOrder: true);

    await service.playSong(first);
    await service.next();

    expect(service.currentSong?.bvid, second.bvid);
    expect(service.queueIndex, 1);
    expect(
      lastFakePlayer!.lastOpenedUri,
      secondFile.path.replaceAll('\\', '/'),
    );
  });

  test('current song notifications expose the new song information', () async {
    final first = Song(
      id: 'first',
      title: 'First title',
      uploader: 'First artist',
      duration: const Duration(seconds: 30),
      bvid: 'BVfirst',
      filePath: firstFile.path,
    );
    final second = Song(
      id: 'second',
      title: 'Second title',
      uploader: 'Second artist',
      duration: const Duration(seconds: 45),
      bvid: 'BVsecond',
      filePath: secondFile.path,
    );
    final service = AudioPlayerService();
    final titles = <String>[];
    service.currentSongNotifier.addListener(() {
      final song = service.currentSong;
      if (song != null) titles.add(song.title);
    });
    service.setQueue([first, second], startIndex: 0, keepOrder: true);

    await service.playSong(first);
    await service.next();

    expect(service.currentSong?.title, 'Second title');
    expect(service.currentSong?.uploader, 'Second artist');
    expect(titles, contains('Second title'));
  });
}
