import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_data.dart';

enum PlayMode { sequential, loopList, loopOne, shuffle }

/// 全局音频播放服务（单例）
class AudioPlayerService {
  static final AudioPlayerService _instance = AudioPlayerService._();
  factory AudioPlayerService() => _instance;
  AudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  Song? _currentSong;
  final List<Song> _queue = [];
  PlayMode _playMode = PlayMode.loopList;
  int _queueIndex = 0;

  Song? get currentSong => _currentSong;
  List<Song> get queue => List.unmodifiable(_queue);
  PlayMode get playMode => _playMode;
  AudioPlayer get player => _player;
  bool get isPlaying => _player.state == PlayerState.playing;
  int get queueIndex => _queueIndex;

  Stream<Duration> get onPositionChanged => _player.onPositionChanged;
  Stream<Duration> get onDurationChanged => _player.onDurationChanged;
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  // ==================== 播放控制 ====================

  Future<void> playSong(Song song) async {
    if (_currentSong?.filePath == song.filePath) {
      await togglePause();
      return;
    }
    _currentSong = song;
    await _player.stop();
    await _player.play(DeviceFileSource(song.filePath));
    // 记录最近播放
    await RecentlyPlayedService.addIfNotExists(
      song.filePath, song.title, song.uploader,
      song.duration.inSeconds, song.filePath, song.coverUrl ?? '',
    );
    _saveState();
  }

  Future<void> togglePause() async {
    if (_player.state == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> next() async {
    if (_queue.isEmpty) return;
    switch (_playMode) {
      case PlayMode.shuffle:
        _queueIndex = (_queue.length > 1) ? (_queueIndex + 1) % _queue.length : 0;
        break;
      case PlayMode.loopOne:
        break;
      default:
        _queueIndex = (_queueIndex + 1) % _queue.length;
    }
    await playSong(_queue[_queueIndex]);
  }

  Future<void> prev() async {
    if (_queue.isEmpty) return;
    final pos = await _player.getCurrentPosition();
    if (pos != null && pos.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    _queueIndex = (_queueIndex - 1 + _queue.length) % _queue.length;
    await playSong(_queue[_queueIndex]);
  }

  // ==================== 队列管理 ====================

  void setQueue(List<Song> songs, {int startIndex = 0}) {
    _queue.clear();
    _queue.addAll(songs);
    _queueIndex = startIndex.clamp(0, _queue.length - 1);
  }

  void addToQueue(Song song) {
    _queue.add(song);
  }

  void removeFromQueue(int index) {
    if (index < _queue.length) {
      _queue.removeAt(index);
      if (index < _queueIndex) _queueIndex--;
      if (_queueIndex >= _queue.length) _queueIndex = _queue.length - 1;
    }
  }

  void setPlayMode(PlayMode mode) {
    _playMode = mode;
    _saveMode();
  }

  String get playModeLabel {
    switch (_playMode) {
      case PlayMode.sequential: return '顺序播放';
      case PlayMode.loopList: return '列表循环';
      case PlayMode.loopOne: return '单曲循环';
      case PlayMode.shuffle: return '随机播放';
    }
  }

  // ==================== 收藏 ====================

  static const _favKey = 'favorites';

  static Future<Set<String>> getFavorites() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_favKey) ?? []).toSet();
  }

  static Future<void> toggleFavorite(String filePath) async {
    final p = await SharedPreferences.getInstance();
    final set = (p.getStringList(_favKey) ?? []).toSet();
    if (set.contains(filePath)) {
      set.remove(filePath);
    } else {
      set.add(filePath);
    }
    await p.setStringList(_favKey, set.toList());
  }

  static Future<bool> isFavorite(String filePath) async {
    final f = await getFavorites();
    return f.contains(filePath);
  }

  // ==================== 持久化 ====================

  Future<void> _saveState() async {
    if (_currentSong == null) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('last_song', '${_currentSong!.filePath}|${_currentSong!.title}|${_currentSong!.uploader}|${_currentSong!.duration.inSeconds}|${_currentSong!.bvid}|${_currentSong!.coverUrl ?? ''}');
  }

  Future<void> _saveMode() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('play_mode', _playMode.index);
  }

  /// 恢复上次播放状态
  Future<Song?> restoreLastSong() async {
    final p = await SharedPreferences.getInstance();
    final last = p.getString('last_song');
    if (last == null) return null;

    final parts = last.split('|');
    if (parts.length < 5) return null;

    final savedMode = p.getInt('play_mode');
    if (savedMode != null && savedMode < PlayMode.values.length) {
      _playMode = PlayMode.values[savedMode];
    }

    return Song(
      id: parts[4],
      title: parts[1],
      uploader: parts.length > 2 ? parts[2] : '',
      duration: Duration(seconds: int.tryParse(parts[3]) ?? 0),
      filePath: parts[0],
      bvid: parts[4],
      coverUrl: parts.length > 5 && parts[5].isNotEmpty ? parts[5] : null,
    );
  }
}
