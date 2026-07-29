import 'package:flutter/material.dart';
import '../models/music_data.dart';
import 'song_list_page.dart';

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放列表'), centerTitle: true),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: mockPlaylists.length + 1, // +1 for "新建"
        itemBuilder: (context, index) {
          if (index < mockPlaylists.length) {
            final playlist = mockPlaylists[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Text(playlist.icon, style: const TextStyle(fontSize: 28)),
                title: Text(playlist.name, style: const TextStyle(fontSize: 16)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${playlist.songs.length}首', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SongListPage(playlist: playlist),
                    ),
                  );
                },
              ),
            );
          } else {
            // 新建播放列表按钮
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 28),
                title: const Text('新建播放列表', style: TextStyle(fontSize: 16, color: Colors.blue)),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('新建播放列表'),
                      content: const TextField(
                        decoration: InputDecoration(hintText: '输入列表名称'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                        FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('创建')),
                      ],
                    ),
                  );
                },
              ),
            );
          }
        },
      ),
    );
  }
}
