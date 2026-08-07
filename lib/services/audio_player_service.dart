import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_data.dart';
import 'settings_service.dart';

enum PlayMode { sequential, loopList, loopOne, shuffle }

class AudioPlayerService {
  static final _instance = AudioPlayerService._();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._() {
    _player.onPlayerComplete.listen((_) => next());
    WidgetsBinding.instance.addObserver(_AppObserver(_saveState));
    _player.onDurationChanged.listen((d) {
      if (d.inMilliseconds > 0 && _currentSong != null) {
        SongManager.updateDuration(_currentSong!.filePath, d.inSeconds);
      }
    });
    // 进度轮询
    int _saveCounter = 0;
    Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_currentSong != null && _playing) {
        final p = await _player.getCurrentPosition();
        if (p != null) { _lastPosition = p; _positionController.add(p); }
        _saveCounter++;
        if (_saveCounter % 4 == 0) _saveState(); // 每2秒保存
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  bool _sourceLoaded = false;
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  Duration _lastPosition = Duration.zero;
  bool _playing = false;
  Song? _currentSong;
  final List<Song> _queue = [];
  List<Song>? _orderedQueue;
  String _currentPlaylistId = "";
  String get currentPlaylistId => _currentPlaylistId;
  PlayMode _playMode = PlayMode.loopList;
  int _queueIndex = 0;
  final currentSongNotifier = ValueNotifier<Song?>(null);
  final favoritesChangedNotifier = ValueNotifier<int>(0);

  Song? get currentSong => _currentSong;
  List<Song> get queue => List.unmodifiable(_queue);
  PlayMode get playMode => _playMode;
  bool get isPlaying => _playing;
  Duration get currentPosition => _lastPosition;
  int get queueIndex => _queueIndex;
  Stream<Duration> get onPositionChanged => _positionController.stream;
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  Stream<bool> get onPlayingChanged => _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  // ==================== 播放 ====================

  Future<void> playSong(Song song, {bool forceRestart = false}) async {
    final idx = _queue.indexWhere((s) => (s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)) == (song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath)));
    if (idx >= 0) _queueIndex = idx;
    if (_currentSong?.filePath == song.filePath && !forceRestart) {
      if (_playing) { _player.pause(); _playing = false; } else {
        if (!_sourceLoaded) {
          await _player.play(DeviceFileSource(song.filePath), position: _lastPosition > Duration.zero ? _lastPosition : null);
          _sourceLoaded = true;
        } else {
          await _player.play(DeviceFileSource(song.filePath), position: _lastPosition > Duration.zero ? _lastPosition : null);
        }
        _playing = true;
      }
      return;
    }
    _lastPosition = Duration.zero;
    _currentSong = song;
    currentSongNotifier.value = song;
    await _player.stop();
    await _player.play(DeviceFileSource(song.filePath));
    _sourceLoaded = true;
    _playing = true;
    // 新歌：清除上次位置，避免残留影响
    _lastPosition = Duration.zero;
    _saveState();
    RecentlyPlayedService.addIfNotExists(song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath)).catchError((_) {});
  }

  void togglePause() async {
    if (_playing) {
      final p = await _player.getCurrentPosition();
      if (p != null) _lastPosition = p;
      _player.pause();
      _playing = false;
    } else {
      if (!_sourceLoaded && _currentSong != null) {
        await _player.play(DeviceFileSource(_currentSong!.filePath), position: _lastPosition > Duration.zero ? _lastPosition : null);
        _sourceLoaded = true;
      } else {
        if (_lastPosition > Duration.zero && _currentSong != null) {
          final cur = await _player.getCurrentPosition();
          if (cur == null || cur == Duration.zero) await _player.seek(_lastPosition);
        }
        _player.resume();
      }
      _playing = true;
    }
    _saveState();
    currentSongNotifier.notifyListeners(); // 强制刷新UI
  }

  void resume() { _player.resume(); _playing = true; }

  Future<void> seek(Duration p) async {
    _lastPosition = p;
    _positionController.add(p);
    await _player.seek(p);
    _saveState();
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_playMode == PlayMode.loopOne) { await seek(Duration.zero); return; }
    if (_playMode == PlayMode.shuffle) {
      final curFp = _currentSong?.filePath;
      if (curFp != null) {
        final cur = _currentSong;
        final ns = cur != null ? SongGroupService.nextInGroup(cur, _queue, playlistId: _currentPlaylistId.isEmpty ? null : _currentPlaylistId) : null;
        if (ns != null) { await playSong(ns); return; }
      }
      _queueIndex = Random().nextInt(_queue.length);
      await playSong(_queue[_queueIndex]);
      return;
    }
    _queueIndex = (_queueIndex + 1) % _queue.length;
    await playSong(_queue[_queueIndex]);
  }

  Future<void> prev() async {
    if (_queue.isEmpty) return;
    final pos = await _player.getCurrentPosition();
    if (pos != null && pos.inSeconds > 3) { await _player.seek(Duration.zero); return; }
    _queueIndex = (_queueIndex - 1 + _queue.length) % _queue.length;
    await playSong(_queue[_queueIndex]);
  }

  // ==================== 队列 ====================
  void setQueue(List<Song> s, {int startIndex = 0, String? playlistId}) {
    if (playlistId != null) _currentPlaylistId = playlistId;
    final curKey = s.isNotEmpty && startIndex >= 0 && startIndex < s.length
        ? (s[startIndex].bvid.isNotEmpty ? s[startIndex].bvid : _fileNameKey(s[startIndex].filePath))
        : null;
    _queue.clear();
    _queue.addAll(_playMode == PlayMode.shuffle ? _shuffleGroups(s) : _groupedQueue(s));
    _queueIndex = _queue.isEmpty
        ? 0
        : (curKey != null
            ? _queue.indexWhere((x) => (x.bvid.isNotEmpty ? x.bvid : _fileNameKey(x.filePath)) == curKey)
            : startIndex.clamp(0, _queue.length - 1));
    if (_queueIndex < 0) _queueIndex = 0;
    currentSongNotifier.notifyListeners();
  }
  void addToQueue(Song s) { _queue.add(s); currentSongNotifier.notifyListeners(); }
  void removeFromQueue(int i) { if (i >= _queue.length) return; _queue.removeAt(i); if (i < _queueIndex) _queueIndex--; if (_queueIndex >= _queue.length) _queueIndex = (_queue.length - 1).clamp(0, 999); currentSongNotifier.notifyListeners(); }
  void setPlayMode(PlayMode m) {
    if (m == PlayMode.shuffle && _playMode != PlayMode.shuffle) {
      _orderedQueue = List<Song>.from(_queue);
      final curKey = _currentSong != null ? (_currentSong!.bvid.isNotEmpty ? _currentSong!.bvid : _fileNameKey(_currentSong!.filePath)) : null;
      final grouped = _shuffleGroups(_orderedQueue!);
      _queue.clear();
      _queue.addAll(grouped);
      _queueIndex = curKey != null ? _queue.indexWhere((x) => (x.bvid.isNotEmpty ? x.bvid : _fileNameKey(x.filePath)) == curKey) : 0;
      if (_queueIndex < 0) _queueIndex = 0;
    } else if (_playMode == PlayMode.shuffle && m != PlayMode.shuffle && _orderedQueue != null) {
      final curKey = _currentSong != null ? (_currentSong!.bvid.isNotEmpty ? _currentSong!.bvid : _fileNameKey(_currentSong!.filePath)) : null;
      final restored = List<Song>.from(_orderedQueue!);
      _queue.clear();
      _queue.addAll(restored);
      _orderedQueue = null;
      _queueIndex = curKey != null ? _queue.indexWhere((x) => (x.bvid.isNotEmpty ? x.bvid : _fileNameKey(x.filePath)) == curKey) : 0;
      if (_queueIndex < 0) _queueIndex = 0;
    }
    _playMode = m;
    _saveMode();
    _saveState();
    currentSongNotifier.notifyListeners();
  }

  /// 组单元随机：组和单曲作为整体打乱，组内保持组队顺序（组内随机由组设置控制）
  List<Song> _shuffleGroups(List<Song> q) {
    final groups = SongGroupService.getGroups(playlistId: _currentPlaylistId.isEmpty ? null : _currentPlaylistId);
    final units = <List<Song>>[];
    final used = <String>{};
    for (final g in groups) {
      final members = g.songPaths
          .map((p) => q.where((s) => (s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)) == p).firstOrNull)
          .whereType<Song>()
          .toList();
      if (members.isEmpty) continue;
      if (g.shuffle && members.length > 1) {
        members.shuffle(Random());
      }
      units.add(members);
      for (final s in members) used.add(_fileNameKey(s.filePath));
    }
    for (final s in q) {
      if (!used.contains(_fileNameKey(s.filePath))) units.add([s]);
    }
    units.shuffle(Random());
    final result = <Song>[];
    for (final u in units) result.addAll(u);
    return result;
  }

  /// 按组重排：组内歌曲相邻且保持在歌单中的相对位置（不提前），单曲原位
  List<Song> _groupedQueue(List<Song> q) {
    final groups = SongGroupService.getGroups(playlistId: _currentPlaylistId.isEmpty ? null : _currentPlaylistId);
    final result = <Song>[];
    final used = <String>{};
    for (final s in q) {
      if (used.contains(_fileNameKey(s.filePath))) continue;
      // 若当前歌属于某组，输出整个组（相邻），组内按组配置
      final g = groups.where((g) => g.songPaths.contains(s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath))).firstOrNull;
      if (g != null) {
        var members = g.songPaths
            .map((p) => q.where((x) => (x.bvid.isNotEmpty ? x.bvid : _fileNameKey(x.filePath)) == p).firstOrNull)
            .whereType<Song>()
            .toList();
        if (g.shuffle && members.length > 1) members.shuffle(Random());
        for (final m in members) {
          if (used.add(_fileNameKey(m.filePath))) result.add(m);
        }
      } else {
        used.add(_fileNameKey(s.filePath));
        result.add(s);
      }
    }
    return result;
  }
  String get playModeLabel { switch (_playMode) { case PlayMode.sequential: return '顺序播放'; case PlayMode.loopList: return '列表循环'; case PlayMode.loopOne: return '单曲循环'; case PlayMode.shuffle: return '随机播放'; }}

  // ==================== 收藏 ====================
  static const _favKey = 'favorites';
  static Future<List<String>> getFavorites() async {
    final p = await SharedPreferences.getInstance();
    final list = p.getStringList(_favKey) ?? [];
    // 迁移旧数据：filePath 条目转成文件名键（BV号）
    final migrated = list.map((e) {
      if (e.contains('\\') || e.contains('/')) {
        final name = e.split('\\').last.split('/').last;
        final dot = name.lastIndexOf('.');
        return dot > 0 ? name.substring(0, dot) : name;
      }
      return e;
    }).toList();
    if (migrated.join('|') != list.join('|')) await p.setStringList(_favKey, migrated);
    return migrated;
  }
  static Future<void> toggleFavorite(Song song) async {
    final key = song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath);
    final p = await SharedPreferences.getInstance();
    final list = List<String>.from(p.getStringList(_favKey) ?? []);
    final idx = list.indexOf(key);
    if (idx >= 0) { list.removeAt(idx); } else { list.add(key); }
    await p.setStringList(_favKey, list);
    _instance.favoritesChangedNotifier.value++;
  }

  /// 文件名（不含扩展名）作为无BV号歌曲的键
  static String _fileNameKey(String fp) {
    final name = fp.split('\\').last.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
  static Future<bool> isFavorite(String fp) async { final f = await getFavorites(); return f.contains(fp); }

  // ==================== 持久化 ====================
  void _saveState() {
    if (_currentSong == null) return;
    try {
      final state = <String, dynamic>{
        'song': _currentSong!.bvid.isNotEmpty ? _currentSong!.bvid : _fileNameKey(_currentSong!.filePath),
        'title': _currentSong!.title,
        'uploader': _currentSong!.uploader,
        'duration': _currentSong!.duration.inSeconds,
        'bvid': _currentSong!.bvid.isNotEmpty ? _currentSong!.bvid : _currentSong!.filePath.split('\\').last.split('/').last.split('.').first,
        'cover': _currentSong!.coverUrl ?? '',
        'position': _lastPosition.inMilliseconds,
        'queue': _queue.map((s) => s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)).toList(),
        'queue_index': _queueIndex,
      };
      File('save_state.json').writeAsStringSync(jsonEncode(state));
    } catch (_) {}
  }
  Future<void> _saveMode() async { final p = await SharedPreferences.getInstance(); await p.setInt('play_mode', _playMode.index); }
  Future<Song?> restoreLastSong() async {
    try {
      final f = File('save_state.json');
      if (!f.existsSync()) return null;
      final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final sm = data['mode'] as int?;
      if (sm != null && sm < PlayMode.values.length) _playMode = PlayMode.values[sm];
      _lastPosition = Duration(milliseconds: data['position'] as int? ?? 0);
      final qPaths = List<dynamic>.from(data['queue'] as List? ?? []);
      final qIdx = data['queue_index'] as int? ?? 0;
      if (qPaths.isNotEmpty) {
        _queue.clear();
        for (final q in qPaths) {
          if (q is Map) {
            // 旧格式：p=filePath
            final fp = q['p'] as String? ?? '';
            final bv = fp.split('\\').last.split('/').last.split('.').first;
            final t = q['t'] as String? ?? '';
            _queue.add(Song(id: bv, title: t.isNotEmpty ? t : bv, uploader: q['u'] as String? ?? '', duration: Duration.zero, filePath: fp, bvid: bv, coverUrl: (q['c'] as String? ?? '').isNotEmpty ? q['c'] as String : null));
          } else {
            // 新格式：纯 bvid，信息由对照表补全
            final bv = q.toString();
            _queue.add(Song(id: bv, title: bv, uploader: '', duration: Duration.zero, filePath: '', bvid: bv));
          }
        }
        _queueIndex = qIdx.clamp(0, _queue.length - 1);
      }
      final fp0 = data['song'] as String? ?? '';
      final bv0 = (data['bvid'] as String? ?? '').isNotEmpty
          ? data['bvid'] as String
          : (fp0.isNotEmpty ? fp0.split('\\').last.split('/').last.split('.').first : '');
      final song = Song(
        id: bv0,
        title: data['title'] as String? ?? '',
        uploader: data['uploader'] as String? ?? '',
        duration: Duration(seconds: data['duration'] as int? ?? 0),
        filePath: fp0,
        bvid: bv0,
        coverUrl: (data['cover'] as String? ?? '').isNotEmpty ? data['cover'] as String? : null,
      );
      _currentSong = song;
      currentSongNotifier.value = song;
      // 从对照表补全封面/标题/上传者（有BV号即可查全）
      try {
        final svc = await SettingsService.getInstance();
        final dir = await svc.getDownloadPath();
        final local = await scanLocalAudioFiles(dir);
        final byKey = {for (final s in local) if (s.bvid.isNotEmpty) s.bvid: s, for (final s in local) if (s.bvid.isEmpty) _fileNameKey(s.filePath): s};
        for (var i = 0; i < _queue.length; i++) {
          final k = _queue[i].bvid.isNotEmpty ? _queue[i].bvid : _fileNameKey(_queue[i].filePath);
          final full = byKey[k];
          if (full != null) _queue[i] = full;
        }
        final curK = _currentSong != null ? (_currentSong!.bvid.isNotEmpty ? _currentSong!.bvid : _fileNameKey(_currentSong!.filePath)) : null;
        final curFull = curK != null ? byKey[curK] : null;
        if (curFull != null) {
          _currentSong = curFull;
          currentSongNotifier.value = curFull;
        }
      } catch (_) {}
      return song;
    } catch (_) {
      return null;
    }
  }
}


class _AppObserver extends WidgetsBindingObserver {
  final void Function() onPause;
  _AppObserver(this.onPause);
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      onPause();
    }
  }
}