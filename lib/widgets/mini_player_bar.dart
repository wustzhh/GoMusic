import 'package:flutter/material.dart';
import '../pages/player_page.dart';
import '../models/music_data.dart';

class MiniPlayerBar extends StatelessWidget {
  final Song? currentSong;

  const MiniPlayerBar({super.key, this.currentSong});

  @override
  Widget build(BuildContext context) {
    // 使用第一首歌作为假数据当前播放
    final song = currentSong ?? mockAllSongs.first;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PlayerPage(song: song)),
        );
      },
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.music_note, color: Colors.deepPurple, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song.title, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                  Text(song.uploader, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.skip_previous, size: 28), onPressed: () {}),
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 32, color: Colors.deepPurple),
              onPressed: () {},
            ),
            IconButton(icon: const Icon(Icons.skip_next, size: 28), onPressed: () {}),
          ],
        ),
      ),
    );
  }
}
