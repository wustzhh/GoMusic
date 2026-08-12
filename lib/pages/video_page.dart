import 'dart:io';

import 'package:flutter/material.dart';
import '../main.dart';
import '../models/music_data.dart';
import '../services/audio_player_service.dart';
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
    // 下载完成自动刷新（无需手动点刷新）
    downloadsChangedNotifier.addListener(_onDownloadsChanged);
  }

  @override
  void dispose() {
    downloadsChangedNotifier.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    _load();
  }

  Future<void> _load() async {
    final svc = await SettingsService.getInstance();
    final dir = await svc.getDownloadPath();
    SongManager.init(dir);
    final videos = <Song>[];
    try {
      final d = Directory(dir);
      if (d.existsSync()) {
        for (final f in d.listSync()) {
          if (f is File && f.path.toLowerCase().endsWith('.mp4')) {
            final name = f.path.split('\\').last.split('/').last;
            final bv = name.substring(0, name.lastIndexOf('.'));
            // 元数据直接查数据管理器（纯视频条目也能查到标题/封面/时长）
            final m = SongManager.findByBvid(bv);
            videos.add(Song(
              id: bv,
              title: m?['title'] as String? ?? bv,
              uploader: m?['uploader'] as String? ?? '',
              duration: Duration(seconds: m?['duration'] as int? ?? 0),
              filePath: f.path,
              bvid: bv,
              coverUrl: (m?['coverPath'] as String? ?? '').isNotEmpty ? m?['coverPath'] as String? : null,
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
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.play_circle_outline, color: Colors.deepPurple),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerPage(song: v, videos: _videos, initialIndex: i)));
                        },
                      ),
                      // 竖着的 ⋮ 菜单
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
                        onSelected: (val) {
                          if (val == 'delete') _confirmDeleteVideo(v);
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
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerPage(song: v, videos: _videos, initialIndex: i)));
                    },
                  ),
                );
              },
            ),
    );
  }

  /// 删除视频文件（保留音频）
  void _confirmDeleteVideo(Song song) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除视频'),
        content: Text('确定要删除「${song.title}」的视频文件吗？\n音频保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () async {
            Navigator.pop(ctx);
            final isVideoOnly = song.filePath.toLowerCase().endsWith('.mp4');
            try {
              if (isVideoOnly) {
                // 仅视频的歌（主文件就是 mp4）：删视频 + 注销登记 + 清理所有歌单记录
                if (File(song.filePath).existsSync()) File(song.filePath).deleteSync();
                if (song.coverUrl != null && song.coverUrl!.isNotEmpty && File(song.coverUrl!).existsSync()) {
                  File(song.coverUrl!).deleteSync();
                }
                SongManager.unregisterSong(song.filePath);
                final key = song.bvid.isNotEmpty ? song.bvid : song.filePath.replaceAll('\\', '/').split('/').last.split('.').first;
                try {
                  final pls = await PlaylistService.getPlaylists();
                  for (final pl in pls) {
                    await PlaylistService.removeSongFromPlaylist(pl.id, key);
                  }
                } catch (_) {}
                try { await AudioPlayerService.removeFavorite(key); } catch (_) {}
                try { await RecentlyPlayedService.removeSong(key); } catch (_) {}
                try { SongGroupService.removeSongFromGroups(key); } catch (_) {}
              } else {
                // 有音频的视频：只删视频文件（mp4），音频与记录保留
                final videoPath = song.videoPath ?? '';
                if (videoPath.isNotEmpty && File(videoPath).existsSync()) File(videoPath).deleteSync();
                // 清除对应音频的视频关联
                SongManager.registerVideoPath(song.filePath, '');
              }
            } catch (_) {}
            AudioPlayerService().favoritesChangedNotifier.value++;
            _load();
          }, child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _cover(Song s) {    if (s.coverUrl != null && s.coverUrl!.isNotEmpty) {
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
