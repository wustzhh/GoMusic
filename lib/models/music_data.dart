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
  final String originalUrl;
  final String originalTitle;
  final String originalAuthor;
  final DateTime? lastPlayed;

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
}

/// 播放列表模型
class Playlist {
  final String id;
  final String name;
  final String icon;
  final List<Song> songs;
  const Playlist({required this.id, required this.name, required this.icon, required this.songs});
}

// ============================================================
// 歌曲管理器 — 统一管理 metadata_map.json
// ============================================================

class SongManager {
  static String? _downloadDir;

  static Future<void> init(String dir) async {
    _downloadDir = dir;
  }

  static String get _mapPath => '$_downloadDir${Platform.pathSeparator}metadata_map.json';

  /// 读取全部元数据
  static Map<String, dynamic> _readMap() {
    final f = File(_mapPath);
    if (!f.existsSync()) return {};
    try {
      return jsonDecode(f.readAsStringSync());
    } catch (_) {
      return {};
    }
  }

  /// 写入元数据
  static void _writeMap(Map<String, dynamic> map) {
    File(_mapPath).writeAsStringSync(jsonEncode(map));
  }

  /// 下载完全成功后登记歌曲
  static void registerSong({
    required String filePath,
    required String title,
    required String uploader,
    required int durationSec,
    required String bvid,
    required String url,
    String? coverPath,
  }) {
    final map = _readMap();
    map[filePath] = {
      'title': title,
      'uploader': uploader,
      'duration': durationSec,
      'bvid': bvid,
      'url': url,
      'coverPath': coverPath ?? '',
    };
    _writeMap(map);
  }

  /// 删除歌曲登记
  static void unregisterSong(String filePath) {
    final map = _readMap();
    map.remove(filePath);
    _writeMap(map);
  }

  /// 扫描本地文件，返回 Song 列表
  static List<Song> scanLocalSongs() {
    if (_downloadDir == null) return [];
    final dir = Directory(_downloadDir!);
    if (!dir.existsSync()) return [];

    final map = _readMap();
    final songs = <Song>[];
    for (final f in dir.listSync()) {
      if (f is File) {
        final ext = f.path.split('.').last.toLowerCase();
        if (ext == 'm4a' || ext == 'mp3' || ext == 'aac' || ext == 'flac' || ext == 'wav') {
          // 从注册表中查元数据
          final meta = map[f.path] as Map<String, dynamic>?;
          final title = meta?['title'] as String? ?? f.path.split(Platform.pathSeparator).last.split('.').first;
          final uploader = meta?['uploader'] as String? ?? '';
          final duration = Duration(seconds: meta?['duration'] as int? ?? 0);
          final bvid = meta?['bvid'] as String? ?? '';
          final url = meta?['url'] as String? ?? '';
          final coverPath = meta?['coverPath'] as String? ?? '';
          // 检查封面文件是否存在
          String? cover;
          if (coverPath.isNotEmpty && File(coverPath).existsSync()) {
            cover = coverPath;
          }
          songs.add(Song(
            id: f.path,
            title: title,
            uploader: uploader,
            duration: duration,
            filePath: f.path,
            bvid: bvid,
            coverUrl: cover,
            originalUrl: url,
            originalTitle: title,
            originalAuthor: uploader,
          ));
        }
      }
    }
    return songs;
  }
}

// ============================================================
// 最近播放服务
// ============================================================

class RecentlyPlayedService {
  static const _key = 'recently_played';

  static Future<void> addIfNotExists(String key, String title, String uploader, int durationSec, String filePath, String coverUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.removeWhere((e) => e.startsWith('$key|'));
    final now = DateTime.now();
    final entry = '$key|$title|$uploader|$durationSec|$filePath|$coverUrl|${now.millisecondsSinceEpoch}';
    list.insert(0, entry);
    if (list.length > 1000) list.removeRange(1000, list.length);
    await prefs.setStringList(_key, list);
  }

  static Future<List<Song>> getRecentSongs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    final songs = <Song>[];
    for (final entry in list) {
      final parts = entry.split('|');
      if (parts.length >= 7 && File(parts[4]).existsSync()) {
        songs.add(Song(
          id: parts[0], title: parts[1], uploader: parts[2],
          duration: Duration(seconds: int.tryParse(parts[3]) ?? 0),
          filePath: parts[4], coverUrl: parts[5].isEmpty ? null : parts[5],
          bvid: parts[0], lastPlayed: DateTime.fromMillisecondsSinceEpoch(int.tryParse(parts[6]) ?? 0),
        ));
      }
    }
    // 清理无效记录
    if (songs.length != list.length) {
      final valid = list.where((e) => File(e.split('|')[4]).existsSync()).toList();
      await prefs.setStringList(_key, valid);
    }
    return songs;
  }
}

// ============================================================
// 播放列表持久化
// ============================================================

class PlaylistService {
  static const _key = 'custom_playlists';

  static Future<List<Playlist>> getPlaylists() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    final result = <Playlist>[];
    for (final raw in list) {
      var parts = raw.split('|||');
      while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
      while (parts.length < 4) parts.add('');
      if (parts[0].isEmpty) continue;
      List<String> songPaths;
      try { songPaths = (jsonDecode(parts[3]) as List).map((x) => x.toString()).where((x) => x.isNotEmpty).toList(); }
      catch (_) { songPaths = parts[3].split(',').where((s) => s.isNotEmpty).toList(); }
      result.add(Playlist(id: parts[0], name: parts[1], icon: parts[2],
        songs: songPaths.map((fp) => Song(id: fp, title: fp.split(Platform.pathSeparator).last.split('.').first, uploader: '', duration: Duration.zero, filePath: fp)).toList(),
      ));
    }
    return result;
  }

  static Future<void> addPlaylist(String name) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    list.add('${DateTime.now().millisecondsSinceEpoch}|||$name|||📋|||[]');
    await p.setStringList(_key, list);
  }

  static Future<void> addSongToPlaylist(String pid, String filePath) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (var i = 0; i < list.length; i++) {
      var parts = list[i].split('|||');
      while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
      while (parts.length < 4) parts.add('');
      if (parts[0] == pid) {
        List<dynamic> paths = [];
        try { paths = jsonDecode(parts[3]); } catch (_) { paths = parts[3].split(','); }
        final set = paths.map((x) => x.toString()).where((x) => x.isNotEmpty).toSet();
        set.add(filePath);
        parts[3] = jsonEncode(set.toList());
        while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
        list[i] = parts.join('|||');
        await p.setStringList(_key, list);
        return;
      }
    }
  }

  static Future<bool> isSongInPlaylist(String pid, String filePath) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (final entry in list) {
      final parts = entry.split('|||');
      if (parts[0] == pid) {
        final songsJson = parts.length > 3 ? parts[3] : '[]';
        try { return (jsonDecode(songsJson) as List).map((x) => x.toString()).contains(filePath); }
        catch (_) { return false; }
      }
    }
    return false;
  }
}

// ============================================================
// 本地歌单扫描（兼容旧接口）
// ============================================================
Future<List<Song>> scanLocalAudioFiles(String dirPath) async {
  SongManager.init(dirPath);
  return SongManager.scanLocalSongs();
}
