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
  /// 当前播放歌曲的标题（用于定位/高亮，优先于 currentIndex）
  final String? currentTitle;
  /// 当前播放歌曲的 BV 号（title 匹配失败时兜底，bvid 唯一可靠）
  final String? currentBvid;
  final void Function(Song) onPlay;
  final void Function(int) onRemove;
  const SongQueueList({
    super.key,
    required this.queue,
    required this.currentIndex,
    required this.playlistId,
    this.currentTitle,
    this.currentBvid,
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
    // 仅当当前歌曲或队列真正变化时重新定位（按标题匹配）
    if (oldWidget.currentTitle != widget.currentTitle ||
        oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.queue.length != widget.queue.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  /// 当前播放歌曲在 queue 中的实际索引（按标题匹配 → bvid 兜底 → 索引兜底）
  int _curQueueIndex() {
    final t = widget.currentTitle;
    if (t != null && t.isNotEmpty) {
      for (var i = 0; i < widget.queue.length; i++) {
        if (widget.queue[i].title == t) return i;
      }
    }
    final bv = widget.currentBvid;
    if (bv != null && bv.isNotEmpty) {
      for (var i = 0; i < widget.queue.length; i++) {
        if (widget.queue[i].bvid == bv) return i;
      }
    }
    return widget.currentIndex.clamp(0, widget.queue.length - 1);
  }

  void _locate() {
    if (widget.queue.isEmpty) return;
    if (!_scrollCtrl.hasClients) {
      // 弹窗动画期间 ListView 尚未挂载：延迟重试
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
      return;
    }
    // 当前播放歌曲的 key（title 优先，bvid 兜底）
    final curKey = _songKey(widget.queue[_curQueueIndex()]);
    // 计算当前歌曲在渲染 items 中的真实 item 索引及其顶部偏移
    var targetItem = -1;
    var itemIdx = 0;
    final offsets = <double>[0.0];
    final used = <String>{};
    final groups = SongGroupService.getGroups(playlistId: widget.playlistId);
    // 预估 item 高度：组框 = 组头(约48) + 成员数*行高(约48)；单曲 = 行高(约48)
    // dense ListTile 实际约 48px
    const rowH = 48.0;
    for (final s in widget.queue) {
      if (used.contains(_songKey(s))) continue;
      final g = groups.where((g) => g.songPaths.contains(_songKey(s))).firstOrNull;
      if (g != null) {
        final members = widget.queue.where((x) => g.songPaths.contains(_songKey(x))).toList();
        if (members.isEmpty) continue;
        for (final m in members) {
          used.add(_songKey(m));
          if (_songKey(m) == curKey) targetItem = itemIdx;
        }
        offsets.add(offsets.last + 48 + members.length * rowH);
        itemIdx++;
      } else {
        used.add(_songKey(s));
        if (_songKey(s) == curKey) targetItem = itemIdx;
        offsets.add(offsets.last + rowH);
        itemIdx++;
      }
    }
    if (targetItem < 0) return;
    // 先滚动到目标 item 的顶部附近（保守靠前），逐帧逼近直到目标渲染
    final est = offsets[targetItem].clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.jumpTo(est);
    int tries = 0;
    void loop() {
      if (tries++ > 15) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final ctx = _targetKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
          return;
        }
        // 目标未渲染（builder 懒加载 + 高度估算偏差）：
        // 估算位置已到上限（目标在尾部）→ 直接滚到底；否则向目标偏移方向二分逼近
        final target = offsets[targetItem].clamp(0.0, _scrollCtrl.position.maxScrollExtent);
        final maxE = _scrollCtrl.position.maxScrollExtent;
        final isAtTarget = (_scrollCtrl.offset - target).abs() < 1.0;
        if (isAtTarget) {
          // 估算已到 target 但仍未渲染：多半是估算偏小，滚向尾部
          _scrollCtrl.jumpTo((_scrollCtrl.offset + (maxE - _scrollCtrl.offset) * 0.6)
              .clamp(0.0, maxE));
        } else {
          _scrollCtrl.jumpTo((_scrollCtrl.offset + (target - _scrollCtrl.offset) * 0.5)
              .clamp(0.0, maxE));
        }
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
      if (used.contains(_songKey(s))) continue;
      final g = groups.where((g) => g.songPaths.contains(_songKey(s))).firstOrNull;
      if (g != null) {
        // 按队列中的顺序取组内成员（队列已按组设置排列）
        final members = queue.where((x) => g.songPaths.contains(_songKey(x))).toList();
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
              used.add(_songKey(m));
              return _buildRow(m, queue.indexOf(m));
            }),
          ]),
        ));
      } else {
        used.add(_songKey(s));
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

  /// 歌曲统一标识：BV号优先，否则文件名（不含扩展名）
  String _songKey(Song s) {
    if (s.bvid.isNotEmpty) return s.bvid;
    final name = s.filePath.split('\\').last.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  Widget _buildRow(Song s, int idx) {
    // 高亮/定位：优先按 title/bvid 匹配（任一命中即当前歌曲）；
    // 两者都未提供时才用索引兜底（避免 currentIndex 与播放不一致时高亮错）
    final t = widget.currentTitle;
    final bv = widget.currentBvid;
    final hasAnchor = (t != null && t.isNotEmpty) || (bv != null && bv.isNotEmpty);
    final byTitle = t != null && t.isNotEmpty && s.title == t;
    final byBvid = bv != null && bv.isNotEmpty && s.bvid == bv;
    final isCur = hasAnchor ? (byTitle || byBvid) : idx == widget.currentIndex;
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
