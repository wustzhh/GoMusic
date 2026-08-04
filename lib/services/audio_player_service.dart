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
    _player.onDurationChanged.listen((d) {
      if (d.inMilliseconds > 0 && _currentSong != null) {
        _writeMeta(_currentSong!, d);
      }
    });
    // 进度轮询
    Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_currentSong != null && _player.state == PlayerState.playing) {
        final p = await _player.getCurrentPosition();
        if (p != null) _positionController.add(p);
      }
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  Song? _currentSong;
  final List<Song> _queue = [];
  PlayMode _playMode = PlayMode.loopList;
  int _queueIndex = 0;
  final currentSongNotifier = ValueNotifier<Song?>(null);

  Song? get currentSong => _currentSong;
  List<Song> get queue => List.unmodifiable(_queue);
  PlayMode get playMode => _playMode;
  bool get isPlaying => _player.state == PlayerState.playing;
  int get queueIndex => _queueIndex;
  Stream<Duration> get onPositionChanged => _positionController.stream;
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  Stream<bool> get onPlayingChanged => _player.onPlayerStateChanged.map((s) => s == PlayerState.playing);

  // ==================== 播放 ====================

  Future<void> playSong(Song song) async {
    final idx = _queue.indexWhere((s) => s.filePath == song.filePath);
    if (idx >= 0) _queueIndex = idx;
    if (_currentSong?.filePath == song.filePath) {
      if (_player.state == PlayerState.playing) { _player.pause(); } else { _player.resume(); }
      return;
    }
    _currentSong = song;
    currentSongNotifier.value = song;
    await _player.stop();
    await _player.play(DeviceFileSource(song.filePath));
    _saveState();
    RecentlyPlayedService.addIfNotExists(song.filePath, song.title, song.uploader, song.duration.inSeconds, song.filePath, song.coverUrl ?? '').catchError((_) {});
  }

  Future<void> togglePause() async {
    if (_player.state == PlayerState.playing) { _player.pause(); } else { _player.resume(); }
  }

  Future<void> seek(Duration p) => _player.seek(p);

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
  Future<void> _saveState() async { if (_currentSong == null) return; final p = await SharedPreferences.getInstance(); await p.setString('last_song', '${_currentSong!.filePath}|${_currentSong!.title}|${_currentSong!.uploader}|${_currentSong!.duration.inSeconds}|${_currentSong!.bvid}|${_currentSong!.coverUrl ?? ''}'); }
  Future<void> _saveMode() async { final p = await SharedPreferences.getInstance(); await p.setInt('play_mode', _playMode.index); }
  Future<Song?> restoreLastSong() async { final p = await SharedPreferences.getInstance(); final last = p.getString('last_song'); if (last == null) return null; final parts = last.split('|'); if (parts.length < 5) return null; final sm = p.getInt('play_mode'); if (sm != null && sm < PlayMode.values.length) _playMode = PlayMode.values[sm]; return Song(id: parts[4], title: parts[1], uploader: parts.length > 2 ? parts[2] : '', duration: Duration(seconds: int.tryParse(parts[3]) ?? 0), filePath: parts[0], bvid: parts[4], coverUrl: parts.length > 5 && parts[5].isNotEmpty ? parts[5] : null); }

  void _writeMeta(Song song, Duration d) {
    try {
      final metaPath = '${song.filePath.substring(0, song.filePath.lastIndexOf('.'))}.json';
      File(metaPath).writeAsStringSync(jsonEncode({'author': song.uploader, 'duration': d.inSeconds}));
    } catch (_) {}
  }
}
