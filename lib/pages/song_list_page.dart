import 'dart:io';
import 'package:flutter/material.dart';
import '../models/music_data.dart';
import 'player_page.dart';

class SongListPage extends StatelessWidget {
  final Playlist playlist;
  const SongListPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(playlist.name), centerTitle: true, actions: [
        PopupMenuButton<String>(itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('编辑列表')),
          const PopupMenuItem(value: 'delete', child: Text('删除列表')),
        ]),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(hintText: '搜索歌曲...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), contentPadding: const EdgeInsets.symmetric(vertical: 0)),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlist.songs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final song = playlist.songs[index];
              return ListTile(
                leading: _buildCover(song),
                title: Text(song.title, style: const TextStyle(fontSize: 15)),
                subtitle: Text(
                  _buildSubtitle(song),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                trailing: Text(song.durationText, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(song: song)));
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _buildCover(Song song) {
    if (song.coverUrl != null && song.coverUrl!.isNotEmpty) {
      final file = File(song.coverUrl!);
      if (file.existsSync()) {
        return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(file, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, e, s) => _musicIcon()));
      }
      if (song.coverUrl!.startsWith('http')) {
        return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(song.coverUrl!, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, e, s) => _musicIcon()));
      }
    }
    return _musicIcon();
  }

  Widget _musicIcon() => const Icon(Icons.music_note, color: Colors.deepPurple, size: 32);

  String _buildSubtitle(Song song) {
    final parts = <String>[];
    if (song.uploader.isNotEmpty) parts.add(song.uploader);
    if (song.lastPlayedText.isNotEmpty) parts.add(song.lastPlayedText);
    return parts.join(' · ');
  }
}
