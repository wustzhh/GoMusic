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
        _writeMeta(_currentSong!, d);
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
    final idx = _queue.indexWhere((s) => s.filePath == song.filePath);
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
    RecentlyPlayedService.addIfNotExists(song.filePath, song.title, song.uploader, song.duration.inSeconds, song.filePath, song.coverUrl ?? '').catchError((_) {});
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
        final ns = SongGroupService.nextInGroup(curFp, _queue, playlistId: _currentPlaylistId.isEmpty ? null : _currentPlaylistId);
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
    _queue.clear();
    _queue.addAll(s);
    _queueIndex = startIndex.clamp(0, _queue.length - 1);
    if (_playMode == PlayMode.shuffle) {
      final curFp = _queue.isNotEmpty ? _queue[_queueIndex].filePath : null;
      _orderedQueue = List<Song>.from(_queue);
      final grouped = _groupedQueue(_orderedQueue!);
      _queue.clear();
      _queue.addAll(grouped);
      _queueIndex = curFp != null ? _queue.indexWhere((x) => x.filePath == curFp) : 0;
      if (_queueIndex < 0) _queueIndex = 0;
    }
    currentSongNotifier.notifyListeners();
  }
  void addToQueue(Song s) { _queue.add(s); currentSongNotifier.notifyListeners(); }
  void removeFromQueue(int i) { if (i >= _queue.length) return; _queue.removeAt(i); if (i < _queueIndex) _queueIndex--; if (_queueIndex >= _queue.length) _queueIndex = (_queue.length - 1).clamp(0, 999); currentSongNotifier.notifyListeners(); }
  void setPlayMode(PlayMode m) {
    if (m == PlayMode.shuffle && _playMode != PlayMode.shuffle) {
      _orderedQueue = List<Song>.from(_queue);
      final curFp = _currentSong?.filePath;
      _queue.clear();
      _queue.addAll(_groupedQueue(_orderedQueue!));
      _queueIndex = _queue.indexWhere((s) => s.filePath == curFp);
      if (_queueIndex < 0) _queueIndex = 0;
    } else if (_playMode == PlayMode.shuffle && m != PlayMode.shuffle && _orderedQueue != null) {
      final curFp = _currentSong?.filePath;
      _queue.clear();
      _queue.addAll(_orderedQueue!);
      _orderedQueue = null;
      _queueIndex = _queue.indexWhere((s) => s.filePath == curFp);
      if (_queueIndex < 0) _queueIndex = 0;
    }
    _playMode = m;
    _saveMode();
    _saveState();
    currentSongNotifier.notifyListeners();
  }

  /// 按组重排：多歌组优先（组内按组配置顺序/随机），单曲在后
  List<Song> _groupedQueue(List<Song> q) {
    final groups = SongGroupService.getGroups(playlistId: _currentPlaylistId.isEmpty ? null : _currentPlaylistId);
    final result = <Song>[];
    final used = <String>{};
    for (final g in groups) {
      var paths = g.songPaths;
      if (g.shuffle && paths.length > 1) {
        paths = List.from(paths)..shuffle(Random());
      }
      for (final p in paths) {
        final s = q.where((x) => x.filePath == p).firstOrNull;
        if (s != null && used.add(s.filePath)) result.add(s);
      }
    }
    for (final s in q) { if (used.add(s.filePath)) result.add(s); }
    return result;
  }
  String get playModeLabel { switch (_playMode) { case PlayMode.sequential: return '顺序播放'; case PlayMode.loopList: return '列表循环'; case PlayMode.loopOne: return '单曲循环'; case PlayMode.shuffle: return '随机播放'; }}

  // ==================== 收藏 ====================
  static const _favKey = 'favorites';
  static Future<List<String>> getFavorites() async { final p = await SharedPreferences.getInstance(); return p.getStringList(_favKey) ?? []; }
  static Future<void> toggleFavorite(String fp) async {
    final p = await SharedPreferences.getInstance();
    final list = List<String>.from(p.getStringList(_favKey) ?? []);
    final idx = list.indexOf(fp);
    if (idx >= 0) { list.removeAt(idx); } else { list.add(fp); }
    await p.setStringList(_favKey, list);
    _instance.favoritesChangedNotifier.value++;
  }
  static Future<bool> isFavorite(String fp) async { final f = await getFavorites(); return f.contains(fp); }

  // ==================== 持久化 ====================
  void _saveState() {
    if (_currentSong == null) return;
    try {
      final state = <String, dynamic>{
        'song': _currentSong!.filePath,
        'title': _currentSong!.title,
        'uploader': _currentSong!.uploader,
        'duration': _currentSong!.duration.inSeconds,
        'bvid': _currentSong!.bvid,
        'cover': _currentSong!.coverUrl ?? '',
        'position': _lastPosition.inMilliseconds,
        'queue': _queue.map((s) => {'p': s.filePath, 't': s.title, 'u': s.uploader, 'c': s.coverUrl ?? ''}).toList(),
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
          final fp = q is Map ? q['p'] as String? ?? '' : q.toString();
          final t = q is Map ? q['t'] as String? ?? '' : '';
          final u = q is Map ? q['u'] as String? ?? '' : '';
          _queue.add(Song(id: 'restored', title: t.isNotEmpty ? t : fp.split('\\').last.split('/').last.split('.').first, uploader: u, duration: Duration.zero, filePath: fp, bvid: fp.split('\\').last.split('/').last.split('.').first));
        }
        _queueIndex = qIdx.clamp(0, _queue.length - 1);
      }
      final fp0 = data['song'] as String? ?? '';
      final bv0 = (data['bvid'] as String? ?? '').isNotEmpty
          ? data['bvid'] as String
          : fp0.split('\\').last.split('/').last.split('.').first;
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
        final byBvid = {for (final s in local) if (s.bvid.isNotEmpty) s.bvid: s};
        for (var i = 0; i < _queue.length; i++) {
          final full = byBvid[_queue[i].bvid];
          if (full != null) _queue[i] = full;
        }
        final curFull = byBvid[_currentSong?.bvid];
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

  void _writeMeta(Song song, Duration d) {
    try {
      final metaPath = '${song.filePath.substring(0, song.filePath.lastIndexOf('.'))}.json';
      File(metaPath).writeAsStringSync(jsonEncode({'author': song.uploader, 'duration': d.inSeconds}));
    } catch (_) {}
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