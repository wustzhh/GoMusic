import 'package:flutter/material.dart';
import '../models/music_data.dart';

class VideoDetailPage extends StatefulWidget {
  final Song song;

  const VideoDetailPage({super.key, required this.song});

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  double progress = 0.4;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('')),
      body: Column(
        children: [
          // 视频画面区域
          GestureDetector(
            onTap: () {},
            child: Container(
              width: double.infinity,
              height: 260,
              color: Colors.black,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 模拟视频画面占位
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_outline, size: 60, color: Colors.white.withValues(alpha: 0.7)),
                      const SizedBox(height: 8),
                      Text(
                        'B站视频: ${widget.song.title}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '纯视频 · 无弹幕 · 无字幕',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 视频信息
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
          const SizedBox(height: 16),
          // 进度条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
              child: Slider(value: progress, onChanged: (v) => setState(() => progress = v)),
            ),
          ),
          const Spacer(),
          // 操作按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.music_note),
                    label: const Text('仅音频模式'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('在B站打开'),
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
