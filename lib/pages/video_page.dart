import 'dart:io';

import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../services/settings_service.dart';
import 'video_player_page.dart';

/// 视频列表页：扫描下载的视频文件，按 BV号从数据管理器取标题/封面
class VideoPage extends StatefulWidget {
  const VideoPage({super.key});
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  List<Song> _videos = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = await SettingsService.getInstance();
    final dir = await svc.getDownloadPath();
    final localSongs = await scanLocalAudioFiles(dir);
    final byBvid = {for (final s in localSongs) if (s.bvid.isNotEmpty) s.bvid: s};
    final videos = <Song>[];
    try {
      final d = Directory(dir);
      if (d.existsSync()) {
        for (final f in d.listSync()) {
          if (f is File && f.path.toLowerCase().endsWith('.mp4')) {
            final name = f.path.split('\\').last.split('/').last;
            final bv = name.substring(0, name.lastIndexOf('.'));
            final meta = byBvid[bv];
            videos.add(Song(
              id: bv,
              title: meta?.title ?? bv,
              uploader: meta?.uploader ?? '',
              duration: meta?.duration ?? Duration.zero,
              filePath: f.path,
              bvid: bv,
              coverUrl: meta?.coverUrl,
              hasVideo: true,
            ));
          }
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _videos = videos;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('视频'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('视频'), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: '', onPressed: _load),
      ]),
      body: _videos.isEmpty
          ? const Center(child: Text('暂无视频，下载时勾选"同时下载视频"', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _videos.length,
              itemBuilder: (_, i) {
                final v = _videos[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _cover(v),
                    title: Text(v.title, style: const TextStyle(fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(v.uploader, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    trailing: const Icon(Icons.play_circle_outline, color: Colors.deepPurple),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerPage(song: v)));
                    },
                  ),
                );
              },
            ),
    );
  }

  Widget _cover(Song s) {
    if (s.coverUrl != null && s.coverUrl!.isNotEmpty) {
      final f = File(s.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        return ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.file(f, width: 44, height: 44, fit: BoxFit.cover));
      }
    }
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: Colors.deepPurple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: const Icon(Icons.video_file_outlined, color: Colors.deepPurple, size: 24),
    );
  }
}
