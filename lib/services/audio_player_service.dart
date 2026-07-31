import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_data.dart';

enum PlayMode { sequential, loopList, loopOne, shuffle }

class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) next();
    });
    _player.positionStream.listen((_) {}); // dummy to keep stream alive
  }

  final AudioPlayer _player = AudioPlayer();
  Song? _currentSong;
  final List<Song> _queue = [];
  PlayMode _playMode = PlayMode.loopList;
  int _queueIndex = 0;

  final ValueNotifier<Song?> currentSongNotifier = ValueNotifier(null);

  Song? get currentSong => _currentSong;
  List<Song> get queue => List.unmodifiable(_queue);
  PlayMode get playMode => _playMode;
  bool get isPlaying => _player.playing;
  int get queueIndex => _queueIndex;
  Stream<Duration> get onPositionChanged => _player.positionStream.map((d) => d ?? Duration.zero);
  Stream<Duration> get onDurationChanged => _player.durationStream.map((d) => d ?? Duration.zero);
  Stream<bool> get onPlayingChanged => _player.playingStream;

  // ==================== 播放控制 ====================

  Future<void> playSong(Song song) async {
    final idx = _queue.indexWhere((s) => s.filePath == song.filePath);
    if (idx >= 0) _queueIndex = idx;

    if (_currentSong?.filePath == song.filePath) {
      if (_player.playing) { _player.pause(); } else { _player.play(); }
      return;
    }
    _currentSong = song;
    currentSongNotifier.value = song;
    await _player.setFilePath(song.filePath);
    _player.play();

    // 立即拿duration写metadata
    final d = _player.duration;
    if (d != null && d.inMilliseconds > 0) {
      _writeMeta(song, d);
    }
    _saveState();
    RecentlyPlayedService.addIfNotExists(song.filePath, song.title, song.uploader, song.duration.inSeconds, song.filePath, song.coverUrl ?? '').catchError((_) {});
  }

  Future<void> togglePause() async {
    if (_player.playing) { _player.pause(); } else { _player.play(); }
  }

  Future<void> seek(Duration position) async => _player.seek(position);

  Future<void> next() async {
    if (_queue.isEmpty) return;
    if (_playMode == PlayMode.loopOne) { await seek(Duration.zero); return; }
    if (_playMode == PlayMode.shuffle) {
      final rng = Random(); var next = _queueIndex;
      while (next == _queueIndex && _queue.length > 1) { next = rng.nextInt(_queue.length); }
      _queueIndex = next;
    } else { _queueIndex = (_queueIndex + 1) % _queue.length; }
    await playSong(_queue[_queueIndex]);
  }

  Future<void> prev() async {
    if (_queue.isEmpty) return;
    final pos = _player.position;
    if (pos.inSeconds > 3) { await _player.seek(Duration.zero); return; }
    _queueIndex = (_queueIndex - 1 + _queue.length) % _queue.length;
    await playSong(_queue[_queueIndex]);
  }

  // ==================== 队列 ====================

  void setQueue(List<Song> songs, {int startIndex = 0}) { _queue.clear(); _queue.addAll(songs); _queueIndex = startIndex.clamp(0, _queue.length - 1); currentSongNotifier.notifyListeners(); }
  void addToQueue(Song song) { _queue.add(song); currentSongNotifier.notifyListeners(); }
  void removeFromQueue(int index) { if (index >= _queue.length) return; _queue.removeAt(index); if (index < _queueIndex) _queueIndex--; if (_queueIndex >= _queue.length) _queueIndex = (_queue.length - 1).clamp(0, 999); currentSongNotifier.notifyListeners(); }
  void setPlayMode(PlayMode mode) { _playMode = mode; _saveMode(); currentSongNotifier.notifyListeners(); }
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
    try { final metaPath = '${song.filePath.substring(0, song.filePath.lastIndexOf('.'))}.json'; final meta = {'author': song.uploader.isNotEmpty ? song.uploader : '', 'duration': d.inSeconds}; File(metaPath).writeAsStringSync(jsonEncode(meta)); } catch (_) {}
  }
}

