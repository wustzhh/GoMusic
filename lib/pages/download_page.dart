import 'package:flutter/material.dart';
import '../models/music_data.dart';

class DownloadPage extends StatelessWidget {
  final VoidCallback? onNavigateToPlaylist;

  const DownloadPage({super.key, this.onNavigateToPlaylist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('下载'), centerTitle: true),
      body: Column(
        children: [
          // URL输入区
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  decoration: InputDecoration(
                    hintText: '输入B站视频URL...',
                    prefixIcon: const Icon(Icons.link),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('同时下载视频', style: TextStyle(fontSize: 15)),
                    const Spacer(),
                    Switch(value: false, onChanged: (_) {}),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.download),
                    label: const Text('开始下载', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          // 下载历史标题
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
          // 下载历史列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: mockDownloadHistory.length,
              itemBuilder: (context, index) {
                final record = mockDownloadHistory[index];
                return _DownloadRecordTile(record: record);
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
