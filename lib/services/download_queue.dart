import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_data.dart';

import 'bilibili_api.dart';
import 'settings_service.dart';

/// 下载任务状态
enum DownloadTaskStatus { waiting, downloading, done, failed }

/// 下载任务（持久化在 SharedPreferences，不依赖解析结果）
class DownloadTask {
  final String bvid;
  String title;
  String uploader;
  String coverUrl;
  bool audio;      // 勾选音频
  bool video;      // 勾选视频
  DownloadTaskStatus status;
  double progress; // 0~1
  String error;
  bool paused = false;      // 用户暂停
  ValueNotifier<bool>? cancel; // 下载取消标志（暂停时触发）
  ValueNotifier<int>? internalChanged; // 单个任务进度刷新

  DownloadTask({
    required this.bvid,
    required this.title,
    this.uploader = '',
    this.coverUrl = '',
    this.audio = true,
    this.video = false,
    this.status = DownloadTaskStatus.waiting,
    this.progress = 0,
    this.error = '',
  });

  Map<String, dynamic> toJson() => {
        'bvid': bvid, 'title': title, 'uploader': uploader, 'coverUrl': coverUrl,
        'audio': audio, 'video': video,
        'status': status.index, 'progress': progress, 'error': error, 'paused': paused,
      };

  static DownloadTask fromJson(Map<String, dynamic> m) => DownloadTask(
        bvid: m['bvid'] as String? ?? '',
        title: m['title'] as String? ?? '',
        uploader: m['uploader'] as String? ?? '',
        coverUrl: m['coverUrl'] as String? ?? '',
        audio: m['audio'] as bool? ?? true,
        video: m['video'] as bool? ?? false,
        status: DownloadTaskStatus.values[m['status'] as int? ?? 0],
        progress: (m['progress'] as num? ?? 0).toDouble(),
        error: m['error'] as String? ?? '',
      )..paused = m['paused'] as bool? ?? false;
}

/// 下载队列：独立于解析结果，任务持久化、逐个执行
class DownloadQueueService {
  static const _key = 'download_queue';
  static final List<DownloadTask> tasks = [];
  static bool _loaded = false;
  static bool _processing = false;

