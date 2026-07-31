import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// 歌曲数据模型
class Song {
  final String id;
  final String title;
  final String uploader;
  final Duration duration;
  final String? coverUrl;
  final bool hasVideo;
  final String bvid;
  final String filePath;
  final DateTime? lastPlayed;

  final String originalUrl;
  final String originalTitle;
  final String originalAuthor;

  const Song({
    required this.id,
    required this.title,
    required this.uploader,
    required this.duration,
    this.coverUrl,
    this.hasVideo = false,
    this.bvid = '',
    this.filePath = '',
    this.lastPlayed,
    this.originalUrl = '',
    this.originalTitle = '',
    this.originalAuthor = '',
  });

  String get durationText {
    if (duration == Duration.zero) return '';
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get lastPlayedText {
    if (lastPlayed == null) return '';
    final now = DateTime.now();
    final diff = now.difference(lastPlayed!);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${lastPlayed!.month.toString().padLeft(2, '0')}-${lastPlayed!.day.toString().padLeft(2, '0')} ${lastPlayed!.hour.toString().padLeft(2, '0')}:${lastPlayed!.minute.toString().padLeft(2, '0')}';
  }
}

/// 播放列表模型
class Playlist {
  final String id;
  final String name;
  final String icon;
  final List<Song> songs;

  const Playlist({required this.id, required this.name, required this.icon, required this.songs});
}

/// 下载记录模型
class DownloadRecord {
  final String id;
  final String title;
  final String url;
  final bool downloadVideo;
  final double progress;
  final DownloadStatus status;
  final bool hasAudio;
  final bool hasVideo;
  final String? fileSize;

  const DownloadRecord({required this.id, required this.title, required this.url, this.downloadVideo = false, this.progress = 0.0, this.status = DownloadStatus.pending, this.hasAudio = false, this.hasVideo = false, this.fileSize});
}

enum DownloadStatus { pending, downloading, completed, failed }

// ============================================================
// 最近播放服务 — 去重/上限1000/显示日期
// ============================================================

class RecentlyPlayedService {
  static const _key = 'recently_played';

  /// 添加歌曲到最近播放（去重：同一bvid只保留最后一次）
  static Future<void> addIfNotExists(String bvid, String title, String uploader, int durationSec, String filePath, String coverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];

    // 移除已存在的同bvid记录
    list.removeWhere((e) => e.startsWith('$bvid|'));

    // 添加到最前面
    final now = DateTime.now();
    final entry = '$bvid|$title|$uploader|$durationSec|$filePath|$coverUrl|${now.millisecondsSinceEpoch}';
    list.insert(0, entry);

    // 上限1000
    if (list.length > 1000) {
      list.removeRange(1000, list.length);
    }

    await prefs.setStringList(_key, list);
  }

  /// 获取最近播放列表（只返回文件真实存在的）
  static Future<List<Song>> getRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    final songs = <Song>[];
    final valid = <String>[];
    for (final entry in list) {
      final parts = entry.split('|');
      if (parts.length >= 7) {
        final filePath = parts[4];
        // 只保留文件真实存在的记录
        if (!File(filePath).existsSync()) continue;
        valid.add(entry);
        final ms = int.tryParse(parts[6]) ?? 0;
        songs.add(Song(
          id: parts[0], title: parts[1], uploader: parts[2],
          duration: Duration(seconds: int.tryParse(parts[3]) ?? 0),
          filePath: filePath, coverUrl: parts[5].isEmpty ? null : parts[5],
          bvid: parts[0], lastPlayed: DateTime.fromMillisecondsSinceEpoch(ms),
        ));
      }
    }
    // 清理已删除文件的记录
    if (valid.length != list.length) {
      await prefs.setStringList(_key, valid);
    }
    return songs;
  }
}

// ============================================================
// 本地歌单扫描
// ============================================================

