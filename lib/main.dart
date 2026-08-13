import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:window_manager/window_manager.dart';
import 'package:audio_service/audio_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'pages/download_page.dart';
import 'pages/playlist_page.dart';
import 'pages/settings_page.dart';
import 'pages/video_page.dart';
import 'services/settings_service.dart';
import 'services/bilibili_api.dart';
import 'models/music_data.dart';
import 'services/audio_player_service.dart';
import 'services/audio_handler.dart';
import 'services/hotkey_service.dart';
import 'widgets/mini_player_bar.dart';

void _logMs(String msg) {
  try {
    final tmp = Directory.systemTemp;
    File('${tmp.path}${Platform.pathSeparator}gomusic_debug.log').writeAsStringSync('[${DateTime.now().toIso8601String().substring(11, 19)}] [MS] $msg\n', mode: FileMode.append);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'gomusic_download',
      channelName: '下载通知',
      channelDescription: 'GoMusic 下载进度',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWifiLock: true,
    ),
  );
  // 初始化窗口管理（仅 Windows 支持；Android 无此插件实现）
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  final service = await SettingsService.getInstance();
  BilibiliApi.cookie = await service.getBilibiliCookie();
  await BilibiliApi.ensureBuvid3();

  // 恢复上次播放状态
  final audioService = AudioPlayerService();
  await audioService.restoreLastSong();
  // Windows 独立音量恢复 + 全局快捷键注册（Ctrl+Alt+方向键）
  if (Platform.isWindows) {
    await audioService.restoreVolume();
    await HotkeyService.instance.init();
  }

  runApp(const GoMusicApp());

  // 媒体会话（Android：耳机键/通知栏/锁屏控制）——延迟到界面显示后初始化，
  // 不阻塞启动（权限弹窗/audio_service 初始化失败都不影响首屏）
  if (Platform.isAndroid) {
    _initMediaSession();
  }
}

/// 初始化媒体会话（异步，不阻塞启动；失败静默）
Future<void> _initMediaSession() async {
  try {
    _logMs('media session init start');
    // Android 13+ 通知权限（媒体通知/锁屏控制需要；不强制等待）
    await Permission.notification.request();
    await AudioService.init(
      builder: () => GoMusicAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.gomusic.channel.playback',
        androidNotificationChannelName: 'GoMusic 播放控制',
        androidNotificationOngoing: true,
      ),
    );
    _logMs('media session init ok');
  } catch (_) {
    // 媒体会话失败不影响正常使用
  }
}

class GoMusicApp extends StatefulWidget {
  const GoMusicApp({super.key});

  @override
  State<GoMusicApp> createState() => _GoMusicAppState();
}

/// 全局主题模式通知（0:浅色 1:深色 2:跟随系统）；设置页切换时更新
final themeModeNotifier = ValueNotifier<int>(1);

/// 全局"下载完成"通知：下载页下载完触发，视频页/歌单页监听后自动刷新
final downloadsChangedNotifier = ValueNotifier<int>(0);

class _GoMusicAppState extends State<GoMusicApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SongGroupService.init(); // 分组数据加载（SharedPreferences，覆盖安装保留）
    // 启动时从存储读取主题模式
    SettingsService.getInstance().then((s) {
      themeModeNotifier.value = s.getThemeMode();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeModeNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从 B站等外部 app 切回时：被抢占暂停的播放自动恢复
    if (state == AppLifecycleState.resumed) {
      AudioPlayerService().onAppResumed();
    }
  }

  ThemeMode _resolveThemeMode(int m) {
    switch (m) {
      case 0: return ThemeMode.light;
      case 2: return ThemeMode.system;
      default: return ThemeMode.dark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        final themeMode = _resolveThemeMode(mode);
        return MaterialApp(
          title: 'GoMusic',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light), useMaterial3: true,
            pageTransitionsTheme: const PageTransitionsTheme(builders: {
              TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
              TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
              TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
            }),
          ),
          darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark), useMaterial3: true,
            pageTransitionsTheme: const PageTransitionsTheme(builders: {
              TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
              TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
              TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
            }),
          ),
          themeMode: themeMode,
          home: const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 1;
  final _playlistKey = GlobalKey<PlaylistPageState>();

  late final List<Widget> _pages = [
    const DownloadPage(),
    PlaylistPage(key: _playlistKey),
    const VideoPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(),
          BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() => _currentIndex = index);
              // 切换到播放页时刷新
              if (index == 1) _playlistKey.currentState?.refresh();
            },
            selectedItemColor: Colors.deepPurpleAccent,
            unselectedItemColor: Colors.grey[400],
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.download), label: '下载'),
              BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline), label: '播放'),
              BottomNavigationBarItem(icon: Icon(Icons.video_library_outlined), label: '视频'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '设置'),
            ],
          ),
        ],
      ),
    );
  }
}
