import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 歌曲数据模型
class Song {
  final String id;
  final String title;
  final String uploader;
  final Duration duration;
  final String? coverUrl;
  final bool hasVideo;
  final String? videoPath;
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
    this.videoPath,
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

  /// 本地歌单的拖动排序（BV号列表）；未拖动过时按添加顺序（mtime 倒序）
  static const _localOrderKey = 'local_playlist_order';

  static Future<List<String>> getLocalOrder() async {
    final p = await SharedPreferences.getInstance();
    return p.getStringList(_localOrderKey) ?? [];
  }

  static Future<void> saveLocalOrder(List<String> bvids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_localOrderKey, bvids);
  }

  static Future<void> init(String dir) async {
    _downloadDir = dir;
  }

  static String get _mapPath => '$_downloadDir${Platform.pathSeparator}metadata_map.json';

  /// 归一化路径作为 map key：统一分隔符（Windows 反斜杠 / Android 正斜杠）+ 绝对路径。
  /// 历史数据（下载时 `'$dir/$name.m4a'` 拼出混合分隔符）会导致与扫描路径 key 不匹配，
  /// 标题查不到后回退成文件名（BV号）。
  static String _normKey(String path) {
    final norm = path.replaceAll('\\', Platform.pathSeparator).replaceAll('/', Platform.pathSeparator);
    return File(norm).absolute.path;
  }

  /// 读取全部元数据（key 归一化，历史混合分隔符数据自动迁移）
  static Map<String, dynamic> _readMap() {
    final f = File(_mapPath);
    if (!f.existsSync()) return {};
    try {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final normalized = <String, dynamic>{};
      var changed = false;
      raw.forEach((k, v) {
        final nk = _normKey(k);
        normalized[nk] = v;
        if (nk != k) changed = true;
      });
      if (changed) File(_mapPath).writeAsStringSync(jsonEncode(normalized));
      return normalized;
    } catch (_) {
      return {};
    }
  }

  /// 写入元数据
  static void _writeMap(Map<String, dynamic> map) {
    File(_mapPath).writeAsStringSync(jsonEncode(map));
  }

  /// 下载完全成功后登记歌曲（唯一的元数据管理文件：音频/视频/封面）
  static void registerSong({
    required String filePath,
    required String title,
    required String uploader,
    required int durationSec,
    required String bvid,
    required String url,
    String? coverPath,
    String? videoPath,
  }) {
    final map = _readMap();
    map[_normKey(filePath)] = {
      'title': title,
      'uploader': uploader,
      'duration': durationSec,
      'bvid': bvid,
      'url': url,
      'coverPath': coverPath ?? '',
      'videoPath': videoPath ?? '',
    };
    _writeMap(map);
  }

  /// 单独登记/更新视频路径（视频下载完成后调用）
  static void registerVideoPath(String filePath, String videoPath) {
    final map = _readMap();
    final m = map[_normKey(filePath)] as Map<String, dynamic>?;
    if (m != null) {
      m['videoPath'] = videoPath;
      _writeMap(map);
    }
  }

  /// 播放时更新时长（唯一元数据文件）
  static void updateDuration(String filePath, int seconds) {
    final map = _readMap();
    final m = map[_normKey(filePath)] as Map<String, dynamic>?;
    if (m != null) {
      m['duration'] = seconds;
      _writeMap(map);
    }
  }

  /// 是否已登记（按 bvid 查）
  static bool isRegistered(String bvid) {
    final map = _readMap();
    for (final v in map.values) {
      if (v is Map && v['bvid'] == bvid) return true;
    }
    return false;
  }

  /// 删除歌曲登记
  static void unregisterSong(String filePath) {
    final map = _readMap();
    map.remove(_normKey(filePath));
    _writeMap(map);
  }

  /// 扫描本地文件，返回 Song 列表
  static List<Song> scanLocalSongs() {
    try {
      File('$_downloadDir/debug.log').writeAsStringSync('[${DateTime.now().toIso8601String().substring(11, 19)}] scan dir=$_downloadDir exists=${_downloadDir != null ? Directory(_downloadDir!).existsSync() : false}\n', mode: FileMode.append);
    } catch (_) {}
    if (_downloadDir == null) return [];
    final dir = Directory(_downloadDir!);
    if (!dir.existsSync()) return [];

    final map = _readMap();
    final songs = <Song>[];
    // 预收集 m4a 文件名：mp4 仅在无对应 m4a 时作为主文件（避免同歌双条目）
    final m4aNames = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.m4a'))
        .map((f) => f.path.split(Platform.pathSeparator).last)
        .toSet();
    for (final f in dir.listSync()) {
      if (f is File) {
        // 跳过缓存区（.tmp 目录）与 .part 下载中文件
        if (f.path.contains('${Platform.pathSeparator}.tmp${Platform.pathSeparator}') || f.path.endsWith('.part')) continue;
        final ext = f.path.split('.').last.toLowerCase();
        final isAudio = ext == 'm4a' || ext == 'mp3' || ext == 'aac' || ext == 'flac' || ext == 'wav';
        // 纯视频（mp4 主文件）不进音频歌单：视频列表由 video_page 单独扫描 mp4
        if (isAudio) {
          // 从注册表查元数据：先按路径，路径不一致时按 BV号 兜底（bvid 唯一键）
          var meta = map[_normKey(f.absolute.path)] as Map<String, dynamic>?;
          final fname = f.path.split(Platform.pathSeparator).last;
          final bvMatch = RegExp(r'^BV\w{10}').firstMatch(fname);
          String? fbv;
          if (meta == null && bvMatch != null) {
            fbv = bvMatch.group(0);
            for (final v in map.values) {
              if (v is Map && v['bvid'] == fbv) { meta = Map<String, dynamic>.from(v); break; }
            }
          }
          // 跳过下载残留：BV 格式命名、路径和 bvid 都查不到的 m4a（下载中断窗口期产物）
          if (bvMatch != null && meta == null) continue;
          final title = meta?['title'] as String? ?? f.path.split(Platform.pathSeparator).last.split('.').first;
          final uploader = meta?['uploader'] as String? ?? '';
          final duration = Duration(seconds: meta?['duration'] as int? ?? 0);
          final bvid = meta?['bvid'] as String? ?? '';
          final url = meta?['url'] as String? ?? '';
          final coverPath = meta?['coverPath'] as String? ?? '';
          final videoPath = meta?['videoPath'] as String? ?? '';
          // 检查封面文件是否存在
          String? cover;
          if (coverPath.isNotEmpty && File(coverPath).existsSync()) {
            cover = coverPath;
          }
          // 检查视频文件是否存在
          String? video;
          if (videoPath.isNotEmpty && File(videoPath).existsSync()) {
            video = videoPath;
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
            hasVideo: video != null,
            videoPath: video,
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

  /// 只记录 BV号（其他信息从对照表查）
  static Future<void> addIfNotExists(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.remove(key);
    list.insert(0, key);
    if (list.length > 1000) list.removeRange(1000, list.length);
    await prefs.setStringList(_key, list);
  }

  /// 从最近播放记录移除
  static Future<void> removeBvid(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.remove(key);
    await prefs.setStringList(_key, list);
  }

  /// 移除某首歌的播放记录
  static Future<void> removeSong(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.remove(key);
    // 兼容旧格式（含分隔符的记录也删）
    list.removeWhere((e) => e.startsWith('$key|'));
    await prefs.setStringList(_key, list);
  }

  /// 返回 BV号列表（按最近播放时间倒序；自动迁移旧格式数据）
  static Future<List<String>> getRecentBvids() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    final valid = <String>[];
    for (final e in list) {
      if (!e.contains('|')) { valid.add(e); continue; }
      // 旧格式：BV号|title|uploader|... 取第一个字段（BV号）
      final parts = e.split('|');
      if (parts.isNotEmpty && parts[0].isNotEmpty) valid.add(parts[0]);
    }
    await prefs.setStringList(_key, valid);
    return valid;
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
      // 迁移旧数据：filePath 条目转为 bvid（文件名）
      final bvids = songPaths.map((p) {
        if (p.contains('\\') || p.contains('/')) {
          final name = p.split('\\').last.split('/').last;
          final dot = name.lastIndexOf('.');
          return dot > 0 ? name.substring(0, dot) : name;
        }
        return p;
      }).toList();
      result.add(Playlist(id: parts[0], name: parts[1], icon: parts[2],
        songs: bvids.map((bv) => Song(id: bv, title: bv, uploader: '', duration: Duration.zero, filePath: '', bvid: bv)).toList(),
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

  static Future<void> addSongToPlaylist(String pid, String bvid) =>
      addSongsToPlaylist(pid, [bvid]);

  /// 批量添加（按 BV号）：新歌曲保持传入顺序，整体插到歌单最前面；旧歌曲去重后保持原顺序在后
  static Future<void> addSongsToPlaylist(String pid, List<String> newBvids) async {
    if (newBvids.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (var i = 0; i < list.length; i++) {
      var parts = list[i].split('|||');
      while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
      while (parts.length < 4) parts.add('');
      if (parts[0] == pid) {
        List<String> oldBvids = [];
        try { oldBvids = (jsonDecode(parts[3]) as List).map((x) => x.toString()).where((x) => x.isNotEmpty).toList(); }
        catch (_) { oldBvids = parts[3].split(',').where((s) => s.isNotEmpty).toList(); }
        // 迁移旧格式条目（filePath → bvid）
        oldBvids = oldBvids.map((p) {
          if (p.contains('\\') || p.contains('/')) {
            final name = p.split('\\').last.split('/').last;
            final dot = name.lastIndexOf('.');
            return dot > 0 ? name.substring(0, dot) : name;
          }
          return p;
        }).toList();
        final newSet = newBvids.toSet();
        final oldFiltered = oldBvids.where((x) => !newSet.contains(x)).toList();
        parts[3] = jsonEncode([...newBvids, ...oldFiltered]);
        while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
        list[i] = parts.join('|||');
        await p.setStringList(_key, list);
        return;
      }
    }
  }

  static Future<bool> isSongInPlaylist(String pid, String bvid) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (final entry in list) {
      final parts = entry.split('|||');
      if (parts[0] == pid) {
        final songsJson = parts.length > 3 ? parts[3] : '[]';
        try { return (jsonDecode(songsJson) as List).map((x) => x.toString()).contains(bvid); }
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

  /// 从歌单移除歌曲（兼容旧数据 filePath 条目）
  /// 重排歌单内歌曲顺序（按 BV号），持久化
  static Future<void> reorderSongsInPlaylist(String pid, List<String> newBvids) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (var i = 0; i < list.length; i++) {
      var parts = list[i].split('|||');
      while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
      while (parts.length < 4) parts.add('');
      if (parts[0] == pid) {
        parts[3] = jsonEncode(newBvids);
        while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
        list[i] = parts.join('|||');
        await p.setStringList(_key, list);
        return;
      }
    }
  }

  static Future<void> removeSongFromPlaylist(String pid, String bvid) async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_key) ?? [];
    for (var i = 0; i < list.length; i++) {
      var parts = list[i].split('|||');
      while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
      while (parts.length < 4) parts.add('');
      if (parts[0] == pid) {
        List<String> paths = [];
        try { paths = (jsonDecode(parts[3]) as List).map((x) => x.toString()).where((x) => x.isNotEmpty).toList(); }
        catch (_) { paths = parts[3].split(',').where((s) => s.isNotEmpty).toList(); }
        // 迁移旧格式：filePath 条目转成 bvid 后比较
        final before = paths.length;
        paths.removeWhere((x) {
          var k = x;
          if (k.contains('\\') || k.contains('/')) {
            final name = k.split('\\').last.split('/').last;
            final dot = name.lastIndexOf('.');
            k = dot > 0 ? name.substring(0, dot) : name;
          }
          return k == bvid;
        });
        // 仅在确实删除了条目时才写回，避免无谓重写损坏数据
        if (paths.length != before) {
          parts[3] = jsonEncode(paths);
          while (parts.length > 3 && parts.last.isEmpty) parts.removeLast();
          list[i] = parts.join('|||');
          await p.setStringList(_key, list);
        }
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
  static SharedPreferences? _prefs;

  /// 启动时初始化（main 调用）：加载存储（优先 SharedPreferences，旧文件自动迁移）
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    _ensureLoaded();
  }

  /// 重置缓存（仅测试用）
  @visibleForTesting
  static void resetForTest() {
    _cache = [];
    _loaded = false;
  }

  static void _ensureLoaded() {
    if (_loaded) return;
    try {
      String? raw;
      if (_prefs != null) raw = _prefs!.getString(_key);
      if (raw == null) {
        // 旧版文件存储迁移（song_groups.json 在私有目录，重装会丢）
        final f = File('song_groups.json');
        if (f.existsSync()) {
          raw = f.readAsStringSync();
          try { f.deleteSync(); } catch (_) {}
        }
      }
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as List;
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
        _persist(); // 迁移后写入新存储
      }
      _loaded = true;
    } catch (_) {
      _loaded = true;
    }
  }

  static void _save() {
    _persist();
  }

  static void _persist() {
    try {
      final raw = jsonEncode(_cache.map((g) => {
        'id': g.id, 'pl': g.playlistId, 'name': g.name, 'paths': g.songPaths, 'shuffle': g.shuffle,
      }).toList());
      _prefs?.setString(_key, raw); // setString 立即更新内存缓存，异步落盘
      // 兜底：私有目录也写一份（_prefs 未初始化时回退读取）
      try { File('song_groups.json').writeAsStringSync(raw); } catch (_) {}
    } catch (_) {}
  }

  /// 获取某歌单的组（>=2首；单曲默认隐式独立组）
  static List<SongGroup> getGroups({String? playlistId}) {
    _ensureLoaded();
    return List.unmodifiable(_cache.where((g) => g.songPaths.length >= 2 && (playlistId == null || g.playlistId == playlistId)));
  }

  /// 获取某首歌所在组（无组返回 null，即单曲独立组）
  static SongGroup? groupOf(Song song, {String? playlistId}) {
    _ensureLoaded();
    final key = song.bvid.isNotEmpty ? song.bvid : song.filePath.split("\\").last.split("/").last.split(".").first;
    for (final g in _cache) {
      if (g.songPaths.contains(key) && (playlistId == null || g.playlistId == playlistId)) return g;
    }
    return null;
  }

  /// 清理缺失歌曲：从所有组中移除本地不存在的歌，不足2首的组解散
  static void removeMissing(Set<String> existing) {
    _ensureLoaded();
    final before = _cache.length;
    for (final g in _cache) {
      g.songPaths.removeWhere((p) => !existing.contains(p));
    }
    _cache.removeWhere((g) => g.songPaths.length < 2);
    if (_cache.length != before) _save();
  }

  /// 组队：把选中歌曲合并为一个组（各自原有组合并后生成新组）
  static void groupSongs(List<Song> songs, {required String playlistId}) {
    _ensureLoaded();
    if (songs.length < 2) return;
    final paths = songs.map((s) => s.bvid.isNotEmpty ? s.bvid : s.filePath.split("\\").last.split("/").last.split(".").first).toList();
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
    final first = songs.first;
    _cache.add(SongGroup(
      id: 'g${DateTime.now().millisecondsSinceEpoch}',
      playlistId: playlistId,
      name: first.title.isNotEmpty ? first.title : first.filePath.split('\\').last.split('/').last.split('.').first,
      songPaths: involved.toList(),
    ));
    _save();
  }

  /// 从所有组中移除歌曲（成员少于2时自动解散组）
  static void removeSongFromGroups(String key) {
    _ensureLoaded();
    for (final g in List<SongGroup>.from(_cache)) {
      if (g.songPaths.remove(key)) {
        if (g.songPaths.length < 2) _cache.remove(g);
      }
    }
    _save();
  }

  /// 解散组（回到单曲独立组）
  static void ungroup(String groupId) {
    _ensureLoaded();
    _cache.removeWhere((g) => g.id == groupId);
    _save();
  }

  /// 设置组内顺序/随机（只改设置，不影响当前歌单/播放顺序；下次播放顺序调整时生效）
  static void setGroupShuffle(String groupId, bool shuffle) {
    _ensureLoaded();
    for (final g in _cache) {
      if (g.id == groupId) { g.shuffle = shuffle; break; }
    }
    _save();
  }

  /// 随机模式下一首：组内没播完先播组内，否则随机跳组（限定当前歌单的组）
  static Song? nextInGroup(Song currentSong, List<Song> queue, {String? playlistId}) {
    _ensureLoaded();
    final group = groupOf(currentSong, playlistId: playlistId);
    final curKey = currentSong.bvid.isNotEmpty ? currentSong.bvid : currentSong.filePath.split("\\").last.split("/").last.split(".").first;
    if (group != null) {
      final curIdx = group.songPaths.indexOf(curKey);
      if (group.shuffle) {
        if (group.songPaths.length > 1) {
          var n = curIdx;
          while (n == curIdx) n = Random().nextInt(group.songPaths.length);
          return queue.where((s) => (s.bvid.isNotEmpty ? s.bvid : s.filePath.split("\\").last.split("/").last.split(".").first) == group.songPaths[n]).firstOrNull;
        }
      } else if (curIdx < group.songPaths.length - 1) {
        return queue.where((s) => (s.bvid.isNotEmpty ? s.bvid : s.filePath.split("\\").last.split("/").last.split(".").first) == group.songPaths[curIdx + 1]).firstOrNull;
      }
      final groups = getGroups(playlistId: playlistId);
      if (groups.isNotEmpty) {
        var g = groups[Random().nextInt(groups.length)];
        if (g.id == group.id && groups.length > 1) {
          g = groups[(groups.indexOf(g) + 1) % groups.length];
        }
        final first = g.songPaths.first;
        return queue.where((s) => (s.bvid.isNotEmpty ? s.bvid : s.filePath.split("\\").last.split("/").last.split(".").first) == first).firstOrNull;
      }
    }
    return null;
  }
}

// ============================================================
// 本地歌单扫描（兼容旧接口）
// ============================================================
/// 清理所有歌单/收藏/最近播放/组中已不存在的歌曲记录
Future<void> purgeMissingSongs(Set<String> existing) async {
  final p = await SharedPreferences.getInstance();
  // 我喜欢
  final fav = (p.getStringList('favorites') ?? []).where(existing.contains).toList();
  await p.setStringList('favorites', fav);
  // 最近播放
  final rec = (p.getStringList('recently_played') ?? []).where(existing.contains).toList();
  await p.setStringList('recently_played', rec);
  // 自定义歌单
  final pls = p.getStringList('custom_playlists') ?? [];
  var changed = false;
  for (var i = 0; i < pls.length; i++) {
    final parts = pls[i].split('|||');
    List<dynamic> paths = [];
    try { paths = jsonDecode(parts.length > 3 ? parts[3] : '[]'); } catch (_) {}
    final kept = paths.where((x) => existing.contains(x.toString())).toList();
    if (kept.length != paths.length) {
      parts[3] = jsonEncode(kept);
      pls[i] = parts.join('|||');
      changed = true;
    }
  }
  if (changed) await p.setStringList('custom_playlists', pls);
  // 组
  SongGroupService.removeMissing(existing);
}

Future<List<Song>> scanLocalAudioFiles(String dirPath) async {
  SongManager.init(dirPath);
  final songs = SongManager.scanLocalSongs();
  // 扫描后净化：本地不存在的歌从所有歌单/收藏/最近播放/组中清除
  final existing = songs.map((s) => s.bvid.isNotEmpty ? s.bvid : s.filePath.replaceAll('\\', '/').split('/').last.split('.').first).toSet();
  purgeMissingSongs(existing);
  return songs;
}
