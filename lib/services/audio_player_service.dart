import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:media_kit/media_kit.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_data.dart';
import 'settings_service.dart';

enum PlayMode { sequential, loopList, loopOne, shuffle }

class AudioPlayerService {
  static AudioPlayerService? _instance;
  factory AudioPlayerService() => _instance ??= AudioPlayerService._();
  AudioPlayerService._() {
    WidgetsBinding.instance.addObserver(_AppObserver(_saveState));
  }

  /// 确保播放内核存在（生产环境首次访问时构造 libmpv Player）
  Player? _playerRef;
  bool _playerInitDone = false;
  void _ensurePlayer() {
    if (_playerInitDone) return;
    _playerInitDone = true;
    if (_playerRef != null) return;
    _playerRef = Player();
    _attachPlayerListeners();
  }

  /// 请求音频焦点（与其他音乐/视频 app 互斥）
  bool _interruptionWired = false;

  Future<void> _requestAudioFocus() async {
    try {
      final session = await AudioSession.instance;
      if (!session.isConfigured) {
        await session.configure(const AudioSessionConfiguration.music());
      }
      if (!_interruptionWired) {
        _interruptionWired = true;
        // 其他 app 抢占音频焦点时，暂停自己（互斥）
        session.interruptionEventStream.listen((event) {
          if (event.begin && _playing) {
            _player.pause();
            _playing = false;
            currentSongNotifier.notifyListeners();
          }
        });
      }
      await session.setActive(true);
    } catch (_) {}
  }

