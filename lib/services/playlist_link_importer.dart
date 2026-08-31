import '../models/music_data.dart';
import 'bilibili_api.dart';

class PlaylistLinkImportResult {
  final List<Song> songs;
  final List<String> missingBvids;

  const PlaylistLinkImportResult({
    required this.songs,
    required this.missingBvids,
  });
}

class PlaylistLinkImporter {
  const PlaylistLinkImporter._();

  static PlaylistLinkImportResult matchLocalSongs(
    Iterable<String> links,
    Iterable<Song> localSongs,
  ) {
    final byBvid = <String, Song>{
      for (final song in localSongs)
        if (song.bvid.isNotEmpty) song.bvid: song,
    };
    for (final song in localSongs) {
      final key = _fileNameKey(song.filePath);
      if (RegExp(r'^BV\w{10}$').hasMatch(key)) {
        byBvid.putIfAbsent(key, () => song);
      }
    }
    final songs = <Song>[];
    final missing = <String>[];
    final seen = <String>{};
    for (final link in links) {
      final bvid = BilibiliApi.extractBvid(link);
      if (bvid == null || !seen.add(bvid)) continue;
      final song = byBvid[bvid];
      if (song == null) {
        missing.add(bvid);
      } else {
        songs.add(song);
      }
    }
    return PlaylistLinkImportResult(songs: songs, missingBvids: missing);
  }

  static Future<PlaylistLinkImportResult> matchLocalSongsAsync(
    Iterable<String> links,
    Iterable<Song> localSongs, {
    Future<String> Function(String url)? resolveShortUrl,
  }) async {
    final resolved = <String>[];
    for (final link in links) {
      final bvid = BilibiliApi.extractBvid(link);
      if (bvid != null || !link.contains('b23.tv')) {
        resolved.add(link);
      } else {
        resolved.add(
          await (resolveShortUrl ?? BilibiliApi.resolveShortUrl)(link),
        );
      }
    }
    return matchLocalSongs(resolved, localSongs);
  }

  static String _fileNameKey(String path) {
    final name = path.split('\\').last.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}
