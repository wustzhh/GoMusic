import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Owns local copies of playlist covers so they do not depend on source files.
class PlaylistCoverManager {
  final Directory? baseDirectory;

  PlaylistCoverManager({this.baseDirectory});

  Future<Directory> _managedDirectory() async {
    final base = baseDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}playlist_covers',
    );
    await directory.create(recursive: true);
    return directory;
  }

  String _fileName(String path) => path.split('\\').last.split('/').last;

  String _safeOwnerId(String ownerId) {
    final safe = ownerId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    if (safe.isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    return safe;
  }

  Future<String> copyLocalCover(
    String sourcePath, {
    required String ownerId,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'File does not exist',
      );
    }
    final name = _fileName(source.path);
    final dot = name.lastIndexOf('.');
    final extension = dot > 0 ? name.substring(dot) : '';
    final directory = await _managedDirectory();
    final target = File(
      '${directory.path}${Platform.pathSeparator}${_safeOwnerId(ownerId)}$extension',
    );
    await source.copy(target.path);
    return target.path;
  }

  Future<void> deleteCover(String coverPath) async {
    final directory = await _managedDirectory();
    final managedPath = (await directory.resolveSymbolicLinks()).replaceAll(
      '/',
      Platform.pathSeparator,
    );
    final candidate = File(coverPath);
    var candidatePath = candidate.absolute.path;
    if (await candidate.exists()) {
      candidatePath = await candidate.resolveSymbolicLinks();
    } else if (candidate.parent.existsSync()) {
      final parent = await Directory(
        candidate.parent.path,
      ).resolveSymbolicLinks();
      candidatePath =
          '$parent${Platform.pathSeparator}${_fileName(candidate.path)}';
    }
    final normalizedManaged = managedPath.endsWith(Platform.pathSeparator)
        ? managedPath.substring(0, managedPath.length - 1)
        : managedPath;
    final normalizedCandidate = candidatePath.replaceAll(
      '/',
      Platform.pathSeparator,
    );
    final comparisonManaged = Platform.isWindows
        ? normalizedManaged.toLowerCase()
        : normalizedManaged;
    final comparisonCandidate = Platform.isWindows
        ? normalizedCandidate.toLowerCase()
        : normalizedCandidate;
    if (!comparisonCandidate.startsWith(
      '$comparisonManaged${Platform.pathSeparator}',
    )) {
      throw ArgumentError.value(
        coverPath,
        'coverPath',
        'Cover is outside the managed directory',
      );
    }
    if (await candidate.exists()) await candidate.delete();
  }
}