Future<List<Song>> scanLocalAudioFiles(String dirPath) async {
  final songs = <Song>[];
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return songs;

  try {
    final files = dir.listSync();
    for (final f in files) {
      if (f is File) {
        final ext = f.path.split('.').last.toLowerCase();
        if (ext == 'm4a' || ext == 'mp3' || ext == 'aac' || ext == 'flac' || ext == 'wav') {
          final name = f.path.split(Platform.pathSeparator).last.split('.').first;
          final coverPath = '$dirPath${Platform.pathSeparator}$name.jpg';
          final coverFile = File(coverPath);
          final hasCover = coverFile.existsSync() && coverFile.lengthSync() > 0;
          // 读元数据
          String author = '';
          Duration duration = Duration.zero;
          final metaFile = File('$dirPath${Platform.pathSeparator}$name.json');
          if (metaFile.existsSync()) {
            try {
              final meta = jsonDecode(metaFile.readAsStringSync());
              author = meta['author'] as String? ?? '';
              duration = Duration(seconds: meta['duration'] as int? ?? 0);
            } catch (_) {}
          }
          songs.add(Song(
            id: f.path,
            title: name,
            uploader: author,
            duration: duration,
            filePath: f.path,
            coverUrl: hasCover ? coverPath : null,
          ));
        }
      }
    }
  } catch (_) {}

  return songs;
}

// ============================================================
// 自定义播放列表持久化
// ============================================================

class PlaylistService {
  static const _key = 'custom_playlists';

  static Future<List<Playlist>> getPlaylists() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    final valid = <String>[];
    final result = <Playlist>[];
    for (final raw in list) {
      if (raw.isEmpty) continue;
      var parts = raw.split('|||');
      // 丢弃末尾空元素
      while (parts.length > 3 && (parts.last.isEmpty)) { parts.removeLast(); }
      // 补齐到至少4段（id/name/icon/songsJson）
      while (parts.length < 4) { parts.add(''); }
      if (parts[0].isEmpty) continue;

      final name = parts[1];
      final songsJson = parts[3].isEmpty ? '[]' : parts[3];
      List<String> songPaths;
      try {
        final decoded = jsonDecode(songsJson);
        songPaths = (decoded as List).map((x) => x.toString()).where((fp) => fp.isNotEmpty).toList();
      } catch (_) {
        songPaths = songsJson.split(',').where((s) => s.isNotEmpty).toList();
        parts[3] = jsonEncode(songPaths);
      }
      // 清理空尾后回写
      while (parts.length > 3 && (parts.last.isEmpty)) { parts.removeLast(); }
      valid.add(parts.join('|||'));
      result.add(Playlist(
        id: parts[0], name: name, icon: parts[2],
        songs: songPaths.map((fp) {
          final coverPath = '${fp.substring(0, fp.lastIndexOf('.'))}.jpg';
          final hasCover = File(coverPath).existsSync() && File(coverPath).lengthSync() > 0;
          return Song(id: fp, title: fp.split(Platform.pathSeparator).last.split('.').first, uploader: '', duration: Duration.zero, filePath: fp, coverUrl: hasCover ? coverPath : null);
        }).toList(),
      ));
    }
    if (!_listEquals(list, valid)) {
      await p.setStringList(_key, valid);
    }
    return result;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; }
    return true;
  }

  static Future<void> addPlaylist(String name) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    list.add('$id|||$name|||📋|||[]');
    await p.setStringList(_key, list);
  }

  static Future<void> addSongToPlaylist(String playlistId, String filePath) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (var i = 0; i < list.length; i++) {
      var parts = list[i].split('|||');
      // 丢弃末尾空元素
      while (parts.length > 3 && (parts.last.isEmpty)) { parts.removeLast(); }
      // 补齐到至少4段
      while (parts.length < 4) { parts.add(''); }
      if (parts[0] == playlistId) {
        final songsJson = parts[3].isEmpty ? '[]' : parts[3];
        List<dynamic> paths;
        try { paths = jsonDecode(songsJson); } catch (_) { paths = (songsJson.isEmpty ? [] : songsJson.split(',')); }
        final pathSet = paths.map((x) => x.toString()).where((x) => x.isNotEmpty).toSet();
        pathSet.add(filePath);
        parts[3] = jsonEncode(pathSet.toList());
        // 丢弃空尾
        while (parts.length > 3 && (parts.last.isEmpty)) { parts.removeLast(); }
        list[i] = parts.join('|||');
        await p.setStringList(_key, list);
        return;
      }
    }
  }

  static Future<bool> isSongInPlaylist(String playlistId, String filePath) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (final entry in list) {
      final parts = entry.split('|||');
      if (parts[0] == playlistId) {
        final songsJson = parts.length > 3 ? parts[3] : '[]';
        try {
          final paths = jsonDecode(songsJson) as List;
          return paths.map((x) => x.toString()).contains(filePath);
        } catch (_) {
          return false;
        }
      }
    }
    return false;
  }
}
