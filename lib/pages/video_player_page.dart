import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
import '../services/audio_handler.dart';

/// 视频播放器：播放/暂停/进度/倍速/横屏(全屏)/锁定(沉浸式)/上一个下一个
/// 与音频互斥：打开视频时暂停音频，退出后恢复
class VideoPlayerPage extends StatefulWidget {
  final Song song;
  /// 可选：视频列表（用于上一个/下一个），需同时提供 initialIndex
  final List<Song>? videos;
  final int? initialIndex;
  const VideoPlayerPage({super.key, required this.song, this.videos, this.initialIndex});
  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final _player = Player();
  VideoController? _controller;
  StreamSubscription? _posSub, _durSub, _playingSub, _completeSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  double _speed = 1.0;
  late int _currentIndex;
  // UI 状态
  bool _controlsVisible = true;  // 控制栏是否显示
  bool _fullscreen = false;      // 横屏/全屏
  bool _locked = false;          // 锁定（沉浸式全屏）
  Timer? _uiTimer;               // UI 自动隐藏定时器
  Timer? _unlockHintTimer;       // 解锁按钮显示 5 秒定时器
  Timer? _saveTimer;             // 视频进度保存定时器
  bool _showUnlockHint = false;  // 锁定状态下是否显示解锁按钮

  Song get _song => (widget.videos != null && widget.videos!.isNotEmpty)
      ? widget.videos![_currentIndex.clamp(0, widget.videos!.length - 1)]
      : widget.song;

  /// 视频进度存储 key（单独存储，与音频进度分开）
  void _vlog(String msg) {
    try {
      final tmp = Directory.systemTemp;
      File('${tmp.path}${Platform.pathSeparator}gomusic_video.log').writeAsStringSync('[${DateTime.now().toIso8601String().substring(11, 19)}] $msg\n', mode: FileMode.append);
    } catch (_) {}
  }

  String get _progressKey => 'video_progress_${_song.bvid.isNotEmpty ? _song.bvid : _song.filePath.split('\\').last.split('/').last.split('.').first}';

