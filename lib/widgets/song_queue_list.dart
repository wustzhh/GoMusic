import 'dart:io';

import 'package:flutter/material.dart';
import '../models/music_data.dart';

/// 播放列表（队列）按组显示的共享组件：
/// 多歌组优先显示（彩色框包裹），单曲在后；组内按组队顺序；
/// 当前歌曲高亮并自动定位。
class SongQueueList extends StatefulWidget {
  final List<Song> queue;
  final int currentIndex;
  final String playlistId;
  final void Function(Song) onPlay;
  final void Function(int) onRemove;
  const SongQueueList({
    super.key,
    required this.queue,
    required this.currentIndex,
    required this.playlistId,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  State<SongQueueList> createState() => _SongQueueListState();
}

class _SongQueueListState extends State<SongQueueList> {
  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _targetKey = GlobalKey();

  static const _groupColors = [
    Colors.amber, Colors.cyan, Colors.limeAccent, Colors.orangeAccent,
    Colors.pinkAccent, Colors.lightGreenAccent, Colors.tealAccent, Colors.redAccent,
    Colors.lightBlueAccent, Colors.purpleAccent,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void didUpdateWidget(SongQueueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 仅当当前歌曲位置或队列长度真正变化时重新定位
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.queue.length != widget.queue.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  void _locate() {
    if (!_scrollCtrl.hasClients || widget.queue.isEmpty) return;
    final cur = widget.queue[widget.currentIndex.clamp(0, widget.queue.length - 1)];
    // 先跳到估计位置让目标渲染，再 ensureVisible 精确定位
    final est = (widget.currentIndex * 64.0 - _scrollCtrl.position.viewportDimension / 2)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.jumpTo(est);
    int tries = 0;
    void loop() {
      if (tries++ > 10) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _targetKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
          return;
        }
        _scrollCtrl.jumpTo((_scrollCtrl.offset + _scrollCtrl.position.viewportDimension * 0.7)
            .clamp(0.0, _scrollCtrl.position.maxScrollExtent));
        loop();
      });
    }
    loop();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final queue = widget.queue;
    final items = <Widget>[];
    final used = <String>{};
    final groups = SongGroupService.getGroups(playlistId: widget.playlistId);
    var gi = 0;
    // 按 queue 顺序遍历：组内歌曲相邻输出并框住，单曲原位
    for (final s in queue) {
      if (used.contains(s.filePath)) continue;
      final g = groups.where((g) => g.songPaths.contains(s.bvid.isNotEmpty ? s.bvid : s.filePath)).firstOrNull;
      if (g != null) {
        // 按队列中的顺序取组内成员（队列已按组设置排列）
        final members = queue.where((x) => g.songPaths.contains(x.bvid.isNotEmpty ? x.bvid : x.filePath)).toList();
        if (members.isEmpty) continue;
        final color = _groupColors[gi % _groupColors.length];
        gi++;
        items.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(8),
            color: color.withValues(alpha: 0.08),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                Icon(Icons.group, size: 15, color: color),
                const SizedBox(width: 6),
                Expanded(child: Text(g.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text('${members.length}首', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                IconButton(
                  icon: Icon(g.shuffle ? Icons.shuffle : Icons.swap_horiz, size: 14, color: color),
                  tooltip: '', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () { SongGroupService.setGroupShuffle(g.id, !g.shuffle); setState(() {}); },
                ),
              ]),
            ),
            const Divider(height: 1, color: Colors.white12),
            ...members.map((m) {
              used.add(m.filePath);
              return _buildRow(m, queue.indexOf(m));
            }),
          ]),
        ));
      } else {
        used.add(s.filePath);
        items.add(_buildRow(s, queue.indexOf(s)));
      }
    }

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }

  Widget _buildRow(Song s, int idx) {
    final isCur = idx == widget.currentIndex;
    final tile = ListTile(
      dense: true,
      leading: _cover(s, isCur),
      title: Text(s.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isCur ? Colors.red : null), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(s.uploader, style: TextStyle(fontSize: 12, color: isCur ? Colors.red.withValues(alpha: 0.7) : Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: IconButton(icon: const Icon(Icons.close, size: 16), tooltip: '', onPressed: () => widget.onRemove(idx)),
    );
    if (isCur) {
      return Container(key: _targetKey, color: Colors.red.withValues(alpha: 0.08), child: InkWell(onTap: () => widget.onPlay(s), child: tile));
    }
    return InkWell(onTap: () => widget.onPlay(s), child: tile);
  }

  Widget _cover(Song s, bool isCur) {
    if (s.coverUrl != null && s.coverUrl!.isNotEmpty) {
      final f = File(s.coverUrl!);
      if (f.existsSync() && f.lengthSync() > 0) {
        return ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.file(f, width: 34, height: 34, fit: BoxFit.cover));
      }
    }
    return Icon(isCur ? Icons.play_arrow : Icons.music_note, color: isCur ? Colors.red : Colors.grey, size: 20);
  }
}
