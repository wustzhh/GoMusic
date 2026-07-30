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
    });

    final info = await _api.getVideoInfo(url);
    if (!mounted) return;

    if (info != null) {
      setState(() {
        _info = info;
        _nameController.text = info.title;
        _authorController.text = info.author;
        _isParsing = false;
      });
    } else {
      setState(() => _isParsing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('解析失败，请检查URL是否正确，或尝试在设置中配置B站Cookie')),
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
      _downloadVideo = false;
      _downloadProgress = 0;
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

    final audioPath = '$dir\\${_safeFileName(_nameController.text.trim())}.m4a';
    var audioOk = false;
    var videoOk = !_downloadVideo; // 不下载视频就直接算成功

    // 下载音频
    audioOk = await StreamDownloader.download(
      url: info.audioUrl!,
      savePath: audioPath,
      onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p * (_downloadVideo ? 0.5 : 1.0));
      },
    );

    // 下载视频
    if (_downloadVideo && info.videoUrl != null && audioOk) {
      final videoPath = '$dir\\${_safeFileName(_nameController.text.trim())}.mp4';
      videoOk = await StreamDownloader.download(
        url: info.videoUrl!,
        savePath: videoPath,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = 0.5 + p * 0.5);
        },
      );
    }

    if (!mounted) return;

    // 更新文件大小显示（覆盖"未知"）
    try {
      final audioFile = File(audioPath);
      if (await audioFile.exists()) {
        _info!.audioSize = await audioFile.length();
      }
      if (_downloadVideo) {
        final videoPath = '$dir\\${_safeFileName(_nameController.text.trim())}.mp4';
        final videoFile = File(videoPath);
        if (await videoFile.exists()) {
          _info!.videoSize = await videoFile.length();
        }
      }
    } catch (_) {}

    setState(() => _isDownloading = false);

    // 检查文件大小
    String sizeText = '';
    try {
      final audioFile = File(audioPath);
      if (await audioFile.exists()) {
        final bytes = await audioFile.length();
        sizeText = '${(bytes / 1048576).toStringAsFixed(1)} MB';
      }
    } catch (_) {}

    if (!mounted) return;

    if (audioOk && videoOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下载完成！$sizeText\n已保存到: $dir')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载失败，请重试')),
      );
    }
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
            if (_info == null) _buildUrlInput(),
            if (_info != null) _buildCompactUrlBar(),
            if (_isParsing) _buildParsingIndicator(),
            if (_info != null) ...[
              const SizedBox(height: 16),
              _buildInfoCard(_info!),
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
        ),
      ),
    );
  }

  // ---- 未解析 URL 输入 ----
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
              const Text('粘贴B站视频链接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  hintText: 'https://www.bilibili.com/video/...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.link),
                ),
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
            icon: const Icon(Icons.search),
            label: const Text('解析视频', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  // ---- 已解析紧凑 URL 行 ----
  Widget _buildCompactUrlBar() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'B站视频URL',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: const Icon(Icons.link, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _clearAll,
          icon: const Icon(Icons.close, color: Colors.red),
          tooltip: '清空',
        ),
      ],
    );
  }

  // ---- 解析中 ----
  Widget _buildParsingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('正在解析...', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  // ---- 视频信息卡片 ----
  Widget _buildInfoCard(BilibiliVideoInfo info) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面（网络图片）
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: info.coverUrl.isNotEmpty
                  ? Image.network(
                      info.coverUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, e, s) => _placeholderCover(),
                    )
                  : _placeholderCover(),
            ),
            const SizedBox(width: 12),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  _infoRow(Icons.person, info.author),
                  const SizedBox(height: 4),
                  _infoRow(Icons.timer_outlined, info.durationText),
                  const SizedBox(height: 4),
                  _infoRow(Icons.audiotrack, '音频 ${info.audioSizeText}'),
                  const SizedBox(height: 4),
                  _infoRow(Icons.videocam, '视频 ${info.videoSizeText}${info.videoWidth > 0 ? ' · ${info.videoWidth}x${info.videoHeight}' : ''}'),
                  const SizedBox(height: 4),
                  Text('BV: ${info.bvid}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderCover() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image, size: 36, color: Colors.grey),
            SizedBox(height: 4),
            Text('封面', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey))),
      ],
    );
  }

  // ---- 可编辑字段 ----
  Widget _buildEditableFields() {
    return Column(
      children: [
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: '本地保存名称',
            hintText: '可修改保存到本地的歌曲名',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _authorController,
          decoration: InputDecoration(
            labelText: '本地保存作者',
            hintText: '可修改保存到本地的作者名',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
      ],
    );
  }

  // ---- 进度条 ----
  Widget _buildProgressBar() {
    return Column(
      children: [
        LinearProgressIndicator(value: _downloadProgress, minHeight: 8),
        const SizedBox(height: 6),
        Text('${(_downloadProgress * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ],
    );
  }

  // ---- 视频开关 ----
  Widget _buildSwitch() {
    return Row(
      children: [
        const Icon(Icons.video_file_outlined, color: Colors.grey),
        const SizedBox(width: 8),
        const Text('同时下载视频', style: TextStyle(fontSize: 15)),
        const Spacer(),
        Switch(
          value: _downloadVideo,
          onChanged: _isDownloading ? null : (v) => setState(() => _downloadVideo = v),
        ),
      ],
    );
  }

  // ---- 下载按钮 ----
  Widget _buildDownloadButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _isDownloading ? null : _startDownload,
        icon: _isDownloading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.download),
        label: Text(
          _isDownloading ? '下载中...' : (_downloadVideo ? '开始下载 (音频 + 视频)' : '开始下载 (仅音频)'),
          style: const TextStyle(fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
