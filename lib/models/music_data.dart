import 'dart:convert';
import 'dart:io';
import 'dart:math';
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

  /// 移动歌单在列表中的位置（调整顺序）
  static Future<void> movePlaylist(int from, int to) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    if (from < 0 || from >= list.length || to < 0 || to >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to, item);
    await p.setStringList(_key, list);
  }

  /// 设置歌单图标（封面）
  static Future<void> setPlaylistIcon(String pid, String icon) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (var i = 0; i < list.length; i++) {
      var parts = list[i].split('|||');
      while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
      while (parts.length < 4) parts.add('');
      if (parts[0] == pid) {
        parts[2] = icon;
        while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
        list[i] = parts.join('|||');
        await p.setStringList(_key, list);
        return;
      }
    }
  }

  /// 从歌单移除歌曲
  static Future<void> removeSongFromPlaylist(String pid, String filePath) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (var i = 0; i < list.length; i++) {
      var parts = list[i].split('|||');
      while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
      while (parts.length < 4) parts.add('');
      if (parts[0] == pid) {
        List<dynamic> paths = [];
        try { paths = jsonDecode(parts[3]); } catch (_) { paths = parts[3].split(','); }
        paths.removeWhere((x) => x.toString() == filePath);
        parts[3] = jsonEncode(paths.map((x) => x.toString()).where((x) => x.isNotEmpty).toList());
        while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
        list[i] = parts.join('|||');
        await p.setStringList(_key, list);
        return;
      }
    }
  }
}

// ============================================================
// 歌曲组（组队系统）
// 每首歌默认是独立组；组队 = 多组合并；组可设组内顺序/随机
// ============================================================
class SongGroup {
  final String id;
  final String playlistId; // 所属歌单
  String name;
  final List<String> songPaths;
  bool shuffle; // 组内随机
  SongGroup({required this.id, required this.playlistId, required this.name, required this.songPaths, this.shuffle = false});
}

class SongGroupService {
  static const _key = 'song_groups';
  static List<SongGroup> _cache = [];
  static bool _loaded = false;

  static void _ensureLoaded() {
    if (_loaded) return;
    try {
      final f = File('song_groups.json');
      if (f.existsSync()) {
        final data = jsonDecode(f.readAsStringSync()) as List;
        _cache = data.map((e) {
          final m = e as Map<String, dynamic>;
          return SongGroup(
            id: m['id'] as String? ?? '',
            playlistId: m['pl'] as String? ?? '',
            name: m['name'] as String? ?? '组',
            songPaths: List<String>.from(m['paths'] ?? []),
            shuffle: m['shuffle'] as bool? ?? false,
          );
        }).toList();
      }
      _loaded = true;
    } catch (_) {
      _loaded = true;
    }
  }

  static void _save() {
    try {
      File('song_groups.json').writeAsStringSync(jsonEncode(_cache.map((g) => {
        'id': g.id, 'pl': g.playlistId, 'name': g.name, 'paths': g.songPaths, 'shuffle': g.shuffle,
      }).toList()));
    } catch (_) {}
  }

  /// 获取某歌单的组（>=2首；单曲默认隐式独立组）
  static List<SongGroup> getGroups({String? playlistId}) {
    _ensureLoaded();
    return List.unmodifiable(_cache.where((g) => g.songPaths.length >= 2 && (playlistId == null || g.playlistId == playlistId)));
  }

  /// 获取某首歌所在组（无组返回 null，即单曲独立组）
  static SongGroup? groupOf(String filePath, {String? playlistId}) {
    _ensureLoaded();
    for (final g in _cache) {
      if (g.songPaths.contains(filePath) && (playlistId == null || g.playlistId == playlistId)) return g;
    }
    return null;
  }

  /// 组队：把选中歌曲合并为一个组（各自原有组合并后生成新组）
  static void groupSongs(List<String> paths, {required String playlistId}) {
    _ensureLoaded();
    if (paths.length < 2) return;
    final involved = <String>{};
    final toRemove = <String>[];
    for (final g in _cache) {
      if (g.playlistId == playlistId && g.songPaths.any((p) => paths.contains(p))) {
        involved.addAll(g.songPaths);
        toRemove.add(g.id);
      }
    }
    involved.addAll(paths);
    _cache.removeWhere((g) => toRemove.contains(g.id));
    final first = paths.first;
    final title = first.split('\\').last.split('/').last.split('.').first;
    _cache.add(SongGroup(
      id: 'g${DateTime.now().millisecondsSinceEpoch}',
      playlistId: playlistId,
      name: title,
      songPaths: involved.toList(),
    ));
    _save();
  }

  /// 解散组（回到单曲独立组）
  static void ungroup(String groupId) {
    _ensureLoaded();
    _cache.removeWhere((g) => g.id == groupId);
    _save();
  }

  /// 设置组内顺序/随机
  static void setGroupShuffle(String groupId, bool shuffle) {
    _ensureLoaded();
    for (final g in _cache) {
      if (g.id == groupId) { g.shuffle = shuffle; break; }
    }
    _save();
  }

  /// 随机模式下一首：组内没播完先播组内，否则随机跳组（限定当前歌单的组）
  static Song? nextInGroup(String currentFp, List<Song> queue, {String? playlistId}) {
    _ensureLoaded();
    final group = groupOf(currentFp, playlistId: playlistId);
    if (group != null) {
      final curIdx = group.songPaths.indexOf(currentFp);
      if (group.shuffle) {
        if (group.songPaths.length > 1) {
          var n = curIdx;
          while (n == curIdx) n = Random().nextInt(group.songPaths.length);
          return queue.where((s) => s.filePath == group.songPaths[n]).firstOrNull;
        }
      } else if (curIdx < group.songPaths.length - 1) {
        return queue.where((s) => s.filePath == group.songPaths[curIdx + 1]).firstOrNull;
      }
      final groups = getGroups(playlistId: playlistId);
      if (groups.isNotEmpty) {
        var g = groups[Random().nextInt(groups.length)];
        if (g.id == group.id && groups.length > 1) {
          g = groups[(groups.indexOf(g) + 1) % groups.length];
        }
        final first = g.songPaths.first;
        return queue.where((s) => s.filePath == first).firstOrNull;
      }
    }
    return null;
  }
}

// ============================================================
// 本地歌单扫描（兼容旧接口）
// ============================================================
Future<List<Song>> scanLocalAudioFiles(String dirPath) async {
  SongManager.init(dirPath);
  return SongManager.scanLocalSongs();
}