  /// 放弃音频焦点（暂停时）
  Future<void> _releaseAudioFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }

  Player get _player {
    _ensurePlayer();
    return _playerRef!;
  }

  /// 测试专用：重置单例（测试环境无法加载 libmpv，可注入 fake Player）
  @visibleForTesting
  static void resetForTest({Player? player}) {
    _instance?.disposeForTest();
    _instance = null;
    if (player != null) {
      _instance = AudioPlayerService._();
      _instance!._playerRef = player;
      _instance!._playerInitDone = true;
      // 重新挂载 completed/duration 监听与进度轮询
      _instance!._attachPlayerListeners();
    }
  }

  /// 生产构造与测试注入共用：挂载播放器事件监听
  void _attachPlayerListeners() {
    _playerRef!.stream.completed.listen((_) {
      _playing = false;
      _autoNext();
    });
    _playerRef!.stream.duration.listen((d) {
      if (d.inMilliseconds > 0 && _currentSong != null) {
        SongManager.updateDuration(_currentSong!.filePath, d.inSeconds);
      }
    });
    int _saveCounter = 0;
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_currentSong != null && _playing) {
        final p = _playerRef!.state.position;
        _lastPosition = p;
        _positionController.add(p);
        _saveCounter++;
        if (_saveCounter % 4 == 0) _saveState();
      }
    });
  }

  Timer? _pollTimer;

  /// 释放轮询定时器（仅测试用；正常生命周期跟随进程，无需调用）。
  @visibleForTesting
  void disposeForTest() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  bool _sourceLoaded = false;
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  Duration _lastPosition = Duration.zero;
  /// 播放状态流：不依赖 media_kit 底层 playing 事件（首次播放不可靠），
  /// 由 _playing setter 主动发出，UI/媒体会话据此同步按钮与通知栏。
  final StreamController<bool> _playingController = StreamController<bool>.broadcast();
  bool _playingState = false;
  bool get _playing => _playingState;
  set _playing(bool v) {
    if (_playingState != v) {
      _playingState = v;
      if (!_playingController.isClosed) _playingController.add(v);
    }
  }
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
  Stream<Duration> get onDurationChanged => _player.stream.duration;
  Stream<bool> get onPlayingChanged => _playingController.stream;

  // ==================== 播放 ====================

  Future<void> playSong(Song song, {bool forceRestart = false}) async {
    // 目标文件必须存在，否则不播放：避免 media_kit open 失败时旧歌继续响
    // 或队列索引被点击目标污染导致 next() 跳错（"点 A 播 B"）。
    if (song.filePath.isEmpty || !File(song.filePath).existsSync()) {
      _playing = false;
      // 定位被点击的无效歌在队列中的位置，从它往后跳（跳过无效歌）
      final badPos = _queue.indexWhere((s) => (s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)) == (song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath)));
      if (badPos >= 0) _queueIndex = badPos;
      Future.delayed(const Duration(milliseconds: 300), () => _skipToValid());
      return;
    }
    // 队列为空时兜底：把当前歌设为单曲队列，保证播放列表始终有内容
    if (_queue.isEmpty) {
      _queue.add(song);
      _queueIndex = 0;
    }
    final idx = _queue.indexWhere((s) => (s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)) == (song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath)));
    if (idx >= 0) _queueIndex = idx;
    if (_currentSong?.filePath == song.filePath && !forceRestart) {
      final st = _player.state;
      if (_playing && !st.completed) {
        // 用户要求：点击正在播放的歌曲不暂停（保持播放，仅进入播放界面）
        _requestAudioFocus();
      } else if (st.completed) {
        // 真的播完了：从头播放当前歌
        _lastPosition = Duration.zero;
        await _playFile(song.filePath);
        _sourceLoaded = true;
        _playing = true;
      } else {
        // 暂停中：优先 resume 续播（不重新加载、不回 0）
        _requestAudioFocus();
        try {
          if (_player.state.completed) {
            _lastPosition = Duration.zero;
            await _playFile(song.filePath);
          } else {
            _player.play();
          }
          _sourceLoaded = true;
          _playing = true;
        } catch (_) {
          await _playFile(song.filePath, position: _lastPosition > Duration.zero ? _lastPosition : null);
          _sourceLoaded = true;
          _playing = true;
        }
      }
      return;
    }
    // 换源决定：立即标记手动播放时间——open 进行中旧源 complete 就会到达，
    // 必须在 open 前建立防抖，否则误触发 _autoNext 切到下一首（"点 A 播 B"）
    _lastManualPlayAt = DateTime.now();
    _lastPosition = Duration.zero;
    _currentSong = song;
    currentSongNotifier.value = song;
    _requestAudioFocus();
    try {
      await _playFile(song.filePath);
      _sourceLoaded = true;
      _playing = true;
    } catch (e) {
      // 播放失败：跳过该曲（下一曲容错）
      _playing = false;
      Future.delayed(const Duration(milliseconds: 300), () => next());
      return;
    }
    // 新歌：清除上次位置，避免残留影响
    _lastPosition = Duration.zero;
    _saveState();
    RecentlyPlayedService.addIfNotExists(song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath)).catchError((_) {});
  }

  void togglePause() async {
    if (_playing) {
      _lastPosition = _player.state.position;
      _player.pause();
      _playing = false;
      _releaseAudioFocus();
    } else {
      _requestAudioFocus();
      if (_currentSong != null && _player.state.completed) {
        // 真的播完了：从头重新播放当前歌
        // （resume/seek 结尾会导致立刻 complete 误切歌）
        _lastPosition = Duration.zero;
        await _playFile(_currentSong!.filePath);
        _sourceLoaded = true;
        _playing = true;
        _saveState();
        currentSongNotifier.notifyListeners();
        return;
      }
      if (!_sourceLoaded && _currentSong != null) {
        // 初始未加载（含启动恢复场景）：带恢复进度播放
        await _playFile(_currentSong!.filePath, position: _lastPosition > Duration.zero ? _lastPosition : null);
        _sourceLoaded = true;
      } else {
        if (_lastPosition > Duration.zero && _currentSong != null) {
          final cur = _player.state.position;
          if (cur == null || cur == Duration.zero) await _player.seek(_lastPosition);
        }
        _player.play();
      }
      _playing = true;
    }
    _saveState();
    currentSongNotifier.notifyListeners(); // 强制刷新UI
  }

  void pause() {
    _player.pause();
    _playing = false;
    _releaseAudioFocus();
  }

  /// 从队列移除歌曲（按 BV号键）
  void removeFromQueueByKey(String key) {
    _queue.removeWhere((s) => (s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)) == key);
    if (_queueIndex >= _queue.length) _queueIndex = _queue.isEmpty ? 0 : _queue.length - 1;
    _saveState();
    currentSongNotifier.notifyListeners();
  }

  /// 下一首播放：目标歌曲放入当前歌曲（或所在组）之后
  void playNext(Song song) {
    final key = song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath);
    // 移除已存在的目标（存在则放到下一位）
    final existIdx = _queue.indexWhere((s) => (s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)) == key);
    if (existIdx >= 0) {
      _queue.removeAt(existIdx);
      if (existIdx < _queueIndex) _queueIndex--;
    }
    // 计算插入位置
    int insertAt;
    final curSong = _currentSong;
    if (curSong != null) {
      final g = SongGroupService.groupOf(curSong, playlistId: _currentPlaylistId.isEmpty ? null : _currentPlaylistId);
      if (g != null) {
        // 当前在组内：插到组的最后一个成员之后
        var lastMemberIdx = _queueIndex;
        for (var i = 0; i < _queue.length; i++) {
          final s = _queue[i];
          if (g.songPaths.contains(s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath))) {
            lastMemberIdx = i;
          }
        }
        insertAt = lastMemberIdx + 1;
      } else {
        insertAt = _queueIndex + 1;
      }
    } else {
      insertAt = _queue.isEmpty ? 0 : _queueIndex + 1;
    }
    if (insertAt < 0) insertAt = 0;
    if (insertAt > _queue.length) insertAt = _queue.length;
    _queue.insert(insertAt, song);
    _saveState();
    currentSongNotifier.notifyListeners();
  }

  void resume() {
    if (_currentSong == null) return;
    _requestAudioFocus();
    if (_player.state.completed) {
      // 已播完：从记录位置重新播放（如拖动进度条后）
      _playFile(_currentSong!.filePath, position: _lastPosition > Duration.zero ? _lastPosition : null);
      _sourceLoaded = true;
      _playing = true;
      return;
    }
    _player.play();
    _playing = true;
  }

  Future<void> seek(Duration p) async {
    _lastPosition = p;
    _positionController.add(p);
    await _player.seek(p);
    _saveState();
  }

  Future<void> next() async {
    try {
      await _next();
    } catch (_) {
      // 出错也尝试跳下一首
      if (_queue.isNotEmpty && _queue.length > 1) {
        _queueIndex = (_queueIndex + 1) % _queue.length;
        await playSong(_queue[_queueIndex]);
      }
    }
  }

  /// 播放完成自动触发：单曲循环重播自己，否则切下一首
  /// 防抖1：Windows 端换源时旧源的 complete 事件可能滞后到达，1 秒内忽略重复触发
  /// 防抖2：手动切歌/播放后 2 秒内忽略 complete（换源时旧源 complete 滞后到达，
  ///        会误触发 next() 导致"点 A 播 B"——实际是自动切到了下一首）
  DateTime? _lastCompleteAt;
  DateTime? _lastManualPlayAt;
  Future<void> _autoNext() async {
    if (_queue.isEmpty) return;
    final now = DateTime.now();
    // 手动播放/切歌后 2 秒内：旧源 complete 滞后到达，不是真播完，忽略
    if (_lastManualPlayAt != null && now.difference(_lastManualPlayAt!) < const Duration(seconds: 2)) {
      return;
    }
    if (_lastCompleteAt != null && now.difference(_lastCompleteAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastCompleteAt = now;
    if (_playMode == PlayMode.loopOne) {
      // 单曲循环：重新播放自己（Windows 端播完已 Stop，resume 无效，必须重新 play）
      await playSong(_currentSong!, forceRestart: true);
      return;
    }
    await next();
  }

  Future<void> _next() async {
    if (_queue.isEmpty) return;
    // 随机模式 = 队列在 setQueue/setPlayMode 时已整体随机化，
    // 下一曲永远按随机后列表顺序取下一首（不重复随机）
    _queueIndex = (_queueIndex + 1) % _queue.length;
    await playSong(_queue[_queueIndex]);
  }

  /// 从当前 _queueIndex 往后跳，跳过文件无效的歌（点无效歌时用）
  Future<void> _skipToValid() async {
    if (_queue.isEmpty) return;
    for (var i = 0; i < _queue.length; i++) {
      _queueIndex = (_queueIndex + 1) % _queue.length;
      final s = _queue[_queueIndex];
      if (s.filePath.isNotEmpty && File(s.filePath).existsSync()) {
        await playSong(s);
        return;
      }
    }
    _playing = false; // 全队列都无效
  }

  Future<void> prev() async {
    if (_queue.isEmpty) return;
    final pos = _player.state.position;
    if (pos != null && pos.inSeconds > 3) { await _player.seek(Duration.zero); return; }
    _queueIndex = (_queueIndex - 1 + _queue.length) % _queue.length;
    await playSong(_queue[_queueIndex]);
  }

  /// media_kit 播放本地文件：open + 可选 seek 定位 + play
  /// 带序号防竞态：快速连续点击/切歌时，只有最后一次 open 才会真正 play，
  /// 避免旧 open 异步完成时覆盖新歌（"点 A 播 B"）。
  int _playSeq = 0;
  Future<void> _playFile(String path, {Duration? position}) async {
    // 任何实际播放都刷新防抖时间戳：open 期间旧源 complete 到达时，
    // _autoNext 会因 2 秒内刚播放过而忽略，避免误切到下一首
    _lastManualPlayAt = DateTime.now();
    final seq = ++_playSeq;
    await _player.open(Media(path), play: false);
    if (seq != _playSeq) return; // 已被更新的播放请求取代
    if (position != null && position > Duration.zero) {
      await _player.seek(position);
      if (seq != _playSeq) return;
    }
    await _player.play();
  }

  // ==================== 队列 ====================
  void setQueue(List<Song> s, {int startIndex = 0, String? playlistId, bool keepOrder = false}) {
    if (playlistId != null) _currentPlaylistId = playlistId;
    final curKey = s.isNotEmpty && startIndex >= 0 && startIndex < s.length
        ? (s[startIndex].bvid.isNotEmpty ? s[startIndex].bvid : _fileNameKey(s[startIndex].filePath))
        : null;
    _queue.clear();
    if (_playMode == PlayMode.shuffle) {
      // 随机模式：先随机化整个列表，播放全部时从随机后第一首开始
      _queue.addAll(_shuffleGroups(s));
      // 播放全部（startIndex==0）：从随机后队列第一首开始；否则定位原歌曲在随机队列中的位置
      _queueIndex = _queue.isEmpty
          ? 0
          : (startIndex == 0
              ? 0
              : (curKey != null
                  ? _queue.indexWhere((x) => (x.bvid.isNotEmpty ? x.bvid : _fileNameKey(x.filePath)) == curKey)
                  : startIndex.clamp(0, _queue.length - 1)));
    } else {
      // 非随机（含播放全部）：按组重排——组内成员聚拢相邻且保持相对顺序，单曲原位
      _queue.addAll(_groupedQueue(s));
      _queueIndex = _queue.isEmpty ? 0 : startIndex.clamp(0, _queue.length - 1);
    }
    if (_queueIndex < 0) _queueIndex = 0;
    currentSongNotifier.notifyListeners();
  }
  void addToQueue(Song s) { _queue.add(s); currentSongNotifier.notifyListeners(); }
  void removeFromQueue(int i) { if (i >= _queue.length) return; _queue.removeAt(i); if (i < _queueIndex) _queueIndex--; if (_queueIndex >= _queue.length) _queueIndex = (_queue.length - 1).clamp(0, 999); currentSongNotifier.notifyListeners(); }

  /// 把指定歌曲移到队列最前（随机模式点击歌曲时使用：该歌必须是第一首）
  void moveToFront(Song song) {
    final key = song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath);
    final idx = _queue.indexWhere((s) => (s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)) == key);
    if (idx > 0) {
      final s = _queue.removeAt(idx);
      _queue.insert(0, s);
    }
    _queueIndex = 0;
    currentSongNotifier.notifyListeners();
  }

  /// 点击歌曲播放前的队列调整：
  /// - 点击的是组内歌曲：点击的歌排到组内第一首（组内其余按组设置：随机打乱/顺序保持），
  ///   保证从点击的歌开始把整个组播完才出组；
  /// - 歌单播放模式为随机：整组放到队列最前（先播完这个组再播其他）；
  /// - 单曲（无组）：原有 moveToFront 行为。
  void prepareClickedSong(Song song) {
    final key = song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath);
    final g = SongGroupService.groupOf(song, playlistId: _currentPlaylistId.isEmpty ? null : _currentPlaylistId);
    if (g == null) { moveToFront(song); return; }
    // 收集组员（按队列当前顺序），记录原组首位置
    final members = <Song>[];
    var groupStart = _queue.length;
    for (var i = 0; i < _queue.length; i++) {
      final s = _queue[i];
      if (g.songPaths.contains(s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath))) {
        members.add(s);
        if (i < groupStart) groupStart = i;
      }
    }
    if (members.isEmpty) return;
    // 组内排序：点击的歌第一，其余按组设置
    final rest = members
        .where((m) => (m.bvid.isNotEmpty ? m.bvid : _fileNameKey(m.filePath)) != key)
        .toList();
    if (g.shuffle && rest.length > 1) rest.shuffle(Random());
    final ordered = <Song>[song, ...rest];
    // 移除组员
    _queue.removeWhere((s) => g.songPaths.contains(s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)));
    // 插入：随机模式→最前；否则→原组首位置
    final insertAt = _playMode == PlayMode.shuffle ? 0 : groupStart.clamp(0, _queue.length);
    _queue.insertAll(insertAt, ordered);
    _queueIndex = _queue.indexWhere((s) => (s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath)) == key);
    if (_queueIndex < 0) _queueIndex = 0;
    currentSongNotifier.notifyListeners();
  }
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
  /// 切换收藏（单曲菜单用）：在则取消、不在则添加到最上
  static Future<void> toggleFavorite(Song song) async {
    final key = song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath);
    final p = await SharedPreferences.getInstance();
    final list = List<String>.from(p.getStringList(_favKey) ?? []);
    final idx = list.indexOf(key);
    if (idx >= 0) { list.removeAt(idx); } else { list.insert(0, key); } // 新收藏放最上面
    await p.setStringList(_favKey, list);
    _instance?.favoritesChangedNotifier.value++;
  }

  /// 无条件移除收藏（删除本地歌曲时清理"我喜欢"用，不依赖缓存状态）
  static Future<void> removeFavorite(String key) async {
    final p = await SharedPreferences.getInstance();
    final list = List<String>.from(p.getStringList(_favKey) ?? []);
    if (list.remove(key)) {
      await p.setStringList(_favKey, list);
      _instance?.favoritesChangedNotifier.value++;
    }
  }

  /// 纯添加收藏：已在收藏中则跳过（不取消）——批量"添加到我喜欢"用
  static Future<void> addFavorite(Song song) async {
    final key = song.bvid.isNotEmpty ? song.bvid : _fileNameKey(song.filePath);
    final p = await SharedPreferences.getInstance();
    final list = List<String>.from(p.getStringList(_favKey) ?? []);
    if (!list.contains(key)) {
      list.insert(0, key); // 新收藏放最上面
      await p.setStringList(_favKey, list);
      _instance?.favoritesChangedNotifier.value++;
    }
  }

  /// 批量添加收藏（保持选中顺序，整体插到最上面；已在收藏的跳过）
  static Future<void> addFavoritesBatch(List<Song> songs) async {
    if (songs.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    final list = List<String>.from(p.getStringList(_favKey) ?? []);
    final newKeys = songs
        .map((s) => s.bvid.isNotEmpty ? s.bvid : _fileNameKey(s.filePath))
        .where((k) => !list.contains(k))
        .toList();
    if (newKeys.isNotEmpty) {
      list.insertAll(0, newKeys); // 整体插到最前，保持选中顺序
      await p.setStringList(_favKey, list);
      _instance?.favoritesChangedNotifier.value++;
    }
  }

  /// 重排收藏顺序（我喜欢歌单拖动排序后保存）
  static Future<void> saveFavoritesOrder(List<String> bvids) async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_favKey, bvids);
    _instance?.favoritesChangedNotifier.value++;
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
      // 恢复播放模式：优先 SharedPreferences（setPlayMode 写入），兼容旧 save_state.json 的 mode 字段
      final prefs = await SharedPreferences.getInstance();
      final smPref = prefs.getInt('play_mode');
      if (smPref != null && smPref >= 0 && smPref < PlayMode.values.length) {
        _playMode = PlayMode.values[smPref];
      }
      final f = File('save_state.json');
      if (!f.existsSync()) return null;
      final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final sm = data['mode'] as int?;
      if (sm != null && sm < PlayMode.values.length) _playMode = PlayMode.values[sm];
      // 恢复上次播放进度（杀进程/退出后从上次位置续播）
      _lastPosition = Duration(milliseconds: data['position'] as int? ?? 0);
      if (_lastPosition < Duration.zero) _lastPosition = Duration.zero;
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