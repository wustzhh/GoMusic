import 'package:flutter/material.dart';
import '../models/music_data.dart';
import 'video_detail_page.dart';

class PlayerPage extends StatefulWidget {
  final Song song;

  const PlayerPage({super.key, required this.song});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  bool isPlaying = true;
  double progress = 0.35;
  late Song song;

  @override
  void initState() {
    super.initState();
    song = widget.song;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        actions: [
          if (song.hasVideo)
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VideoDetailPage(song: song)),
                );
              },
              icon: const Icon(Icons.ondemand_video, size: 18),
              label: const Text('源视频'),
            ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          // 视频/封面区域
          GestureDetector(
            onTap: () {
              if (song.hasVideo) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VideoDetailPage(song: song)),
                );
              }
            },
            child: Container(
              width: 280,
              height: 280,
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    song.hasVideo ? Icons.play_circle_outline : Icons.album,
                    size: 80,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    song.hasVideo ? '点击观看视频' : '专辑封面',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // 歌曲信息
          Text(song.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(song.uploader, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 24),
          // 进度条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (v) => setState(() => progress = v),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(song.duration * progress), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(song.durationText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // 播放控制
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous, size: 48),
                onPressed: () {},
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: Icon(isPlaying ? Icons.pause_circle : Icons.play_circle, size: 64, color: Colors.deepPurple),
                onPressed: () => setState(() => isPlaying = !isPlaying),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.skip_next, size: 48),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 来源标识
          Text(
            song.hasVideo ? '已下载视频 · 可观看源视频' : '仅音频 · 无源视频',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
