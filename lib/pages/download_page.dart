import 'package:flutter/material.dart';
import '../services/bilibili_api.dart';

/// 解析后的视频信息
class _ParsedInfo {
  final String url;
  final String coverUrl;
  final String originalTitle;
  final String originalAuthor;
  final String duration;
  final String bvid;

  const _ParsedInfo({
    required this.url,
    required this.coverUrl,
    required this.originalTitle,
    required this.originalAuthor,
    required this.duration,
    required this.bvid,
  });
}

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _authorController = TextEditingController();

  bool _downloadVideo = false;
  bool _isLoading = false;
  _ParsedInfo? _parsedInfo;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _parseUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() => _isLoading = true);

    final info = await BilibiliApi.getVideoInfo(url);

    if (!mounted) return;

    if (info != null) {
      setState(() {
        _parsedInfo = _ParsedInfo(
          url: info.url,
          coverUrl: info.coverUrl,
          originalTitle: info.title,
          originalAuthor: info.author,
          duration: info.durationText,
          bvid: info.bvid,
        );
        _nameController.text = info.title;
        _authorController.text = info.author;
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
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
      _parsedInfo = null;
      _downloadVideo = false;
    });
  }

  void _startDownload() {
    final info = _parsedInfo;
    if (info == null) return;

    final localName = _nameController.text.trim();
    final localAuthor = _authorController.text.trim();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('开始下载: $localName / $localAuthor'
            '${_downloadVideo ? " (含视频)" : ""}'
            '\n原网址: ${info.url}'
            '\n原标题: ${info.originalTitle}'
            '\n原作者: ${info.originalAuthor}'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsedInfo;

    return Scaffold(
      appBar: AppBar(title: const Text('下载'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ── URL输入区 ──
            // 未解析时大块区域，已解析时紧凑行
            if (parsed == null) _buildUrlInputLarge(),
            if (parsed != null) _buildUrlInputCompact(),

            // ── 解析结果区 ──
            if (parsed != null) ...[
              const SizedBox(height: 16),
              _buildVideoInfoCard(parsed),
              const SizedBox(height: 16),
              _buildEditableFields(),
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

  // ===================== 子组件 =====================

  /// 未解析时的大块URL输入
  Widget _buildUrlInputLarge() {
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
            onPressed: _isLoading ? null : _parseUrl,
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search),
            label: Text(_isLoading ? '解析中...' : '解析视频', style: const TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }

  /// 已解析时的紧凑URL行
  Widget _buildUrlInputCompact() {
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

  /// 视频信息卡片（封面+原标题+原作者+时长）
  Widget _buildVideoInfoCard(_ParsedInfo info) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
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
            ),
            const SizedBox(width: 12),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.originalTitle,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(info.originalAuthor, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(info.duration, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'BV: ${info.bvid}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 可编辑字段
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

  /// 视频下载开关
  Widget _buildSwitch() {
    return Row(
      children: [
        const Icon(Icons.video_file_outlined, color: Colors.grey),
        const SizedBox(width: 8),
        const Text('同时下载视频', style: TextStyle(fontSize: 15)),
        const Spacer(),
        Switch(value: _downloadVideo, onChanged: (v) => setState(() => _downloadVideo = v)),
      ],
    );
  }

  /// 下载按钮（动态文字）
  Widget _buildDownloadButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _startDownload,
        icon: const Icon(Icons.download),
        label: Text(
          _downloadVideo ? '开始下载 (音频 + 视频)' : '开始下载 (仅音频)',
          style: const TextStyle(fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
