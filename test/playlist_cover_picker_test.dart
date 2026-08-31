import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gomusic/services/playlist_cover_manager.dart';
import 'package:gomusic/services/playlist_cover_picker.dart';

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.path);

  final String? path;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (path == null) return null;
    return FilePickerResult([
      PlatformFile(name: 'cover.jpg', size: 4, path: path),
    ]);
  }
}

void main() {
  test(
    'system-selected cover is copied before the source can disappear',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'gomusic-cover-picker-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}${Platform.pathSeparator}source.jpg');
      await source.writeAsString('cover');

      final picker = PlaylistCoverPicker(
        filePicker: _FakeFilePicker(source.path),
        coverManager: PlaylistCoverManager(baseDirectory: root),
      );

      final managedPath = await picker.pickAndCopy(ownerId: 'playlist-1');
      await source.delete();

      expect(managedPath, isNotNull);
      expect(await File(managedPath!).readAsString(), 'cover');
    },
  );
}
