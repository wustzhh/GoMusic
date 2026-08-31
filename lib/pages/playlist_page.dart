import 'dart:io';
import 'package:flutter/material.dart';
import '../main.dart';
import '../models/music_data.dart';
import '../services/settings_service.dart';
import '../services/audio_player_service.dart';
import '../services/playlist_cover_manager.dart';
import '../ui/theme_components.dart';
import 'song_list_page.dart';

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({super.key});
  @override
  PlaylistPageState createState() => PlaylistPageState();
}

class PlaylistPageState extends State<PlaylistPage> {
  List<Playlist> _playlists = [];
  bool _loaded = false;
  final PlaylistCoverManager _coverManager = PlaylistCoverManager();

  @override
  void initState() {
    super.initState();
    AudioPlayerService().favoritesChangedNotifier.addListener(() => refresh());
    downloadsChangedNotifier.addListener(_onDownloadsChanged);
    _loadPlaylists();
  }

  @override
  void dispose() {
    AudioPlayerService().favoritesChangedNotifier.removeListener(
      () => refresh(),
    );
    downloadsChangedNotifier.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  void _onDownloadsChanged() {
    refresh();
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
    final recentBvids = await RecentlyPlayedService.getRecentBvids();
    final recentSongs = recentBvids.map((bv) {
      return localSongs
              .where((s) => s.bvid == bv || _fileNameKey(s) == bv)
              .firstOrNull ??
          Song(
            id: bv,
            title: bv,
            uploader: '',
            duration: Duration.zero,
            bvid: bv,
            filePath: '',
          ); // 占位：数量保持真实
    }).toList();
    final favPaths = await AudioPlayerService.getFavorites();
    final favSongs = favPaths.map((k) {
      return localSongs
              .where((s) => s.bvid == k || _fileNameKey(s) == k)
              .firstOrNull ??
          Song(
            id: k,
            title: k,
            uploader: '',
            duration: Duration.zero,
            bvid: k,
            filePath: '',
          ); // 占位：数量保持真实
    }).toList();
    var customPls = await PlaylistService.getPlaylists();
    final defaultCovers = <String, String?>{
      'fav': await PlaylistService.getDefaultPlaylistCover('fav'),
      'local': await PlaylistService.getDefaultPlaylistCover('local'),
      'recent': await PlaylistService.getDefaultPlaylistCover('recent'),
    };
    // 本地歌单：拖动过则应用拖动顺序；否则按添加顺序（mtime 倒序，最后添加的放最上面）
    final localOrder = await SongManager.getLocalOrder();
    List<Song> localList;
    if (localOrder.isNotEmpty) {
      final byKey = {for (final s in localSongs) _fileNameKey(s): s};
      final ordered = <Song>[];
      for (final k in localOrder) {
        final s = byKey[k];
        if (s != null) {
          ordered.add(s);
          byKey.remove(k);
        }
      }
      // 未记录的新歌（如刚下载的）：按添加顺序（mtime 倒序）插到最前
      final rest = byKey.values.toList()
        ..sort((a, b) => _mtimeOf(b.filePath).compareTo(_mtimeOf(a.filePath)));
      ordered.insertAll(0, rest);
      localList = ordered;
    } else {
      localList = List.from(localSongs)
        ..sort((a, b) {
          final ma = _mtimeOf(a.filePath);
          final mb = _mtimeOf(b.filePath);
          return mb.compareTo(ma);
        });
    }
    // 补全自定义歌单歌曲信息（标题/封面，用BV号匹配本地对照表）
    for (var i = 0; i < customPls.length; i++) {
      final pl = customPls[i];
      final songs = pl.songs.map((s) {
        final bv = s.bvid.isNotEmpty
            ? s.bvid
            : s.filePath.split('\\').last.split('/').last.split('.').first;
        final full = localSongs
            .where((x) => x.bvid == bv || _fileNameKey(x) == bv)
            .firstOrNull;
        return full ?? s;
      }).toList();
      customPls[i] = Playlist(
        id: pl.id,
        name: pl.name,
        icon: pl.icon,
        songs: songs,
        coverPath: pl.coverPath,
        lastPlayedAt: pl.lastPlayedAt,
      );
    }

    if (!mounted) return;
    setState(() {
      _playlists = [
        Playlist(
          id: 'fav',
          name: '我喜欢',
          icon: '❤️',
          songs: favSongs,
          coverPath: defaultCovers['fav'],
        ),
        ...customPls,
        Playlist(
          id: 'local',
          name: '本地歌单',
          icon: '📁',
          songs: localList,
          coverPath: defaultCovers['local'],
        ),
        Playlist(
          id: 'recent',
          name: '最近播放',
          icon: '🕐',
          songs: recentSongs,
          coverPath: defaultCovers['recent'],
        ),
      ];
      _loaded = true;
    });
  }

  /// 文件修改时间（不存在返回 epoch）
  DateTime _mtimeOf(String path) {
    try {
      final f = File(path);
      return f.existsSync()
          ? f.statSync().modified
          : DateTime.fromMillisecondsSinceEpoch(0);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _fileNameKey(Song s) {
    if (s.bvid.isNotEmpty) return s.bvid;
    final name = s.filePath.split('\\').last.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Widget _playlistCover(Playlist pl) {
    final coverPath = pl.coverPath;
    if (coverPath != null && coverPath.isNotEmpty) {
      if (coverPath.startsWith('http://') || coverPath.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            coverPath,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Text(pl.icon, style: const TextStyle(fontSize: 28)),
          ),
        );
      }
      final cover = File(coverPath);
      if (cover.existsSync() && cover.lengthSync() > 0) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(cover, width: 40, height: 40, fit: BoxFit.cover),
        );
      }
    }
    if (pl.songs.isNotEmpty) {
      final first = pl.songs.first;
      if (first.coverUrl != null && first.coverUrl!.isNotEmpty) {
        final f = File(first.coverUrl!);
        if (f.existsSync() && f.lengthSync() > 0) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(f, width: 40, height: 40, fit: BoxFit.cover),
          );
        }
      }
    }
    return Text(pl.icon, style: const TextStyle(fontSize: 28));
  }

  Future<void> _setCustomCover(Playlist pl) async {
    final controller = TextEditingController(text: pl.coverPath ?? '');
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置歌单封面'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入本地图片路径或 http(s) 图片地址，留空清除',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (path == null) return;
    try {
      String? savedPath;
      if (path.isNotEmpty) {
        if (path.startsWith('http://') || path.startsWith('https://')) {
          savedPath = path;
        } else {
          savedPath = await _coverManager.copyLocalCover(path, ownerId: pl.id);
          if (pl.coverPath != null &&
              pl.coverPath != savedPath &&
              !(pl.coverPath!.startsWith('http://') ||
                  pl.coverPath!.startsWith('https://'))) {
            try {
              await _coverManager.deleteCover(pl.coverPath!);
            } catch (_) {}
          }
        }
      }
      await PlaylistService.setPlaylistCover(pl.id, savedPath);
      await refresh();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('封面保存失败，请检查图片路径')));
    }
  }

  Future<void> _deleteCustomPlaylist(
    Playlist pl,
    BuildContext settingsContext,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除“${pl.name}”吗？歌曲文件不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await PlaylistService.deletePlaylist(pl.id);
    final cover = pl.coverPath;
    if (cover != null &&
        cover.isNotEmpty &&
        !(cover.startsWith('http://') || cover.startsWith('https://'))) {
      try {
        await _coverManager.deleteCover(cover);
      } catch (_) {}
    }
    if (settingsContext.mounted) Navigator.pop(settingsContext);
    await refresh();
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
                        leading: Text(
                          pl.icon,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          pl.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_upward, size: 16),
                              tooltip: '',
                              onPressed: i == 0
                                  ? null
                                  : () async {
                                      await PlaylistService.movePlaylist(
                                        i,
                                        i - 1,
                                      );
                                      setDlg(() {});
                                      refresh();
                                    },
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward, size: 16),
                              tooltip: '',
                              onPressed: i == custom.length - 1
                                  ? null
                                  : () async {
                                      await PlaylistService.movePlaylist(
                                        i,
                                        i + 1,
                                      );
                                      setDlg(() {});
                                      refresh();
                                    },
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.emoji_emotions_outlined,
                                size: 16,
                              ),
                              onSelected: (icon) async {
                                await PlaylistService.setPlaylistIcon(
                                  pl.id,
                                  icon,
                                );
                                setDlg(() {});
                                refresh();
                              },
                              itemBuilder: (_) =>
                                  [
                                        '📋',
                                        '🎵',
                                        '🎧',
                                        '⭐',
                                        '🔥',
                                        '💿',
                                        '📀',
                                        '🎤',
                                        '🎸',
                                        '🎹',
                                        '🎻',
                                        '🥁',
                                        '🪕',
                                        '🎺',
                                        '🎷',
                                        '🫧',
                                        '💜',
                                        '💙',
                                        '💚',
                                        '💛',
                                        '🧡',
                                        '🖤',
                                        '🤍',
                                      ]
                                      .map(
                                        (e) => PopupMenuItem(
                                          value: e,
                                          child: Text(
                                            e,
                                            style: const TextStyle(
                                              fontSize: 20,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                            IconButton(
                              key: ValueKey('playlist-cover-${pl.id}'),
                              icon: const Icon(Icons.image_outlined, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _setCustomCover(pl),
                            ),
                            IconButton(
                              key: ValueKey('playlist-delete-${pl.id}'),
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: Colors.red,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _deleteCustomPlaylist(pl, ctx),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(
        backgroundColor: Colors.transparent, // 透出全局动态背景
        appBar: AppBar(title: const Text('播放列表'), centerTitle: true),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent, // 透出全局动态背景
      appBar: AppBar(
        // 不显示合计数量：同一首歌可在多个歌单，简单相加会重复计数
        title: const Text('播放列表'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            tooltip: '歌单设置',
            onPressed: _showSettings,
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _playlists.length + 1,
        itemBuilder: (context, index) {
          if (index < _playlists.length) {
            final pl = _playlists[index];
            return ThemeComponents.panel(
              context,
              margin: const EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: _playlistCover(pl),
                title: Text(pl.name, style: const TextStyle(fontSize: 16)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${pl.songs.length}首',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SongListPage(playlist: pl),
                    ),
                  ).then((_) => refresh());
                },
              ),
            );
          } else {
            return ThemeComponents.panel(
              context,
              margin: const EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(
                  Icons.add_circle_outline,
                  color: Colors.blue,
                  size: 28,
                ),
                title: const Text(
                  '新建播放列表',
                  style: TextStyle(fontSize: 16, color: Colors.blue),
                ),
                onTap: () {
                  final ctrl = TextEditingController();
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('新建播放列表'),
                      content: TextField(
                        controller: ctrl,
                        decoration: const InputDecoration(
                          hintText: '输入列表名称',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () async {
                            if (ctrl.text.trim().isNotEmpty) {
                              await PlaylistService.addPlaylist(
                                ctrl.text.trim(),
                              );
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
