import 'dart:io';

/// Matches files produced by the download page without depending on UI state.
class DownloadFileMatcher {
  const DownloadFileMatcher._();

  static bool hasMediaFile({
    required String directory,
    required String bvid,
    required String title,
  }) {
    for (final name in _names(bvid, title)) {
      for (final extension in const [
        'm4a',
        'mp4',
        'mp3',
        'aac',
        'flac',
        'wav',
      ]) {
        final file = File(
          '${Directory(directory).path}${Platform.pathSeparator}$name.$extension',
        );
        if (file.existsSync() && file.lengthSync() > 0) return true;
      }
    }
    return false;
  }

  static bool hasFile({
    required String directory,
    required String bvid,
    required String title,
    required String extension,
  }) {
    for (final name in _names(bvid, title)) {
      final file = File(
        '${Directory(directory).path}${Platform.pathSeparator}$name.$extension',
      );
      if (file.existsSync() && file.lengthSync() > 0) return true;
    }
    return false;
  }

  static Iterable<String> _names(String bvid, String title) sync* {
    if (bvid.isNotEmpty) yield bvid;
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (safeTitle.isNotEmpty && safeTitle != bvid) yield safeTitle;
  }
}
