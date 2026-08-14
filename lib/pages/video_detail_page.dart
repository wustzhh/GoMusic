import 'dart:io';

import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
import 'video_player_page.dart';

/// 视频详情：有本地视频直接播放本地文件；无本地视频给出提示
class VideoDetailPage extends StatefulWidget {
  final Song song;
  const VideoDetailPage({super.key, required this.song});
  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  /// 删除本地视频文件并返回
  void _confirmDeleteVideo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除视频'),
        content: Text('确定要删除「${widget.song.title}」的视频文件吗？\n音频保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            try {
              final vp = widget.song.videoPath;
              if (vp != null && vp.isNotEmpty) {
                final f = File(vp);
                if (f.existsSync()) f.deleteSync();
              }
              SongManager.registerVideoPath(widget.song.filePath, '');
            } catch (_) {}
            AudioPlayerService().favoritesChangedNotifier.value++;
            if (Navigator.canPop(context)) Navigator.pop(context);
          }, child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vp = widget.song.videoPath;
    final hasLocal = vp != null && vp.isNotEmpty && File(vp).existsSync();
    return Scaffold(
      backgroundColor: Colors.transparent, // 透出全局动态背景
      appBar: AppBar(title: const Text(''), actions: [
        if (hasLocal)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (v) {
              if (v == 'delete') _confirmDeleteVideo(context);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Row(children: [
                Icon(Icons.delete_outline, color: Colors.red, size: 18),
                SizedBox(width: 8),
                Text('删除视频', style: TextStyle(color: Colors.red)),
              ])),
            ],
          ),
      ]),
      body: Column(
        children: [
          // 视频画面区域：本地视频直接播放
          GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              height: 260,
              color: Colors.black,
              child: hasLocal
                  ? VideoPlayerPage(song: widget.song)
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.videocam_off_outlined, size: 60, color: Colors.white.withValues(alpha: 0.7)),
                            const SizedBox(height: 8),
                            Text(
                              '未下载视频',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '下载时勾选「视频」后即可本地播放',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.song.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('UP主: ${widget.song.uploader}', style: const TextStyle(fontSize: 14, color: Colors.grey)),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                if (hasLocal)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerPage(song: widget.song)));
                      },
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('全屏播放本地视频'),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.music_note),
                      label: const Text('返回音频模式'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
