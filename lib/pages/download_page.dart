import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';
import '../services/bilibili_api.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import '../widgets/top_toast.dart';
import '../models/music_data.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});
  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _authorController = TextEditingController();
  final _api = BilibiliApi();

  bool _downloadVideo = false;
  bool _downloadAudio = true;
  bool _isParsing = false;
  bool _isDownloading = false;
  bool _cancelling = false; // 点击取消后的即时反馈
  ValueNotifier<bool>? _cancelNotifier;
  String _downloadingTitle = '';
  int _downloadingSize = 0;
  double _downloadProgress = 0;
  int _downloadedBytes = 0; // 已下载字节（total 未知时用于容量显示）
  int _speedLastBytes = 0; // 速度计算：上次字节
  DateTime _speedLastTime = DateTime.now(); // 速度计算：上次时间

  void _updateItemSpeed(_BatchItem item, int received) {
    final now = DateTime.now();
    final dt = now.difference(_speedLastTime).inMilliseconds;
    if (_speedLastBytes > 0 && dt > 400) {
      item.speed = (received - _speedLastBytes) / (dt / 1000);
    }
    _speedLastBytes = received; _speedLastTime = now;
  }

  BilibiliVideoInfo? _singleInfo;
  VideoStream? _selectedStream;
  bool _alreadyDownloaded = false;
  bool _coverMissing = false;
  bool _videoMissing = false;

  // 批量下载
  List<_BatchItem> _batchItems = [];
  int _batchTotal = 0;
  int _batchDone = 0;

  String? _downloadDir;

  @override
  void initState() {
    super.initState();
    _initDir();
  }

  Future<void> _initDir() async {
    try {
      final s = await SettingsService.getInstance();
      final d = await s.getDownloadPath();
      if (mounted) setState(() => _downloadDir = d);
    } catch (_) {}
  }

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  // ==================== 解析 ====================

  Future<void> _parseUrl() async {
    var url = _urlController.text.trim();
    if (url.isEmpty) return;
    // 从分享文本中提取所有 URL（可多个链接）
    final urls = RegExp(r'https?://\S+').allMatches(url).map((m) {
      var u = m.group(0)!;
      // 去掉 URL 尾部可能带上的中文标点
      return u.replaceFirst(RegExp(r'[^A-Za-z0-9/:_?=&.%-]+$'), '');
    }).toList();
    if (urls.isEmpty) return;

    setState(() {
      _isParsing = true; _singleInfo = null; _batchItems = [];
      _alreadyDownloaded = false; _downloadVideo = false;
    });

    // 逐个链接解析，结果合并到批量列表
    var gotAny = false;
    var failedCount = 0;
    for (var raw in urls) {
      // b23.tv 短链先解析成真实 URL
      final resolved = await BilibiliApi.resolveShortUrl(raw);
      if (!mounted) return;

      if (_isCollectionUrl(resolved)) {
        final videos = await _api.getCollectionVideos(resolved);
        if (videos != null && videos.isNotEmpty) {
          setState(() {
            _batchItems.addAll(videos.map((v) => _BatchItem(info: v, name: v.bvid, exists: _fileExists(v.bvid, _safeName(v.title)))));
          });
          gotAny = true;
        } else {
          failedCount++;
        }
      } else {
        final info = await _api.getVideoInfo(resolved);
        if (!mounted) return;
        if (info != null) {
          setState(() {
            _batchItems.add(_BatchItem(info: info, name: info.bvid, exists: _fileExists(info.bvid, _safeName(info.title))));
          });
          gotAny = true;
        } else {
          failedCount++;
        }
      }
    }

    if (!mounted) return;
    if (!gotAny) {
      setState(() => _isParsing = false);
      _snack(failedCount > 0 ? '解析失败：$failedCount 个链接无法解析' : '未找到可解析的链接');
      return;
    }
    if (_batchItems.length == 1 && !_isCollectionUrl(urls.length == 1 ? urls.first : '')) {
      // 单个普通视频：走单曲详情
      final info = _batchItems.first.info;
      await _checkSingleExists(info);
      setState(() {
        _singleInfo = info;
        _batchItems = [];
        _isParsing = false;
        _nameController.text = info.bvid;
        _authorController.text = info.author;
        _selectedStream = info.videoStreams.isNotEmpty ? info.videoStreams.first : null;
      });
    } else {
      setState(() => _isParsing = false);
      _snack('解析完成：${_batchItems.length} 个音视频');
    }
  }

  bool _fileExists(String bvid, String titleName) {
    try {
      final dir = _downloadDir ?? '';
      bool has(String n) => File('$dir/$n.m4a').existsSync() && File('$dir/$n.m4a').lengthSync() > 0;
      // 同时匹配 BV号命名（旧版本）与标题命名（当前版本）的下载文件
      return has(bvid) || has(titleName);
    } catch (_) { return false; }
  }

  bool _isCollectionUrl(String url) =>
      url.contains('/list/ml') || url.contains('medialist') ||
      (url.contains('list.bilibili.com') && (url.contains('ml') || url.contains('fid'))) ||
      (url.contains('fid=') && url.contains('space.bilibili.com'));

  Future<void> _parseCollection(String url) async {
    final videos = await _api.getCollectionVideos(url);
    if (!mounted) return;
    if (videos == null || videos.isEmpty) {
      // 回退普通解析
      final info = await _api.getVideoInfo(url);
      if (!mounted) return;
      if (info != null) {
        await _checkSingleExists(info);
        setState(() {
          _singleInfo = info; _isParsing = false;
          _nameController.text = info.bvid;
          _authorController.text = info.author;
          _selectedStream = info.videoStreams.isNotEmpty ? info.videoStreams.first : null;
        });
      } else {
        setState(() => _isParsing = false);
        _snack('解析失败');
      }
      return;
    }

    final dir = _downloadDir ?? '';
    setState(() {
      _batchItems = videos.map((v) {
        final name = v.bvid;
        return _BatchItem(info: v, exists: _fileExists(v.bvid, v.title), name: name);
      }).toList();
      _isParsing = false;
    });
  }

  Future<void> _checkSingleExists(BilibiliVideoInfo info) async {
    if (_downloadDir == null) await _initDir();
    final dir = _downloadDir ?? '';
    final name = info.bvid;
    final hasAudio = File('$dir/$name.m4a').existsSync();
    final hasCover = File('$dir/$name.jpg').existsSync();
    final hasVideo = File('$dir/$name.mp4').existsSync();
    _alreadyDownloaded = hasAudio && hasCover && hasVideo;
    _coverMissing = hasAudio && !hasCover;
    _videoMissing = hasAudio && hasCover && !hasVideo;
  }

  String _fmtSpeed(double bytesPerSec) {
    if (bytesPerSec >= 1048576) return '${(bytesPerSec / 1048576).toStringAsFixed(1)}MB/s';
    if (bytesPerSec >= 1024) return '${(bytesPerSec / 1024).toStringAsFixed(0)}KB/s';
    return '${bytesPerSec.toStringAsFixed(0)}B/s';
  }

  void _dlog(String msg) {
    try {
      final dir = _downloadDir ?? '';
      File('$dir/debug.log').writeAsStringSync('[$_now] $msg\n', mode: FileMode.append);
    } catch (_) {}
  }
  static String get _now => DateTime.now().toIso8601String().substring(11, 19);

  void _snack(String msg) {
    if (mounted) showTopToast(context, msg);
  }

  void _saveMeta(String dir, String name, String author, BilibiliVideoInfo info) {
    // 全部下载成功后才在 SongManager 统一登记
  }

  // ==================== 单个下载 ====================

  static void _foregroundCallback() {
    FlutterForegroundTask.updateService(
      notificationTitle: 'GoMusic 下载中',
      notificationText: '正在下载歌曲...',
    );
  }

  Future<void> _startSingle() async {
    final info = _singleInfo;
    if (info == null || info.audioUrl == null) { _dlog('startSingle: audioUrl null'); _snack('无下载地址'); return; }
    if (_downloadDir == null) {
      await _initDir();
      if (_downloadDir == null) { _snack('下载目录初始化失败'); return; }
    }
    final dir = _downloadDir!;
    _dlog('startSingle dir=$dir url=${info.audioUrl!.substring(0, info.audioUrl!.length > 40 ? 40 : info.audioUrl!.length)}... size=${info.audioSize}');
    final name = info.bvid;  // 用BV号做文件名，纯英文
    SongManager.init(dir);   // 确保metadata目录已初始化

    setState(() { _isDownloading = true; _downloadProgress = 0; _downloadingTitle = info.title; });
    _cancelNotifier = ValueNotifier(false);
    if (Platform.isAndroid) {
      final notif = await Permission.notification.request();
      if (notif.isDenied || notif.isPermanentlyDenied) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('需要通知权限'),
              content: const Text('后台下载需要通知权限（显示下载进度）。请在设置中开启通知。'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消下载')),
                FilledButton(onPressed: () {
                  Navigator.pop(ctx);
                  openAppSettings();
                }, child: const Text('去设置开启')),
              ],
            ),
          );
        }
        setState(() => _isDownloading = false);
        return;
      }
      FlutterForegroundTask.startService(
        serviceId: 100,
        notificationTitle: 'GoMusic 下载中',
        notificationText: info.title,
        callback: _foregroundCallback,
      );
    }

    // 封面（失败不影响主流程）
    var coverFailed = false;
    if (info.coverUrl.isNotEmpty) {
      final ok = await StreamDownloader.download(url: info.coverUrl, savePath: '$dir/$name.jpg', onProgress: (_) {});
      coverFailed = !ok;
    } else {
      // 没有封面 URL 也视为缺封面
      coverFailed = true;
    }
    if (coverFailed) {
      setState(() { _isDownloading = false; _cancelling = false; _downloadingTitle = ''; });
      _snack('下载失败：封面下载失败');
      return;
    }
    // 音频（勾选才下载；已存在跳过）
    var audioOk = true;
    if (_downloadAudio) {
      final hasAudio = File('$dir/$name.m4a').existsSync() && File('$dir/$name.m4a').lengthSync() > 0;
      if (!hasAudio) {
        _downloadingSize = info.audioSize;
        var lastUi = DateTime.now();
        audioOk = await StreamDownloader.download(
          url: info.audioUrl!, savePath: '$dir/$name.m4a',
          onProgress: (p) {
            final now = DateTime.now();
            if (now.difference(lastUi).inMilliseconds >= 400) {
              lastUi = now;
              final prog = p * (_downloadVideo ? 0.5 : 1.0);
              if (Platform.isAndroid) {
                FlutterForegroundTask.updateService(
                  notificationTitle: 'GoMusic 下载中',
                  notificationText: '${info.title} ${(prog * 100).toStringAsFixed(0)}%',
                );
              }
              if (mounted) setState(() => _downloadProgress = prog);
            }
          },
          onSize: (received, total) {
            if (mounted) {
              _downloadedBytes = received;
              if (total > 0) _downloadingSize = total;
              final now2 = DateTime.now();
              if (now2.difference(lastUi).inMilliseconds >= 400) {
                lastUi = now2;
                setState(() {});
              }
            }
          },
          cancel: _cancelNotifier,
          expectedSize: info.audioSize > 0 ? info.audioSize : null,
        );
      }
    }
    // 视频（勾选才下载）
    var videoOk = true;
    if (_downloadVideo) {
      if (_selectedStream?.baseUrl != null) {
        final audioFile = File('$dir/$name.m4a');
        // durl 合并流场景：音频流 URL 与视频流相同（MP4 自带音轨），直接拷贝避免重复下载
        if (info.audioUrl != null && _selectedStream!.baseUrl == info.audioUrl && audioFile.existsSync()) {
          try {
            audioFile.copySync('$dir/$name.mp4');
            videoOk = true;
          } catch (_) { videoOk = false; }
        } else {
          _downloadingSize = _selectedStream!.size;
          var lastUi2 = DateTime.now();
          videoOk = await StreamDownloader.download(
            url: _selectedStream!.baseUrl!, savePath: '$dir/$name.mp4',
            onProgress: (p) {
              final now = DateTime.now();
              if (now.difference(lastUi2).inMilliseconds >= 400) {
                lastUi2 = now;
                final prog = 0.5 + p * 0.5;
                if (Platform.isAndroid) {
                  FlutterForegroundTask.updateService(
                    notificationTitle: 'GoMusic 下载中',
                    notificationText: '${info.title} ${(prog * 100).toStringAsFixed(0)}%',
                  );
                }
                if (mounted) setState(() => _downloadProgress = prog);
              }
            },
            onSize: (received, total) {
              if (mounted) {
                _downloadedBytes = received;
                if (total > 0) _downloadingSize = total;
                final now2 = DateTime.now();
                if (now2.difference(lastUi2).inMilliseconds >= 400) {
                  lastUi2 = now2;
                  setState(() {});
                }
              }
            },
            cancel: _cancelNotifier,
            expectedSize: _selectedStream!.size > 0 ? _selectedStream!.size : null,
          );
        }
      } else {
        videoOk = false;
      }
    }

    if (!mounted) return;
    String sizeText = '';
    try { final f = File('$dir/$name.m4a'); if (f.existsSync()) sizeText = '${(f.lengthSync() / 1048576).toStringAsFixed(1)} MB'; } catch (_) {}

    // 最终校验：勾选的音频/视频 + 封面，任一缺失 = 下载失败
    final needAudio = _downloadAudio ? (File('$dir/$name.m4a').existsSync() && File('$dir/$name.m4a').lengthSync() > 0) : true;
    final needVideo = _downloadVideo ? (File('$dir/$name.mp4').existsSync() && File('$dir/$name.mp4').lengthSync() > 0) : true;
    final needCover = File('$dir/$name.jpg').existsSync() && File('$dir/$name.jpg').lengthSync() > 0;
    final allOk = audioOk && videoOk && needAudio && needVideo && needCover;
    if (!allOk) {
      // 清理残留，避免"已下载"误判
      try {
        if (!needAudio) File('$dir/$name.m4a').deleteSync();
        if (!needVideo) File('$dir/$name.mp4').deleteSync();
        if (!needCover) File('$dir/$name.jpg').deleteSync();
      } catch (_) {}
      setState(() { _isDownloading = false; _cancelling = false; _downloadingTitle = ''; });
      _snack('下载失败：文件不完整（${needCover ? "" : "封面"}${needAudio ? "" : "音频"}${needVideo ? "" : "视频"}缺失）');
      return;
    }
    // 完全下载成功后才登记（不受页面切换影响）
    if (audioOk && videoOk) {
      SongManager.registerSong(
        filePath: '$dir/$name.m4a',
        title: info.title,
        uploader: _authorController.text.trim(),
        durationSec: info.durationSeconds,
        bvid: info.bvid,
        url: info.url,
        coverPath: '$dir/$name.jpg',
      );
    }
    // 视频下载成功：登记到唯一元数据文件
    if (videoOk && _downloadVideo) {
      SongManager.registerVideoPath('$dir/$name.m4a', '$dir/$name.mp4');
    }
    // 通知其他页面（视频页/歌单页）自动刷新
    if (audioOk || videoOk) downloadsChangedNotifier.value++;
    if (!mounted) return;
    _cancelNotifier?.value = false;
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadingTitle = '';
      });
      // 通知主界面刷新（下载完成后本地歌单/历史记录立即更新）
      AudioPlayerService().favoritesChangedNotifier.value++;
    }
    if (Platform.isAndroid) FlutterForegroundTask.stopService();
    await _checkSingleExists(info);
    _snack('${audioOk && videoOk ? "下载完成" : (_cancelNotifier?.value == true ? "已取消" : "下载失败")} $sizeText${coverFailed ? " ⚠封面下载失败" : ""}');
  }

  // ==================== 批量下载 ====================

  Future<void> _startBatch() async {
    _cancelNotifier = ValueNotifier(false);
    setState(() { _isDownloading = true; _batchTotal = 0; _batchDone = 0; });
    SongManager.init(_downloadDir!);

    final toDownload = _batchItems.where((b) => !b.exists).toList();
    _batchTotal = toDownload.length;

    for (final item in toDownload) {
      if (!mounted) return;
      if (_cancelNotifier?.value == true) { setState(() {}); break; }
      setState(() => item.status = _BatchStatus.downloading);

      final full = await _api.getVideoInfo(item.info.url);
      if (full?.audioUrl == null) {
        setState(() => item.status = _BatchStatus.failed);
        _batchDone++;
        continue;
      }

      // 封面（失败 = 该项下载失败）
      var coverOk = true;
      if (full!.coverUrl.isNotEmpty) {
        coverOk = await StreamDownloader.download(url: full.coverUrl, savePath: '${_downloadDir}/${item.name}.jpg', onProgress: (_) {}, cancel: _cancelNotifier);
      } else {
        coverOk = false;
      }
      if (!coverOk) {
        if (mounted) setState(() => item.status = _BatchStatus.failed);
        _batchDone++;
        continue;
      }
      // 音频（勾选才下载）
      var audioOk = true;
      if (_downloadAudio) {
        _speedLastBytes = 0; _speedLastTime = DateTime.now();
        audioOk = await StreamDownloader.download(
          url: full.audioUrl!, savePath: '${_downloadDir}/${item.name}.m4a',
          onProgress: (p) { if (mounted) setState(() => _downloadProgress = (_batchDone + p) / _batchTotal); },
          onSize: (received, total) { if (mounted) setState(() { _updateItemSpeed(item, received); item.progress = total > 0 ? (received / total) * 0.5 : item.progress; }); },
          cancel: _cancelNotifier,
        );
      }
      // 视频（勾选才下载）
      var videoOk = true;
      if (_downloadVideo && full.videoStreams.isNotEmpty) {
        final best = full.videoStreams.first;
        final audioFile = File('${_downloadDir}/${item.name}.m4a');
        // durl 合并流场景：视频流 URL 与音频流相同，直接拷贝避免重复下载
        if (full.audioUrl != null && best.baseUrl == full.audioUrl && audioFile.existsSync()) {
          try {
            audioFile.copySync('${_downloadDir}/${item.name}.mp4');
            videoOk = true;
          } catch (_) { videoOk = false; }
        } else {
          videoOk = await StreamDownloader.download(
            url: best.baseUrl!, savePath: '${_downloadDir}/${item.name}.mp4',
            expectedSize: best.size > 0 ? best.size : null,
            onProgress: (p) { if (mounted) setState(() => _downloadProgress = (_batchDone + p) / _batchTotal); },
            onSize: (received, total) { if (mounted) setState(() { _updateItemSpeed(item, received); item.progress = total > 0 ? 0.5 + (received / total) * 0.5 : item.progress; }); },
            cancel: _cancelNotifier,
          );
        }
      }

      // 最终校验：勾选的音频/视频 + 封面，任一缺失 = 失败
      final needAudio = _downloadAudio ? (File('${_downloadDir}/${item.name}.m4a').existsSync() && File('${_downloadDir}/${item.name}.m4a').lengthSync() > 0) : true;
      final needVideo = _downloadVideo ? (File('${_downloadDir}/${item.name}.mp4').existsSync() && File('${_downloadDir}/${item.name}.mp4').lengthSync() > 0) : true;
      final needCover = File('${_downloadDir}/${item.name}.jpg').existsSync() && File('${_downloadDir}/${item.name}.jpg').lengthSync() > 0;
      final ok = audioOk && videoOk && needAudio && needVideo && needCover;
      if (!ok) {
        if (_cancelNotifier?.value == true) {
          if (mounted) setState(() => item.status = _BatchStatus.waiting);
          _batchDone++;
          continue;
        }
        // 清理残留
        try {
          if (!needAudio) File('${_downloadDir}/${item.name}.m4a').deleteSync();
          if (!needVideo) File('${_downloadDir}/${item.name}.mp4').deleteSync();
          if (!needCover) File('${_downloadDir}/${item.name}.jpg').deleteSync();
        } catch (_) {}
        if (mounted) setState(() => item.status = _BatchStatus.failed);
        _batchDone++;
        continue;
      }
      if (ok) {
        item.exists = true;
        SongManager.registerSong(
          filePath: '${_downloadDir}/${item.name}.m4a',
          title: full.title, uploader: full.author, durationSec: full.durationSeconds,
          bvid: full.bvid, url: full.url,
          coverPath: '${_downloadDir}/${item.name}.jpg',
          videoPath: _downloadVideo && File('${_downloadDir}/${item.name}.mp4').existsSync() ? '${_downloadDir}/${item.name}.mp4' : null,
        );
      }
      setState(() {
        item.status = ok ? _BatchStatus.done : _BatchStatus.failed;
        if (ok) item.exists = true;
        _batchDone++;
      });
    }

    if (!mounted) return;
    setState(() { _isDownloading = false; _cancelling = false; });
    // 通知主界面刷新（下载完成后本地歌单/历史记录立即更新）
    AudioPlayerService().favoritesChangedNotifier.value++;
    downloadsChangedNotifier.value++;
    _snack('批量下载完成: $_batchDone/$_batchTotal');
  }

  String _safeName(String s) {
    // 替换非法字符并截断到安全长度
    var name = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (name.length > 80) name = name.substring(0, 80);
    return name;
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载'), centerTitle: true),
      body: Column(children: [
        _buildUrlInput(),
        // 下载进度固定在顶部
        if (_isDownloading) _buildProgressBar(),
        // 内容区可滚动
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(children: [
            if (_isParsing) _buildLoading(),
            if (_singleInfo != null) _buildSingleResult(),
            if (_batchItems.isNotEmpty) _buildBatchResult(),
            const SizedBox(height: 80),
          ]),
        )),
      ]),
      // 固定底部按钮
      bottomSheet: _buildBottomBar(),
    );
  }

  // ---- URL输入 ----
  Widget _buildUrlInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: '粘贴B站分享链接或视频/收藏夹链接...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.link, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                tooltip: '',
                onPressed: () => setState(() => _urlController.clear()),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => _parseUrl(),
            contextMenuBuilder: (ctx, editableTextState) {
              final items = editableTextState.contextMenuButtonItems;
              // 翻译成中文
              final names = {
                ContextMenuButtonType.copy: '复制',
                ContextMenuButtonType.paste: '粘贴',
                ContextMenuButtonType.cut: '剪切',
                ContextMenuButtonType.selectAll: '全选',
                ContextMenuButtonType.delete: '删除',
              };
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: editableTextState.contextMenuAnchors,
                buttonItems: items.map((item) => ContextMenuButtonItem(
                  type: item.type,
                  label: names[item.type] ?? item.label,
                  onPressed: item.onPressed,
                )).toList(),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: _isParsing ? null : _parseUrl,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
          child: _isParsing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('解析'),
        ),
      ]),
    );
  }

  // ---- 加载中 ----
  Widget _buildLoading() {
    return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()));
  }

  // ---- 单个视频结果 ----
  Widget _buildSingleResult() {
    final info = _singleInfo!;
    return Column(children: [
      const SizedBox(height: 12),
      _buildInfoCard(info),
      if (_alreadyDownloaded)
        _buildAlreadyBadge(),
      if (_coverMissing)
        _buildCoverMissingBadge(),
      if (_videoMissing)
        _buildVideoMissingBadge(),
      if (!_alreadyDownloaded && !_coverMissing) ...[
        if (info.videoStreams.length > 1) _buildQualityPicker(),
        const SizedBox(height: 12),
        _buildEditableFields(),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.music_note, color: Colors.grey, size: 18),
          const SizedBox(width: 4),
          const Text('下载音频', style: TextStyle(fontSize: 14)),
          const Spacer(),
          Switch(value: _downloadAudio, onChanged: _isDownloading ? null : (v) => setState(() => _downloadAudio = v)),
        ]),
        Row(children: [
          const Icon(Icons.video_file_outlined, color: Colors.grey, size: 18),
          const SizedBox(width: 4),
          Text(_videoMissing ? '下载视频' : '下载视频', style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Switch(value: _downloadVideo, onChanged: _isDownloading ? null : (v) => setState(() => _downloadVideo = v)),
        ]),
      ],
      // 下载进度（单独显示，不受条件控制）
      if (_isDownloading) ...[
        const SizedBox(height: 12),
      ],
    ]);
  }

  Widget _buildAlreadyBadge() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.check_circle, color: Colors.green, size: 16),
        SizedBox(width: 6),
        Text('本地已下载', style: TextStyle(color: Colors.green, fontSize: 13)),
      ]),
    );
  }

  Widget _buildVideoMissingBadge() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.video_file_outlined, color: Colors.orange, size: 16),
        SizedBox(width: 6),
        Text('音频已下载，视频未下载', style: TextStyle(color: Colors.orange, fontSize: 13)),
      ]),
    );
  }

  Widget _buildCoverMissingBadge() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
        const SizedBox(width: 6),
        const Text('封面缺失', style: TextStyle(color: Colors.orange, fontSize: 13)),
        const SizedBox(width: 8),
        SizedBox(
          height: 26,
          child: ElevatedButton.icon(
            onPressed: _redownloadCover,
            icon: const Icon(Icons.download, size: 14),
            label: const Text('补下封面', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
          ),
        ),
      ]),
    );
  }

  Future<void> _redownloadCover() async {
    final info = _singleInfo;
    if (info == null || info.coverUrl.isEmpty) return;
    final dir = _downloadDir ?? '';
    final name = _safeName(_nameController.text.trim());
    final ok = await StreamDownloader.download(
      url: info.coverUrl, savePath: '$dir/$name.jpg', onProgress: (_) {},
    );
    if (ok) {
      setState(() {
        _coverMissing = false;
        _alreadyDownloaded = true;
      });
      _snack('封面已补下');
    } else {
      _snack('封面下载失败');
    }
  }

  Widget _buildInfoCard(BilibiliVideoInfo info) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(8),
          child: info.coverUrl.isNotEmpty
              ? Image.network(info.coverUrl, width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (_, e, s) => _placeholder())
              : _placeholder()),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(info.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('${info.author} · ${info.durationText}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 2),
          Text('音频 ${info.audioSizeText} | 视频 ${_selectedStream?.sizeText ?? '未知'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text('BV: ${info.bvid}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ])),
      ])),
    );
  }

  Widget _placeholder() => Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.image, color: Colors.grey, size: 30));

  Widget _buildQualityPicker() {
    final streams = _singleInfo!.videoStreams;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
        child: DropdownButton<VideoStream>(
          value: _selectedStream ?? streams.first, isExpanded: true, underline: const SizedBox(),
          items: streams.map((s) => DropdownMenuItem(value: s, child: Text(s.description, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) { if (v != null) setState(() => _selectedStream = v); },
        )),
    );
  }

  Widget _buildEditableFields() {
    return Column(children: [
      TextField(controller: _nameController, decoration: const InputDecoration(labelText: '本地名称', border: OutlineInputBorder(), isDense: true), style: const TextStyle(fontSize: 13)),
      const SizedBox(height: 8),
      TextField(controller: _authorController, decoration: const InputDecoration(labelText: '本地作者', border: OutlineInputBorder(), isDense: true), style: const TextStyle(fontSize: 13)),
    ]);
  }

  Widget _buildProgressBar() {
    final pct = (_downloadProgress * 100).toStringAsFixed(0);
    final name = _singleInfo != null ? _nameController.text.trim() : '';
    final batch = _batchItems.isNotEmpty ? '${_batchDone}/${_batchTotal}' : '';
    // 已下载容量（total 未知时按估算字节显示）
    String sizeText = '';
    if (_downloadedBytes > 0) {
      sizeText = _downloadedBytes >= 1048576
          ? '${(_downloadedBytes / 1048576).toStringAsFixed(1)}MB'
          : '${(_downloadedBytes / 1024).toStringAsFixed(0)}KB';
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.deepPurple.withValues(alpha: 0.12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (batch.isNotEmpty) Text('下载 $batch 首', style: TextStyle(fontSize: 11, color: Colors.grey)),
        if (name.isNotEmpty) Text(name, style: TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        SizedBox(height: 6),
        Row(children: [
          Expanded(child: LinearProgressIndicator(value: _downloadProgress, minHeight: 6)),
          SizedBox(width: 12),
          if (sizeText.isNotEmpty) Text(sizeText, style: TextStyle(fontSize: 11, color: Colors.grey)),
          if (sizeText.isNotEmpty) SizedBox(width: 6),
          Text('$pct%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  // ---- 批量下载结果 ----
  Widget _buildBatchResult() {
    return Column(children: [
      const SizedBox(height: 8),
      Row(children: [
        Text('收藏夹 · ${_batchItems.length}个视频', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('音频', style: const TextStyle(fontSize: 11)),
        Switch(value: _downloadAudio, onChanged: _isDownloading ? null : (v) => setState(() => _downloadAudio = v)),
        Text('视频', style: const TextStyle(fontSize: 11)),
        Switch(value: _downloadVideo, onChanged: _isDownloading ? null : (v) => setState(() => _downloadVideo = v)),
        Text('已完成 ${_batchItems.where((b) => b.exists || b.status == _BatchStatus.done).length}/${_batchItems.length}',
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
      ..._batchItems.map((item) => _buildBatchRow(item)),
      const SizedBox(height: 12),
    ]);
  }

  Widget _buildBatchRow(_BatchItem item) {
    IconData icon; Color color; String label;
    switch (item.status) {
      case _BatchStatus.done: icon = Icons.check_circle; color = Colors.green; label = '已下载'; break;
      case _BatchStatus.downloading: icon = Icons.downloading; color = Colors.orange; label = '下载中'; break;
      case _BatchStatus.failed: icon = Icons.error; color = Colors.red; label = '失败'; break;
      case _BatchStatus.waiting: icon = Icons.hourglass_empty; color = Colors.grey; label = '等待'; break;
    }
    if (item.exists && item.status == _BatchStatus.waiting) {
      icon = Icons.check_circle; color = Colors.green; label = '已下载';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color, size: 20),
        title: Text(item.info.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        subtitle: Text('${item.info.author} · ${item.info.durationText} · 音频${item.info.audioSizeText}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (item.status == _BatchStatus.failed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.orange, size: 18),
                padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                onPressed: () => _retryItem(item),
              ),
            ),
          if (item.status == _BatchStatus.downloading) ...[
            SizedBox(
              width: 90,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: item.progress.clamp(0.0, 1.0), minHeight: 5, backgroundColor: Colors.grey.withValues(alpha: 0.2), color: Colors.orange),
              ),
            ),
            const SizedBox(width: 6),
            Text('${(item.progress * 100).clamp(0, 100).toStringAsFixed(0)}% ${item.speed > 0 ? _fmtSpeed(item.speed) : ""}', style: const TextStyle(fontSize: 10, color: Colors.orange)),
          ] else ...[
            Text(_downloadVideo ? '🎵🎬' : '🎵', style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, color: color)),
          ]
        ]),
      ),
    );
  }

  Future<void> _retryItem(_BatchItem item) async {
    // 并发防护：有下载任务进行中时不允许重试，避免多首同时下载
    if (_isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('有下载任务进行中，请等待当前下载完成'), duration: Duration(seconds: 2)));
      return;
    }
    setState(() { item.status = _BatchStatus.downloading; item.exists = false; item.progress = 0; item.speed = 0; });
    SongManager.init(_downloadDir!);

    final full = await _api.getVideoInfo(item.info.url);
    if (full?.audioUrl == null) { setState(() => item.status = _BatchStatus.failed); return; }

    // 封面（失败 = 该项下载失败）
    var coverOk = true;
    if (full!.coverUrl.isNotEmpty) {
      coverOk = await StreamDownloader.download(url: full.coverUrl, savePath: '${_downloadDir}/${item.name}.jpg', onProgress: (_) {}, cancel: _cancelNotifier);
    } else {
      coverOk = false;
    }
    // 音频（勾选才下载）
    var audioOk = true;
    if (_downloadAudio) {
      _speedLastBytes = 0; _speedLastTime = DateTime.now();
      audioOk = await StreamDownloader.download(
        url: full.audioUrl!, savePath: '${_downloadDir}/${item.name}.m4a',
        onProgress: (_) {},
        onSize: (received, total) { if (mounted) setState(() { _updateItemSpeed(item, received); item.progress = total > 0 ? (received / total) * 0.5 : item.progress; }); },
        cancel: _cancelNotifier,
      );
    }
    // 视频（勾选才下载）
    var videoOk = true;
    if (_downloadVideo && full.videoStreams.isNotEmpty) {
      final best = full.videoStreams.first;
      final audioFile = File('${_downloadDir}/${item.name}.m4a');
      if (full.audioUrl != null && best.baseUrl == full.audioUrl && audioFile.existsSync()) {
        try { audioFile.copySync('${_downloadDir}/${item.name}.mp4'); videoOk = true; } catch (_) { videoOk = false; }
      } else {
        videoOk = await StreamDownloader.download(
          url: best.baseUrl!, savePath: '${_downloadDir}/${item.name}.mp4',
          expectedSize: best.size > 0 ? best.size : null,
          onProgress: (_) {},
          onSize: (received, total) { if (mounted) setState(() { _updateItemSpeed(item, received); item.progress = total > 0 ? 0.5 + (received / total) * 0.5 : item.progress; }); },
          cancel: _cancelNotifier,
        );
      }
    }
    // 最终校验
    final needAudio = _downloadAudio ? (File('${_downloadDir}/${item.name}.m4a').existsSync() && File('${_downloadDir}/${item.name}.m4a').lengthSync() > 0) : true;
    final needVideo = _downloadVideo ? (File('${_downloadDir}/${item.name}.mp4').existsSync() && File('${_downloadDir}/${item.name}.mp4').lengthSync() > 0) : true;
    final needCover = File('${_downloadDir}/${item.name}.jpg').existsSync() && File('${_downloadDir}/${item.name}.jpg').lengthSync() > 0;
    final ok = audioOk && videoOk && needAudio && needVideo && needCover;
    if (!ok) {
      try {
        if (!needAudio) File('${_downloadDir}/${item.name}.m4a').deleteSync();
        if (!needVideo) File('${_downloadDir}/${item.name}.mp4').deleteSync();
        if (!needCover) File('${_downloadDir}/${item.name}.jpg').deleteSync();
      } catch (_) {}
    }
    if (ok) {
      SongManager.registerSong(
        filePath: '${_downloadDir}/${item.name}.m4a',
        title: full.title, uploader: full.author, durationSec: full.durationSeconds,
        bvid: full.bvid, url: full.url,
        coverPath: '${_downloadDir}/${item.name}.jpg',
        videoPath: _downloadVideo ? '${_downloadDir}/${item.name}.mp4' : null,
      );
    }
    setState(() { item.status = ok ? _BatchStatus.done : _BatchStatus.failed; if (ok) item.exists = true; item.progress = ok ? 1.0 : 0; item.speed = 0; });
  }

  // ---- 固定底部按钮 ----
  Widget? _buildBottomBar() {
    if (_isParsing || (!_isDownloading && _singleInfo == null && _batchItems.isEmpty)) return null;
    if (_singleInfo != null && _alreadyDownloaded) return null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
      ),
      child: _isDownloading
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              if (_downloadingTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('正在下载：$_downloadingTitle${_downloadingSize > 0 ? ' (${(_downloadingSize / 1048576).toStringAsFixed(1)}MB)' : ''}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              SizedBox(
                width: double.infinity, height: 36,
                child: OutlinedButton.icon(
                  onPressed: _cancelling ? null : () {
                    _cancelNotifier?.value = true;
                    setState(() => _cancelling = true); // 立即反馈
                  },
                  icon: const Icon(Icons.close, color: Colors.red, size: 16),
                  label: Text(_cancelling ? '正在取消...' : '取消下载', style: const TextStyle(fontSize: 13, color: Colors.red)),
                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                ),
              ),
            ])
          : SizedBox(
              width: double.infinity, height: 44,
              child: ElevatedButton.icon(
                onPressed: _batchItems.isNotEmpty ? _startBatch : _startSingle,
                icon: const Icon(Icons.download),
                label: Text(
                  _batchItems.isNotEmpty
                      ? '一键下载全部(${_batchItems.where((b) => !b.exists).length}首${_downloadVideo ? " 音频+视频" : " 仅音频"})'
                      : (_downloadVideo ? '开始下载 (音频+视频)' : '开始下载 (仅音频)'),
                  style: const TextStyle(fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              ),
            ),
    );
  }
}

// ==================== 批量下载项状态 ====================

enum _BatchStatus { waiting, downloading, done, failed }

class _BatchItem {
  final BilibiliVideoInfo info;
  final String name;
  bool exists;
  _BatchStatus status;
  double progress = 0;   // 0~1
  double speed = 0;      // bytes/秒
  _BatchItem({required this.info, required this.name, this.exists = false, this.status = _BatchStatus.waiting});
}