  @override
  void initState() {
    super.initState();
    _currentIndex = (widget.initialIndex ?? 0).clamp(0, (widget.videos?.length ?? 1) - 1);
    _controller = VideoController(_player);
    _playingSub = _player.stream.playing.listen((p) {
      if (mounted) setState(() => _playing = p);
      // 暂停瞬间立即保存进度（防杀进程丢失）
      if (!p && _seekDone) {
        _saveProgress(_player.state.position ?? _position);
      }
      // 同步媒体会话（视频播放/暂停 → 通知栏/锁屏按钮状态）
      GoMusicAudioHandler.instance?.notifyVideoMedia(
        id: _song.bvid.isNotEmpty ? _song.bvid : _song.filePath,
        title: _song.title,
        artist: _song.uploader,
        duration: _duration,
        playing: p,
        position: _position,
      );
    });
    _posSub = _player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _player.stream.duration.listen((d) { if (mounted) setState(() => _duration = d); });
    _completeSub = _player.stream.completed.listen((_) {
      if (mounted) setState(() => _playing = false);
      // 播完清除进度，下次从头
      _saveProgress(Duration.zero);
    });
    _open();
    _scheduleHide();
    // 与音频互斥：打开视频时若音频在播放则暂停（退出时恢复）
    _audioWasPlaying = AudioPlayerService().isPlaying;
    if (_audioWasPlaying) {
      AudioPlayerService().togglePause(); // isPlaying==true → 暂停
    }
    // 每 3 秒保存一次播放进度（seek 完成前跳过，避免 0 覆盖已存进度）
    _saveTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_seekDone) return;
      _saveProgress(_position);
    });
  }

  // 打开视频前音频是否在播放（退出时恢复）
  bool _audioWasPlaying = false;

  // 是否已完成恢复 seek（避免在 seek 前用 0 覆盖已存进度）
  bool _seekDone = false;

  Future<void> _open() async {
    final path = _song.videoPath ?? _song.filePath;
    final f = File(path);
    if (!f.existsSync()) return;
    // 先读进度，再打开媒体
    final saved = await _loadProgress();
    _vlog('open ${_song.bvid} saved=${saved?.inMilliseconds ?? -1}');
    _seekDone = false;
    await _player.open(Media(f.path));
    AudioPlayerService().acquireAudioFocus();
    await _player.setRate(_speed);
    if (saved != null && saved.inMilliseconds > 0) {
      // 等媒体真正就绪（duration>0）后再 seek，否则 seek 会被忽略
      await _waitReady();
      await _player.seek(saved);
      // Android media_kit 在媒体未就绪时可能静默忽略 seek：短暂等待后验证，失败重试
      await Future.delayed(const Duration(milliseconds: 800));
      final pos = _player.state.position;
      if (pos == null || pos == Duration.zero) {
        await _player.seek(saved);
        _vlog('seek retry -> ${saved.inMilliseconds}');
      } else {
        _vlog('seek ok -> ${pos.inMilliseconds}');
      }
      if (mounted) setState(() => _position = saved);
    }
    _seekDone = true;
  }

  /// 等待媒体就绪（duration 出现），最多 15 秒
  Future<void> _waitReady() async {
    if (_duration.inMilliseconds > 0) return;
    final completer = Completer<void>();
    StreamSubscription<Duration>? sub;
    sub = _player.stream.duration.listen((d) {
      if (d.inMilliseconds > 0 && !completer.isCompleted) {
        sub?.cancel();
        completer.complete();
      }
    });
    Timer(const Duration(seconds: 15), () {
      sub?.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  /// 读取视频进度（毫秒）
  Future<Duration?> _loadProgress() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ms = p.getInt(_progressKey);
      return ms != null ? Duration(milliseconds: ms) : null;
    } catch (_) {
      return null;
    }
  }

  /// 保存视频进度
  Future<void> _saveProgress(Duration pos) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_progressKey, pos.inMilliseconds);
    } catch (_) {}
  }

  /// 切换视频（上一个/下一个）
  Future<void> _switchTo(int index) async {
    final len = widget.videos?.length ?? 1;
    if (len <= 1) return;
    // 保存当前视频进度
    await _saveProgress(_position);
    _currentIndex = (index + len) % len;
    setState(() { _position = Duration.zero; _duration = Duration.zero; });
    await _open();
  }

  /// 隐藏控制 UI（用于自动隐藏）
  void _scheduleHide() {
    _uiTimer?.cancel();
    _uiTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_locked) setState(() => _controlsVisible = false);
    });
  }

  /// 点击画面：锁定 → 显示解锁按钮5秒；未锁定 → 切换控制栏显隐
  void _onTapVideo() {
    if (_locked) {
      setState(() => _showUnlockHint = true);
      _unlockHintTimer?.cancel();
      _unlockHintTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showUnlockHint = false);
      });
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  /// 进入/退出横屏全屏
  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.setFullScreen(true);
      } else {
        await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } else {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.setFullScreen(false);
      } else {
        await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
    setState(() {});
  }

  /// 进入/退出锁定：锁屏只隐藏所有 UI（不强制横屏/全屏）
  /// 锁定时沉浸式隐藏系统栏，解锁恢复系统栏（保持当前方向不变）
  Future<void> _toggleLock() async {
    final entering = !_locked;
    setState(() {
      _locked = entering;
      _showUnlockHint = false;
      _controlsVisible = !entering;
    });
    if (entering) {
      // 锁屏：仅隐藏系统 UI，不动窗口/方向（全屏与否保持原状）
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // 桌面：全屏状态由 _fullscreen 独立控制，锁屏只隐藏控制栏
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } else {
      // 解锁：恢复系统 UI（方向仍由 _fullscreen 决定，不强制改）
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // 桌面：无操作
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    // 保存最终播放进度（seek 未完成时跳过，避免覆盖已存进度）
    if (_seekDone) _saveProgress(_position);
    _posSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    _completeSub?.cancel();
    _uiTimer?.cancel();
    _unlockHintTimer?.cancel();
    _saveTimer?.cancel();
    _player.dispose();
    AudioPlayerService().releaseAudioFocus();
    // 与音频互斥：退出视频时恢复之前暂停的音频
    if (_audioWasPlaying) {
      AudioPlayerService().resume();
    }
    // 退出时恢复竖屏/退出全屏
    if (_fullscreen) {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        windowManager.setFullScreen(false);
      } else {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 锁定态：全屏沉浸式，无 AppBar/无控制栏，只有解锁提示按钮
    if (_locked) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(child: _videoView()),
          // 透明点击层（在 Video 上层，确保点击屏幕被捕获）
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onTapVideo,
              onDoubleTap: () {
                if (_playing) {
                  _player.pause();
                  AudioPlayerService().releaseAudioFocus();
                } else {
                  _player.play();
                  AudioPlayerService().acquireAudioFocus();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
          // 解锁按钮提示（点击屏幕后显示5秒；位置与右上角锁定按钮一致）
          if (_showUnlockHint)
            Positioned(
              top: 12,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.lock_open, color: Colors.white, size: 24),
                onPressed: _toggleLock,
              ),
            ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_song.title, style: const TextStyle(fontSize: 15)), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.fullscreen, size: 20), onPressed: _toggleFullscreen),
        IconButton(icon: const Icon(Icons.lock, size: 20), onPressed: _toggleLock),
      ]),
      body: Stack(children: [
        // 视频画面（始终显示）
        Positioned.fill(child: _videoView()),
        // 透明点击层（在 Video 上层，点击画面切换控制栏显隐；双击播放/暂停）
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTapVideo,
            onDoubleTap: () {
              if (_playing) { _player.pause(); } else { _player.play(); }
            },
            child: const SizedBox.expand(),
          ),
        ),
        // 中央播放图标：仅控制栏可见且暂停时显示；点击=播放（不隐藏控制栏）
        if (_controlsVisible && !_playing)
          Center(
            child: GestureDetector(
              onTap: () {
                _player.play();
                AudioPlayerService().acquireAudioFocus();
                _scheduleHide();
              },
              child: Icon(
                Icons.play_circle,
                size: 64,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
        // 底部：进度条 + 按钮区（随控制栏显隐，UI 隐藏时连进度条一起隐藏）
        if (_controlsVisible)
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _buildProgress(),
              _buildControls(),
            ]),
          ),
      ]),
    );
  }

  /// 视频画面（统一封装）
  Widget _videoView() {
    return Center(
      child: _controller == null
          ? const CircularProgressIndicator()
          : Video(
              controller: _controller!,
              controls: NoVideoControls,
              wakelock: false,
            ),
    );
  }

  /// 进度条（始终显示，独立于按钮区）
  Widget _buildProgress() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Slider(
          value: _duration.inMilliseconds > 0 ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0) : 0,
          onChanged: (v) => _player.seek(Duration(milliseconds: (v * _duration.inMilliseconds).round())),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            Text(_fmt(_position), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const Spacer(),
            Text(_fmt(_duration), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
      ]),
    );
  }

  /// 底部按钮区（随控制栏显隐）
  Widget _buildControls() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          IconButton(
            icon: const Icon(Icons.skip_previous, size: 28, color: Colors.white),
            onPressed: () => _switchTo(_currentIndex - 1),
          ),
          IconButton(
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 36, color: Colors.deepPurple),
            onPressed: () {
              if (_playing) {
                _player.pause();
                AudioPlayerService().releaseAudioFocus();
              } else {
                _player.play();
                AudioPlayerService().acquireAudioFocus();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.skip_next, size: 28, color: Colors.white),
            onPressed: () => _switchTo(_currentIndex + 1),
          ),
          const Spacer(),
          // 选集：弹出视频列表（全屏显示封面+名字，非全屏只显示名字）
          if (widget.videos != null && widget.videos!.length > 1)
            IconButton(
              icon: const Icon(Icons.video_collection_outlined, size: 24, color: Colors.white),
              tooltip: '选集',
              onPressed: _showEpisodeList,
            ),
          // 倍速
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed, size: 22, color: Colors.grey),
            onSelected: (s) async { _speed = s; await _player.setRate(s); setState(() {}); },
            itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) => PopupMenuItem(
              value: s,
              child: Text('${s}x', style: TextStyle(fontWeight: _speed == s ? FontWeight.bold : FontWeight.normal, color: _speed == s ? Colors.deepPurple : null)),
            )).toList(),
          ),
          Text('${_speed}x', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ]),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// 选集：弹出视频列表
  /// 全屏（横屏）→ 显示封面+名字的横向大卡片；非全屏 → 只显示名字的紧凑列表
  void _showEpisodeList() {
    final videos = widget.videos ?? <Song>[];
    if (videos.length < 2) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('选集（${videos.length}个视频）', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          Expanded(
            child: _fullscreen
                // 全屏/横屏：横向大卡片，封面+名字
                ? GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, childAspectRatio: 0.75, crossAxisSpacing: 8, mainAxisSpacing: 8,
                    ),
                    itemCount: videos.length,
                    itemBuilder: (_, i) => _episodeCard(videos[i], i, ctx),
                  )
                // 非全屏：紧凑列表，只显示名字
                : ListView.builder(
                    itemCount: videos.length,
                    itemBuilder: (_, i) => _episodeRow(videos[i], i, ctx),
                  ),
          ),
        ]),
      ),
    );
  }

  /// 全屏选集卡片：封面 + 名字
  Widget _episodeCard(Song v, int i, BuildContext ctx) {
    final cur = i == _currentIndex;
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        _switchTo(i);
      },
      borderRadius: BorderRadius.circular(8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(fit: StackFit.expand, children: [
              _episodeCover(v),
              if (cur)
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.35), child: const Center(child: Icon(Icons.play_arrow, color: Colors.white, size: 32))),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 4),
        Text(v.title, style: TextStyle(fontSize: 11, color: cur ? Colors.deepPurple : null), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  /// 非全屏选集行：只显示名字
  Widget _episodeRow(Song v, int i, BuildContext ctx) {
    final cur = i == _currentIndex;
    return ListTile(
      dense: true,
      leading: Icon(cur ? Icons.play_arrow : Icons.movie_outlined, size: 18, color: cur ? Colors.deepPurple : Colors.grey),
      title: Text(v.title, style: TextStyle(fontSize: 13, color: cur ? Colors.deepPurple : null), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        Navigator.pop(ctx);
        _switchTo(i);
      },
    );
  }

  /// 选集封面（无封面时用占位）
  Widget _episodeCover(Song v) {
    if (v.coverUrl != null && v.coverUrl!.isNotEmpty) {
      final f = File(v.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        return Image.file(f, fit: BoxFit.cover);
      }
    }
    return Container(color: Colors.grey[800], child: const Center(child: Icon(Icons.movie, color: Colors.grey, size: 28)));
  }
}
