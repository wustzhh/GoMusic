import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_data.dart';

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
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  Duration _lastPosition = Duration.zero;
  bool _playing = false;
  Song? _currentSong;
  final List<Song> _queue = [];
  PlayMode _playMode = PlayMode.loopList;
  int _queueIndex = 0;
  final currentSongNotifier = ValueNotifier<Song?>(null);

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

  Future<void> playSong(Song song) async {
    final idx = _queue.indexWhere((s) => s.filePath == song.filePath);
    if (idx >= 0) _queueIndex = idx;
    if (_currentSong?.filePath == song.filePath) {
      if (_playing) { _player.pause(); _playing = false; } else {
        await _player.play(DeviceFileSource(song.filePath), position: _lastPosition > Duration.zero ? _lastPosition : null);
        _playing = true;
      }
      return;
    }
    _currentSong = song;
    currentSongNotifier.value = song;
    await _player.stop();
    await _player.play(DeviceFileSource(song.filePath));
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
      if (_lastPosition > Duration.zero && _currentSong != null) {
        final cur = await _player.getCurrentPosition();
        if (cur == null || cur == Duration.zero) await _player.seek(_lastPosition);
      }
      _player.resume(); _playing = true;
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
    if (_playMode == PlayMode.shuffle) { var n = _queueIndex; while (n == _queueIndex && _queue.length > 1) n = Random().nextInt(_queue.length); _queueIndex = n; }
    else { _queueIndex = (_queueIndex + 1) % _queue.length; }
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
  void setQueue(List<Song> s, {int startIndex = 0}) { _queue.clear(); _queue.addAll(s); _queueIndex = startIndex.clamp(0, _queue.length - 1); currentSongNotifier.notifyListeners(); }
  void addToQueue(Song s) { _queue.add(s); currentSongNotifier.notifyListeners(); }
  void removeFromQueue(int i) { if (i >= _queue.length) return; _queue.removeAt(i); if (i < _queueIndex) _queueIndex--; if (_queueIndex >= _queue.length) _queueIndex = (_queue.length - 1).clamp(0, 999); currentSongNotifier.notifyListeners(); }
  void setPlayMode(PlayMode m) { _playMode = m; _saveMode(); currentSongNotifier.notifyListeners(); }
  String get playModeLabel { switch (_playMode) { case PlayMode.sequential: return '顺序播放'; case PlayMode.loopList: return '列表循环'; case PlayMode.loopOne: return '单曲循环'; case PlayMode.shuffle: return '随机播放'; }}

  // ==================== 收藏 ====================
  static const _favKey = 'favorites';
  static Future<Set<String>> getFavorites() async { final p = await SharedPreferences.getInstance(); return (p.getStringList(_favKey) ?? []).toSet(); }
  static Future<void> toggleFavorite(String fp) async { final p = await SharedPreferences.getInstance(); final s = (p.getStringList(_favKey) ?? []).toSet(); if (s.contains(fp)) { s.remove(fp); } else { s.add(fp); } await p.setStringList(_favKey, s.toList()); }
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
      final song = Song(
        id: data['bvid'] as String? ?? '',
        title: data['title'] as String? ?? '',
        uploader: data['uploader'] as String? ?? '',
        duration: Duration(seconds: data['duration'] as int? ?? 0),
        filePath: data['song'] as String? ?? '',
        bvid: data['bvid'] as String? ?? '',
        coverUrl: (data['cover'] as String? ?? '').isNotEmpty ? data['cover'] as String? : null,
      );
      _currentSong = song;
      currentSongNotifier.value = song;
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