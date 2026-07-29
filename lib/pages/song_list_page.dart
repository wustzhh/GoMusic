import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../widgets/mini_player_bar.dart';
import 'player_page.dart';

class SongListPage extends StatelessWidget {
  final Playlist playlist;

  const SongListPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(playlist.name),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {},
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑列表')),
              const PopupMenuItem(value: 'delete', child: Text('删除列表')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索歌曲...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (_) {},
            ),
          ),
          // 歌曲列表
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: playlist.songs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final song = playlist.songs[index];
                return ListTile(
                  leading: const Icon(Icons.music_note, color: Colors.deepPurple, size: 32),
                  title: Text(song.title, style: const TextStyle(fontSize: 15)),
                  subtitle: Text(song.uploader, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: Text(song.durationText, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlayerPage(song: song),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // 迷你播放条
          const MiniPlayerBar(),
        ],
      ),
    );
  }
}
