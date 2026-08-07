import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/bilibili_api.dart';
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
  ValueNotifier<bool>? _cancelNotifier;
  String _downloadingTitle = '';
  int _downloadingSize = 0;
  double _downloadProgress = 0;

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
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isParsing = true; _singleInfo = null; _batchItems = [];
      _alreadyDownloaded = false; _downloadVideo = false;
    });

    if (_isCollectionUrl(url)) {
      await _parseCollection(url);
    } else {
      final info = await _api.getVideoInfo(url);
      if (!mounted) return;
      if (info != null) {
        await _checkSingleExists(info);
        setState(() {
          _singleInfo = info; _isParsing = false;
          _nameController.text = info.title;
          _authorController.text = info.author;
          _selectedStream = info.videoStreams.isNotEmpty ? info.videoStreams.first : null;
        });
      } else {
        setState(() => _isParsing = false);
        _snack('解析失败，请检查URL');
      }
    }
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
          _nameController.text = info.title;
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
        final exists = File('$dir/$name.m4a').existsSync();
        return _BatchItem(info: v, exists: exists, name: name);
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
            if (mounted && now.difference(lastUi).inMilliseconds >= 400) {
              lastUi = now;
              setState(() => _downloadProgress = p * (_downloadVideo ? 0.5 : 1.0));
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
        _downloadingSize = _selectedStream!.size;
        var lastUi2 = DateTime.now();
        videoOk = await StreamDownloader.download(
          url: _selectedStream!.baseUrl!, savePath: '$dir/$name.mp4',
          onProgress: (p) {
            final now = DateTime.now();
            if (mounted && now.difference(lastUi2).inMilliseconds >= 400) {
              lastUi2 = now;
              setState(() => _downloadProgress = 0.5 + p * 0.5);
            }
          },
          cancel: _cancelNotifier,
          expectedSize: _selectedStream!.size > 0 ? _selectedStream!.size : null,
        );
      } else {
        videoOk = false;
      }
    }

    if (!mounted) return;
    String sizeText = '';
    try { final f = File('$dir/$name.m4a'); if (f.existsSync()) sizeText = '${(f.lengthSync() / 1048576).toStringAsFixed(1)} MB'; } catch (_) {}

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
    if (!mounted) return;
    _cancelNotifier?.value = false;
    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadingTitle = '';
      });
    }
    if (Platform.isAndroid) FlutterForegroundTask.stopService();
    await _checkSingleExists(info);
    _snack('${audioOk && videoOk ? "下载完成" : (_cancelNotifier?.value == true ? "已取消" : "下载失败")} $sizeText${coverFailed ? " ⚠封面下载失败" : ""}');
  }

  // ==================== 批量下载 ====================

  Future<void> _startBatch() async {
    setState(() { _isDownloading = true; _batchTotal = 0; _batchDone = 0; });
    SongManager.init(_downloadDir!);

    final toDownload = _batchItems.where((b) => !b.exists).toList();
    _batchTotal = toDownload.length;

    for (final item in toDownload) {
      if (!mounted) return;
      setState(() => item.status = _BatchStatus.downloading);

      final full = await _api.getVideoInfo(item.info.url);
      if (full?.audioUrl == null) {
        setState(() => item.status = _BatchStatus.failed);
        _batchDone++;
        continue;
      }

      // 封面
      if (full!.coverUrl.isNotEmpty) {
        await StreamDownloader.download(url: full.coverUrl, savePath: '${_downloadDir}/${item.name}.jpg', onProgress: (_) {});
      }
      // 音频（勾选才下载）
      var audioOk = true;
      if (_downloadAudio) {
        audioOk = await StreamDownloader.download(
          url: full.audioUrl!, savePath: '${_downloadDir}/${item.name}.m4a',
          onProgress: (p) { if (mounted) setState(() => _downloadProgress = (_batchDone + p) / _batchTotal); },
        );
      }
      // 视频（勾选才下载，取最高画质）
      var videoOk = true;
      if (_downloadVideo && full.videoStreams.isNotEmpty) {
        final best = full.videoStreams.first;
        videoOk = await StreamDownloader.download(
          url: best.baseUrl!, savePath: '${_downloadDir}/${item.name}.mp4',
          expectedSize: best.size > 0 ? best.size : null,
          onProgress: (p) { if (mounted) setState(() => _downloadProgress = (_batchDone + p) / _batchTotal); },
        );
      }

      final ok = audioOk && videoOk;
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
    setState(() => _isDownloading = false);
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
              hintText: '粘贴B站视频链接或收藏夹链接...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.link, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => _parseUrl(),
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
        subtitle: Text('${item.info.author} · ${item.info.durationText}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
    setState(() { item.status = _BatchStatus.downloading; item.exists = false; });
    SongManager.init(_downloadDir!);

    final full = await _api.getVideoInfo(item.info.url);
    if (full?.audioUrl == null) { setState(() => item.status = _BatchStatus.failed); return; }

    if (full!.coverUrl.isNotEmpty) {
      await StreamDownloader.download(url: full.coverUrl, savePath: '${_downloadDir}/${item.name}.jpg', onProgress: (_) {});
    }
    final ok = await StreamDownloader.download(
      url: full.audioUrl!, savePath: '${_downloadDir}/${item.name}.m4a',
      onProgress: (_) {},
    );
    if (ok) {
      SongManager.registerSong(
        filePath: '${_downloadDir}/${item.name}.m4a',
        title: full.title, uploader: full.author, durationSec: full.durationSeconds,
        bvid: full.bvid, url: full.url,
        coverPath: '${_downloadDir}/${item.name}.jpg',
      );
    }
    setState(() { item.status = ok ? _BatchStatus.done : _BatchStatus.failed; if (ok) item.exists = true; });
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
              Row(children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: _downloadProgress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 10),
                Text('${(_downloadProgress * 100).clamp(0, 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity, height: 36,
                child: OutlinedButton.icon(
                  onPressed: () {
                    _cancelNotifier?.value = true;
                    setState(() => _isDownloading = false);
                  },
                  icon: const Icon(Icons.close, color: Colors.red, size: 16),
                  label: const Text('取消下载', style: TextStyle(fontSize: 13, color: Colors.red)),
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
