import 'package:flutter/material.dart';
import '../models/music_data.dart';
import '../services/settings_service.dart';
import '../services/audio_player_service.dart';
import 'song_list_page.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});
  @override
  PlaylistPageState createState() => PlaylistPageState();
}

class PlaylistPageState extends State<PlaylistPage> {
  List<Playlist> _playlists = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    AudioPlayerService().favoritesChangedNotifier.addListener(() => refresh());
    _loadPlaylists();
  }

  Future<void> refresh() {
    _loaded = false;
    if (mounted) setState(() {});
    return _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final service = await SettingsService.getInstance();
    final dir = await service.getDownloadPath();
    final localSongs = await scanLocalAudioFiles(dir);
    final recentSongs = await RecentlyPlayedService.getRecentSongs();
    final favPaths = await AudioPlayerService.getFavorites();
    final favSongs = favPaths.map((fp) => localSongs.where((s) => s.filePath == fp).firstOrNull).where((s) => s != null).cast<Song>().toList();
    final customPls = await PlaylistService.getPlaylists();

    if (!mounted) return;
    setState(() {
      _playlists = [
        Playlist(id: 'fav', name: '我喜欢', icon: '❤️', songs: favSongs),
        ...customPls,
        Playlist(id: 'local', name: '本地歌单', icon: '📁', songs: List.from(localSongs)..sort((a,b) => a.title.compareTo(b.title))),
        Playlist(id: 'recent', name: '最近播放', icon: '🕐', songs: recentSongs),
      ];
      _loaded = true;
    });
  }

  void _showSettings() async {
    final custom = await PlaylistService.getPlaylists();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('歌单设置', style: TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 320,
            child: custom.isEmpty
              ? const Text('暂无自定义歌单', style: TextStyle(color: Colors.grey))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: custom.length,
                  itemBuilder: (_, i) {
                    final pl = custom[i];
                    return ListTile(
                      dense: true,
                      leading: Text(pl.icon, style: const TextStyle(fontSize: 22)),
                      title: Text(pl.name, style: const TextStyle(fontSize: 14)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.arrow_upward, size: 16), tooltip: '', onPressed: i == 0 ? null : () async {
                          await PlaylistService.movePlaylist(i, i - 1);
                          setDlg(() {});
                          refresh();
                        }),
                        IconButton(icon: const Icon(Icons.arrow_downward, size: 16), tooltip: '', onPressed: i == custom.length - 1 ? null : () async {
                          await PlaylistService.movePlaylist(i, i + 1);
                          setDlg(() {});
                          refresh();
                        }),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.emoji_emotions_outlined, size: 16),
                          onSelected: (icon) async {
                            await PlaylistService.setPlaylistIcon(pl.id, icon);
                            setDlg(() {});
                            refresh();
                          },
                          itemBuilder: (_) => ['📋','🎵','🎧','⭐','🔥','💿','📀','🎤','🎸','🎹','🎻','🥁','🪕','🎺','🎷','🫧','💜','💙','💚','💛','🧡','🖤','🤍'].map((e) => PopupMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 20)))).toList(),
                        ),
                      ]),
                    );
                  },
                ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('播放列表'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('播放列表'), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.tune, size: 20), tooltip: '', onPressed: _showSettings),
      ]),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _playlists.length + 1,
        itemBuilder: (context, index) {
          if (index < _playlists.length) {
            final pl = _playlists[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Text(pl.icon, style: const TextStyle(fontSize: 28)),
                title: Text(pl.name, style: const TextStyle(fontSize: 16)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${pl.songs.length}首', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SongListPage(playlist: pl),
                  )).then((_) => refresh());
                },
              ),
            );
          } else {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.add_circle_outline, color: Colors.blue, size: 28),
                title: const Text('新建播放列表', style: TextStyle(fontSize: 16, color: Colors.blue)),
                onTap: () {
                  final ctrl = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('新建播放列表'),
                      content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '输入列表名称', border: OutlineInputBorder())),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                        FilledButton(
                          onPressed: () async {
                            if (ctrl.text.trim().isNotEmpty) {
                              await PlaylistService.addPlaylist(ctrl.text.trim());
                            }
                            Navigator.pop(ctx);
                            refresh();
                          },
                          child: const Text('创建'),
                        ),
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
