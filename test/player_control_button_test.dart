import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/pages/player_page.dart';

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
}
