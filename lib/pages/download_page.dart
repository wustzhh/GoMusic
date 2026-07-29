import 'package:flutter/material.dart';
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

  bool _downloadVideo = false;
  bool _isParsed = false;

  // 解析后的信息（假数据）
  String _videoTitle = '';
  String _videoAuthor = '';
  String _duration = '';
  // ignore: unused_field
  String _coverUrl = ''; // 后续B站API解析时使用

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  void _parseUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // 模拟解析：用假数据填充
    setState(() {
      _isParsed = true;
      _videoTitle = '夜曲';
      _videoAuthor = '周杰伦';
      _duration = '03:42';
      _coverUrl = '';
      _nameController.text = _videoTitle;
      _authorController.text = _videoAuthor;
    });
  }

  void _startDownload() {
    // TODO: 实际下载逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('开始下载（功能待实现）')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载'), centerTitle: true),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // URL输入区
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // URL输入框 + 解析按钮
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            hintText: '输入B站视频URL...',
                            prefixIcon: const Icon(Icons.link),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _parseUrl,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        child: const Text('解析'),
                      ),
                    ],
                  ),

                  // 解析结果区
                  if (_isParsed) ...[
                    const SizedBox(height: 16),
                    _buildParsedInfo(),
                  ],

                  const SizedBox(height: 12),

                  // 视频下载开关
                  Row(
                    children: [
                      const Text('同时下载视频', style: TextStyle(fontSize: 15)),
                      const Spacer(),
                      Switch(
                        value: _downloadVideo,
                        onChanged: (v) => setState(() => _downloadVideo = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 下载按钮
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _startDownload,
                      icon: const Icon(Icons.download),
                      label: const Text('开始下载', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),

            // 下载历史
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('下载历史', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: mockDownloadHistory.length,
              itemBuilder: (context, index) {
                return _DownloadRecordTile(record: mockDownloadHistory[index]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParsedInfo() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面 + 信息行
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 封面占位
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.image, size: 40, color: Colors.grey),
                ),
                const SizedBox(width: 12),
                // 视频信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '原标题: $_videoTitle',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'UP主: $_videoAuthor',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '时长: $_duration',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            // 可编辑字段
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '本地保存名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _authorController,
              decoration: const InputDecoration(
                labelText: '本地保存作者',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// DownloadRecordTile 保持不变
class _DownloadRecordTile extends StatelessWidget {
  final DownloadRecord record;

  const _DownloadRecordTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final isCompleted = record.status == DownloadStatus.completed;
    final isDownloading = record.status == DownloadStatus.downloading;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isCompleted ? Icons.check_circle : (isDownloading ? Icons.downloading : Icons.error),
          color: isCompleted ? Colors.green : (isDownloading ? Colors.orange : Colors.red),
        ),
        title: Text(record.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDownloading) ...[
              const SizedBox(height: 4),
              LinearProgressIndicator(value: record.progress),
              const SizedBox(height: 2),
              Text('${(record.progress * 100).toInt()}%', style: const TextStyle(fontSize: 12)),
            ],
            if (isCompleted) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (record.hasAudio) const Text('🎵音频 ', style: TextStyle(fontSize: 12)),
                  if (record.hasVideo) const Text('📹视频', style: TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ],
        ),
        trailing: isCompleted ? Text(record.fileSize ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)) : null,
      ),
    );
  }
}
