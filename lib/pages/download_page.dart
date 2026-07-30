import 'dart:io';
import 'package:flutter/material.dart';
import '../services/bilibili_api.dart';
import '../services/settings_service.dart';

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
  bool _isParsing = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  BilibiliVideoInfo? _info;
  VideoStream? _selectedStream;
  bool _alreadyDownloaded = false;           // 是否已下载过
  String _downloadedSizeText = '';           // 已下载文件大小

  // 收藏夹相关
  List<BilibiliVideoInfo>? _collectionVideos; // 收藏夹视频列表
  bool _isCollection = false;

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
      _isParsing = true;
      _info = null;
      _collectionVideos = null;
      _isCollection = false;
      _alreadyDownloaded = false;
      _downloadedSizeText = '';
    });

    // 检测是否收藏夹/合集链接
    final isCollection = url.contains('/list/ml') ||
        url.contains('medialist') ||
        url.contains('favlist') ||
        (url.contains('fid=') && url.contains('space.bilibili.com'));
    if (isCollection) {
      _parseCollection(url);
      return;
    }

    final info = await _api.getVideoInfo(url);
    if (!mounted) return;
    await _afterParse(info);
  }

  Future<void> _parseCollection(String url) async {
    setState(() => _isCollection = true);
    final videos = await _api.getCollectionVideos(url);
    if (!mounted) return;
    if (videos != null && videos.isNotEmpty) {
      setState(() {
        _collectionVideos = videos;
        _isParsing = false;
      });
    } else {
      // 收藏夹解析失败，回退为普通视频链接
      final info = await _api.getVideoInfo(url);
      if (!mounted) return;
      setState(() => _isCollection = false);
      await _afterParse(info);
    }
  }

  Future<void> _afterParse(BilibiliVideoInfo? info) async {
    if (!mounted) return;
    if (info != null) {
      // 检查是否已下载
      final service = await SettingsService.getInstance();
      final dir = await service.getDownloadPath();
      final audioPath = '$dir\\${_safeFileName(info.title)}.m4a';
      final alreadyExists = File(audioPath).existsSync();
      String sizeText = '';
      if (alreadyExists) {
        try {
          final bytes = await File(audioPath).length();
          sizeText = '${(bytes / 1048576).toStringAsFixed(1)} MB';
        } catch (_) {}
      }

      setState(() {
        _info = info;
        _nameController.text = info.title;
        _authorController.text = info.author;
        _isParsing = false;
        _selectedStream = info.videoStreams.isNotEmpty ? info.videoStreams.first : null;
        _alreadyDownloaded = alreadyExists;
        _downloadedSizeText = sizeText;
      });
    } else {
      setState(() => _isParsing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('解析失败，请检查URL是否正确')),
        );
      }
    }
  }

  void _clearAll() {
    _urlController.clear();
    _nameController.clear();
    _authorController.clear();
    setState(() {
      _info = null;
      _collectionVideos = null;
      _isCollection = false;
      _downloadVideo = false;
      _downloadProgress = 0;
      _alreadyDownloaded = false;
      _downloadedSizeText = '';
    });
  }

  // ==================== 下载 ====================

  Future<void> _startDownload() async {
    final info = _info;
    if (info == null || info.audioUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未获取到下载地址，请重新解析')),
      );
      return;
    }

    final service = await SettingsService.getInstance();
    final dir = await service.getDownloadPath();

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    final name = _safeFileName(_nameController.text.trim());
    final audioPath = '$dir\\$name.m4a';
    var audioOk = false;
    var videoOk = !_downloadVideo;
    var coverOk = false;

    // 下载封面
    if (info.coverUrl.isNotEmpty) {
      coverOk = await StreamDownloader.download(
        url: info.coverUrl,
        savePath: '$dir\\$name.jpg',
        onProgress: (_) {},
      );
    }

    // 下载音频
    audioOk = await StreamDownloader.download(
      url: info.audioUrl!,
      savePath: audioPath,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p * (_downloadVideo ? 0.5 : 1.0));
      },
    );

    // 下载视频
    if (_downloadVideo && _selectedStream?.baseUrl != null && audioOk) {
      videoOk = await StreamDownloader.download(
        url: _selectedStream!.baseUrl!,
        savePath: '$dir\\$name.mp4',
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = 0.5 + p * 0.5);
        },
      );
    }

    if (!mounted) return;

    // 读取实际文件大小
    String sizeText = '';
    try {
      final audioFile = File(audioPath);
      if (await audioFile.exists()) {
        final bytes = await audioFile.length();
        sizeText = '${(bytes / 1048576).toStringAsFixed(1)} MB';
      }
    } catch (_) {}

    setState(() {
      _isDownloading = false;
      _alreadyDownloaded = audioOk;
      _downloadedSizeText = sizeText;
    });

    if (audioOk && videoOk) {
      final parts = <String>['音频 $sizeText'];
      if (_downloadVideo) parts.add('视频');
      if (coverOk) parts.add('封面');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载完成！${parts.join(' + ')}\n$dir')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载失败，请重试')),
      );
    }
  }

  // 收藏夹一键下载
  Future<void> _batchDownloadAll() async {
    if (_collectionVideos == null) return;
    final service = await SettingsService.getInstance();
    final dir = await service.getDownloadPath();
    setState(() { _isDownloading = true; _downloadProgress = 0; });

    final total = _collectionVideos!.length;
    var ok = 0;
    for (var i = 0; i < total; i++) {
      final v = _collectionVideos![i];
      // 解析完整信息
      final full = await _api.getVideoInfo(v.url);
      if (full?.audioUrl != null) {
        final name = _safeFileName(full!.title);
        final path = '$dir\\$name.m4a';
        final success = await StreamDownloader.download(
          url: full.audioUrl!,
          savePath: path,
          onProgress: (_) {},
        );
        if (success) ok++;
        if (full.coverUrl.isNotEmpty) {
          await StreamDownloader.download(url: full.coverUrl, savePath: '$dir\\$name.jpg', onProgress: (_) {});
        }
      }
      if (mounted) setState(() => _downloadProgress = (i + 1) / total);
    }

    if (!mounted) return;
    setState(() => _isDownloading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('批量下载完成：$ok/$total')),
    );
  }

  String _safeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_info == null && _collectionVideos == null) _buildUrlInput(),
            if (_info != null) _buildCompactUrlBar(),
            if (_isCollection && _collectionVideos != null) ...[
              _buildCompactUrlBar(),
              const SizedBox(height: 12),
              Text('收藏夹 · ${_collectionVideos!.length}个视频', style: const TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              ..._collectionVideos!.map((v) => _buildCollectionItem(v)),
              const SizedBox(height: 12),
              if (_isDownloading) _buildProgressBar(),
              const SizedBox(height: 8),
              _buildBatchDownloadButton(),
            ],
            if (_isParsing) _buildParsingIndicator(),
            if (_info != null) ...[
              const SizedBox(height: 16),
              _buildInfoCard(_info!),
              if (_alreadyDownloaded)
                _buildDownloadedBadge(),
              if (_info!.videoStreams.length > 1 && !_alreadyDownloaded) ...[
                const SizedBox(height: 12),
                _buildQualitySelector(),
              ],
              if (!_alreadyDownloaded) ...[
                const SizedBox(height: 16),
                _buildEditableFields(),
                if (_isDownloading) ...[
                  const SizedBox(height: 16),
                  _buildProgressBar(),
                ],
                const SizedBox(height: 16),
                _buildSwitch(),
                const SizedBox(height: 16),
                _buildDownloadButton(),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadedBadge() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Text('本地已下载', style: TextStyle(color: Colors.green[700], fontSize: 14)),
          if (_downloadedSizeText.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(_downloadedSizeText, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildCollectionItem(BilibiliVideoInfo v) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: v.coverUrl.isNotEmpty
            ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(v.coverUrl, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, e, s) => const Icon(Icons.image, size: 40)))
            : const Icon(Icons.music_note, size: 30),
        title: Text(v.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        subtitle: Text('${v.author} · ${v.durationText}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ),
    );
  }

  Widget _buildBatchDownloadButton() {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton.icon(
        onPressed: _isDownloading ? null : _batchDownloadAll,
        icon: _isDownloading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.download),
        label: Text(_isDownloading ? '下载中...' : '一键下载全部(${_collectionVideos?.length ?? 0}首)', style: const TextStyle(fontSize: 15)),
      ),
    );
  }

  // ---- 原有UI组件保持不变 ----
  Widget _buildUrlInput() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.video_library_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('粘贴B站视频或收藏夹链接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: 'https://www.bilibili.com/video/...\n或收藏夹/合集链接...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.link),
                ),
                maxLines: 2,
                onSubmitted: (_) => _parseUrl(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _isParsing ? null : _parseUrl,
            icon: _isParsing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search),
            label: Text(_isParsing ? '解析中...' : '解析视频', style: const TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactUrlBar() {
    return Row(children: [
      Expanded(child: TextField(controller: _urlController, decoration: InputDecoration(hintText: 'B站视频URL', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), prefixIcon: const Icon(Icons.link, size: 20), contentPadding: const EdgeInsets.symmetric(vertical: 10)), style: const TextStyle(fontSize: 13))),
      const SizedBox(width: 8),
      IconButton(onPressed: _clearAll, icon: const Icon(Icons.close, color: Colors.red), tooltip: '清空'),
    ]);
  }

  Widget _buildParsingIndicator() {
    return const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('正在解析...', style: TextStyle(color: Colors.grey))]));
  }

  Widget _buildInfoCard(BilibiliVideoInfo info) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: info.coverUrl.isNotEmpty ? Image.network(info.coverUrl, width: 100, height: 100, fit: BoxFit.cover, errorBuilder: (_, e, s) => _placeholderCover()) : _placeholderCover()),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(info.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          _infoRow(Icons.person, info.author),
          const SizedBox(height: 4),
          _infoRow(Icons.timer_outlined, info.durationText),
          const SizedBox(height: 4),
          _infoRow(Icons.audiotrack, '音频 ${info.audioSizeText}'),
          const SizedBox(height: 4),
          _infoRow(Icons.videocam, '视频 ${_selectedStream?.sizeText ?? '未知'}${(_selectedStream?.width ?? 0) > 0 ? ' · ${_selectedStream?.width}x${_selectedStream?.height}' : ''}'),
          const SizedBox(height: 4),
          Text('BV: ${info.bvid}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
      ])),
    );
  }

  Widget _placeholderCover() {
    return Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)), child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.image, size: 36, color: Colors.grey), SizedBox(height: 4), Text('封面', style: TextStyle(color: Colors.grey, fontSize: 11))])));
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(children: [Icon(icon, size: 14, color: Colors.grey), const SizedBox(width: 4), Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey)))]);
  }

  Widget _buildEditableFields() {
    return Column(children: [
      TextField(controller: _nameController, decoration: InputDecoration(labelText: '本地保存名称', hintText: '可修改保存到本地的歌曲名', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
      const SizedBox(height: 12),
      TextField(controller: _authorController, decoration: InputDecoration(labelText: '本地保存作者', hintText: '可修改保存到本地的作者名', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
    ]);
  }

  Widget _buildProgressBar() {
    return Column(children: [LinearProgressIndicator(value: _downloadProgress, minHeight: 8), const SizedBox(height: 6), Text('${(_downloadProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.grey, fontSize: 13))]);
  }

  Widget _buildQualitySelector() {
    final streams = _info!.videoStreams;
    return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: DropdownButton<VideoStream>(value: _selectedStream ?? streams.first, isExpanded: true, underline: const SizedBox(), items: streams.map((s) => DropdownMenuItem(value: s, child: Text(s.description, style: const TextStyle(fontSize: 13)))).toList(), onChanged: (v) { if (v != null) setState(() => _selectedStream = v); })));
  }

  Widget _buildSwitch() {
    return Row(children: [const Icon(Icons.video_file_outlined, color: Colors.grey), const SizedBox(width: 8), const Text('同时下载视频', style: TextStyle(fontSize: 15)), const Spacer(), Switch(value: _downloadVideo, onChanged: _isDownloading ? null : (v) => setState(() => _downloadVideo = v))]);
  }

  Widget _buildDownloadButton() {
    return SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
      onPressed: _isDownloading ? null : _startDownload,
      icon: _isDownloading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.download),
      label: Text(_isDownloading ? '下载中...' : (_downloadVideo ? '开始下载 (音频 + 视频)' : '开始下载 (仅音频)'), style: const TextStyle(fontSize: 16)),
      style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ));
  }
}
