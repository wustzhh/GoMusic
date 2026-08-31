import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/pages/player_page.dart';
import 'package:gomusic/models/music_data.dart';
import 'package:gomusic/services/audio_player_service.dart';
import 'dart:io';

import 'fakes.dart';

void main() {
  testWidgets('player control button keeps its hit area and handles taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerControlButton(
            icon: Icons.play_arrow,
            size: 84,
            onPressed: () => taps++,
          ),
        ),
      ),
    );

    final before = tester.getSize(find.byType(PlayerControlButton));
    await tester.tap(find.byType(PlayerControlButton));
    await tester.pump();
    final after = tester.getSize(find.byType(PlayerControlButton));

    expect(taps, 1);
    expect(after, before);
  });
  testWidgets('player page keeps volume controls out of the playback view', (
    tester,
  ) async {
    final file = File('${Directory.systemTemp.path}\\gomusic-volume-test.m4a');
    file.writeAsBytesSync(const <int>[0]);
    addTearDown(() {
      AudioPlayerService().disposeForTest();
      try {
        file.deleteSync();
      } catch (_) {}
    });
    injectFakePlayer();
    await AudioPlayerService().playSong(
      Song(
        id: 'BV4444444444',
        title: '测试歌曲',
        uploader: '测试',
        duration: const Duration(seconds: 10),
        bvid: 'BV4444444444',
        filePath: file.path,
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: PlayerPage()));
    expect(find.byKey(const ValueKey('player-volume-slider')), findsNothing);
    AudioPlayerService().disposeForTest();
  });
}