  /// 任务变化通知（UI 刷新）
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        tasks.clear();
        tasks.addAll(list.map((e) => DownloadTask.fromJson(e as Map<String, dynamic>)));
      }
    } catch (_) {}
  }

  static Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(tasks.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  /// 添加任务入队
  static Future<void> add({
    required String bvid,
    required String title,
    String uploader = '',
    String coverUrl = '',
    bool audio = true,
    bool video = false,
  }) async {
    await ensureLoaded();
    // 去重：同 bvid 且已完成/等待中的不重复加
    if (tasks.any((t) => t.bvid == bvid && t.status != DownloadTaskStatus.failed)) {
      changed.value++;
      return;
    }
    tasks.add(DownloadTask(bvid: bvid, title: title, uploader: uploader, coverUrl: coverUrl, audio: audio, video: video));
    await _persist();
    changed.value++;
    // 自动开始处理
    process();
  }

  /// 移除任务（同时删除缓存区的部分下载文件）
  static Future<void> remove(int index) async {
    if (index < 0 || index >= tasks.length) return;
    final t = tasks[index];
    // 取消进行中的下载
    t.cancel?.value = true;
    // 删除缓存区（.tmp）中该任务的部分文件
    try {
      final svc = await SettingsService.getInstance();
      final dir = await svc.getDownloadPath();
      final tmpDir = Directory('$dir/.tmp');
      if (tmpDir.existsSync()) {
        for (final f in tmpDir.listSync()) {
          if (f is File && f.path.contains(t.bvid)) {
            try { f.deleteSync(); } catch (_) {}
          }
        }
      }
    } catch (_) {}
    tasks.removeAt(index);
    await _persist();
    changed.value++;
  }

  /// 暂停下载（保留 .part，支持续传）
  static void pause(DownloadTask task) {
    task.paused = true;
    task.cancel?.value = true; // 中断当前下载
    task.status = DownloadTaskStatus.waiting;
    changed.value++;
    _persist();
  }

  /// 继续下载（断点续传）
  static void resume(DownloadTask task) {
    task.paused = false;
    task.cancel?.value = false;
    task.status = DownloadTaskStatus.waiting;
    changed.value++;
    _persist();
    process();
  }

  /// 重试失败任务
  static Future<void> retry(int index) async {
    if (index < 0 || index >= tasks.length) return;
    tasks[index].status = DownloadTaskStatus.waiting;
    tasks[index].progress = 0;
    tasks[index].error = '';
    await _persist();
    changed.value++;
    process();
  }

  /// 队列处理循环：逐个执行等待中的任务
  static void process() {
    if (_processing) return;
    _processing = true;
    _run();
  }

  static Future<void> _run() async {
    try {
      await ensureLoaded();
      final api = BilibiliApi();
      final svc = await SettingsService.getInstance();
      final dir = await svc.getDownloadPath();
      while (true) {
        // 找下一个等待任务（跳过暂停的）
        DownloadTask? task;
        for (final t in tasks) {
          if (t.status == DownloadTaskStatus.waiting && !t.paused) { task = t; break; }
        }
        if (task == null) break;

        task.status = DownloadTaskStatus.downloading;
        task.progress = 0;
        task.cancel = ValueNotifier(false);
        task.internalChanged = ValueNotifier(0);
        changed.value++;
        await _persist();

        try {
          final name = task.bvid;
          final url = 'https://www.bilibili.com/video/${task.bvid}';
          final info = await api.getVideoInfo(url);
          if (info == null) {
            task.status = DownloadTaskStatus.failed;
            task.error = '解析失败';
            changed.value++;
            await _persist();
            continue;
          }

          var fail = false;
          if (task.paused) {
            // 暂停：恢复等待状态，保留 .part（断点续传）
            task.status = DownloadTaskStatus.waiting;
            changed.value++;
            await _persist();
            continue;
          }
          // 封面
          if (info.coverUrl.isNotEmpty) {
            final ok = await StreamDownloader.download(url: info.coverUrl, savePath: '$dir/$name.jpg', onProgress: (_) {});
            if (!ok) fail = true;
          } else {
            fail = true;
          }
          // 音频
          if (!fail && task.audio) {
            if (info.audioUrl == null) {
              fail = true;
            } else {
              final ok = await StreamDownloader.download(
                url: info.audioUrl!, savePath: '$dir/$name.m4a',
                onProgress: (p) { task!.progress = p * 0.5; task!.internalChanged?.value++; },
                cancel: task.cancel,
                expectedSize: info.audioSize > 0 ? info.audioSize : null,
              );
              if (!ok) fail = true;
            }
          }
          // 视频
          if (!fail && task.video) {
            if (info.videoStreams.isEmpty) {
              fail = true;
            } else {
              final best = info.videoStreams.first;
              final ok = await StreamDownloader.download(
                url: best.baseUrl!, savePath: '$dir/$name.mp4',
                onProgress: (p) { task!.progress = 0.5 + p * 0.5; task!.internalChanged?.value++; },
                cancel: task.cancel,
                expectedSize: best.size > 0 ? best.size : null,
              );
              if (!ok) fail = true;
            }
          }

          // 最终校验
          if (!fail) {
            if (task.audio && !(File('$dir/$name.m4a').existsSync() && File('$dir/$name.m4a').lengthSync() > 0)) fail = true;
            if (task.video && !(File('$dir/$name.mp4').existsSync() && File('$dir/$name.mp4').lengthSync() > 0)) fail = true;
            if (!(File('$dir/$name.jpg').existsSync() && File('$dir/$name.jpg').lengthSync() > 0)) fail = true;
          }

          if (fail) {
            try {
              if (task.audio) File('$dir/$name.m4a').deleteSync();
              if (task.video) File('$dir/$name.mp4').deleteSync();
              File('$dir/$name.jpg').deleteSync();
            } catch (_) {}
            task.status = DownloadTaskStatus.failed;
            task.error = '下载不完整';
          } else {
            // 完成：登记数据管理器
            SongManager.registerSong(
              filePath: '$dir/$name.m4a',
              title: task.title.isNotEmpty ? task.title : info.title,
              uploader: task.uploader.isNotEmpty ? task.uploader : info.author,
              durationSec: info.durationSeconds,
              bvid: task.bvid,
              url: info.url,
              coverPath: '$dir/$name.jpg',
              videoPath: task.video ? '$dir/$name.mp4' : null,
            );
            // 完成后从队列清除
            tasks.remove(task);
          }
        } catch (e) {
          task.status = DownloadTaskStatus.failed;
          task.error = e.toString();
        }
        changed.value++;
        await _persist();
      }
    } finally {
      _processing = false;
    }
  }
}
