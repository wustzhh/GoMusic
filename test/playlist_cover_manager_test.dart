import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/playlist_cover_manager.dart';

void main() {
  late Directory root;
  late Directory sourceDirectory;
  late PlaylistCoverManager manager;

  setUp(() async {
    root = Directory('build/test-playlist-cover-manager');
    if (root.existsSync()) await root.delete(recursive: true);
    await root.create(recursive: true);
    sourceDirectory = Directory('${root.path}${Platform.pathSeparator}sources');
    await sourceDirectory.create();
    manager = PlaylistCoverManager(baseDirectory: root);
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test(
    'copies a local cover into the managed playlist_covers directory',
    () async {
      final source = File(
        '${sourceDirectory.path}${Platform.pathSeparator}cover.jpg',
      );
      await source.writeAsString('cover-data');

      final copiedPath = await manager.copyLocalCover(
        source.path,
        ownerId: 'playlist-1',
      );

      expect(
        copiedPath,
        contains(
          '${Platform.pathSeparator}playlist_covers${Platform.pathSeparator}',
        ),
      );
      expect(await File(copiedPath).readAsString(), 'cover-data');
      expect(await source.exists(), isTrue);
    },
  );

  test('replaces an owner cover while keeping the managed filename', () async {
    final first = File(
      '${sourceDirectory.path}${Platform.pathSeparator}first.png',
    );
    final second = File(
      '${sourceDirectory.path}${Platform.pathSeparator}second.png',
    );
    await first.writeAsString('first');
    await second.writeAsString('second');

    final firstPath = await manager.copyLocalCover(
      first.path,
      ownerId: 'playlist-1',
    );
    final secondPath = await manager.copyLocalCover(
      second.path,
      ownerId: 'playlist-1',
    );

    expect(secondPath, firstPath);
    expect(await File(secondPath).readAsString(), 'second');
  });

  test(
    'deleteCover refuses to delete a file outside the managed directory',
    () async {
      final outside = File('${root.path}${Platform.pathSeparator}outside.jpg');
      await outside.writeAsString('keep');

      await expectLater(
        manager.deleteCover(outside.path),
        throwsA(isA<ArgumentError>()),
      );
      expect(await outside.exists(), isTrue);
    },
  );

  test('deleteCover removes a managed copy', () async {
    final source = File(
      '${sourceDirectory.path}${Platform.pathSeparator}cover.jpg',
    );
    await source.writeAsString('cover-data');
    final copiedPath = await manager.copyLocalCover(
      source.path,
      ownerId: 'playlist-1',
    );

    await manager.deleteCover(copiedPath);

    expect(await File(copiedPath).exists(), isFalse);
  });
}
