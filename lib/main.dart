import 'dart:io';

import 'package:flutter/gestures.dart';
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
import 'ui/dynamic_background.dart';
import 'ui/skin.dart';
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

  // 恢复界面皮肤（默认素·深色）
  skinNotifier.value = Skins.byId(service.getSkin());

  // 恢复上次播放状态
  final audioService = AudioPlayerService();
  await audioService.restoreLastSong();
  // Windows 独立音量恢复 + 全局快捷键注册（Ctrl+Alt+方向键）
  if (Platform.isWindows) {
    await audioService.restoreVolume();
    await HotkeyService.instance.init();
  }

  runApp(const GoMusicApp());

  // 媒体会话（Android：耳机键/通知栏/锁屏控制；Windows：SMTC 系统媒体卡片/音量 OSD）
  // 延迟到界面显示后初始化，不阻塞启动（权限弹窗/初始化失败都不影响首屏）
  if (Platform.isAndroid || Platform.isWindows) {
    _initMediaSession();
  }
}

/// 提前创建媒体会话处理器单例（消除竞态：
/// 若等 AudioService.init 的 builder 异步创建，用户启动后立即播放视频时
/// instance 仍为 null，视频页 attach 委托失败 → 耳机键无路由、前台服务未启动）
GoMusicAudioHandler ensureMediaHandler() {
  return GoMusicAudioHandler.instance ??= GoMusicAudioHandler();
}

/// 初始化媒体会话（异步，不阻塞启动；失败静默）
Future<void> _initMediaSession() async {
  try {
    _logMs('media session init start');
    // Android 13+ 通知权限（媒体通知/锁屏控制需要；不强制等待）
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    await AudioService.init(
      builder: ensureMediaHandler, // 复用提前创建的单例（不新建）
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

/// 全局界面皮肤通知（设置页切换时更新，动态背景/主题色实时响应）
/// 默认：极光（启动即有动态背景）
final skinNotifier = ValueNotifier<SkinStyle>(Skins.aurora);

/// 全局"下载完成"通知：下载页下载完触发，视频页/歌单页监听后自动刷新
final downloadsChangedNotifier = ValueNotifier<int>(0);

class _GoMusicAppState extends State<GoMusicApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SongGroupService.init(); // 分组数据加载（SharedPreferences，覆盖安装保留）
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    skinNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从 B站等外部 app 切回时：被抢占暂停的播放自动恢复
    if (state == AppLifecycleState.resumed) {
      AudioPlayerService().onAppResumed();
    }
  }

  ThemeMode _resolveThemeMode(bool dark) {
    return dark ? ThemeMode.dark : ThemeMode.light;
  }

  /// 按皮肤构建完整主题：卡片玻璃/发光、按钮形状圆角、AppBar/导航透明风格
  ThemeData _buildTheme(SkinStyle skin, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: skin.accent, brightness: brightness);
    final ui = skin.ui;
    final radius = BorderRadius.circular(ui.radius);
    final cardColor = ui.glassy
        ? scheme.surface.withValues(alpha: ui.glassOpacity)
        : scheme.surface;
    final cardBorder = ui.glassy
        ? BorderSide(
            color: ui.neonGlow
                ? skin.accent.withValues(alpha: 0.85)
                : skin.accent.withValues(alpha: 0.30),
            width: ui.neonGlow ? 1.6 : 1.0,
          )
        : BorderSide.none;
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
      }),
      // 卡片：玻璃拟态/霓虹描边/主题圆角（全部页面 Card 自动跟随）
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: radius, side: cardBorder),
      ),
      // AppBar：动态皮肤透明融入背景
      appBarTheme: AppBarTheme(
        backgroundColor: ui.appBarTransparent ? Colors.transparent : scheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      // 底部导航：玻璃化
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: ui.navTransparent
            ? scheme.surface.withValues(alpha: 0.65)
            : scheme.surface,
        elevation: 0,
        selectedItemColor: skin.accent,
      ),
      // 按钮：全局圆角随主题
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: ui.glassy ? BorderSide(color: skin.accent.withValues(alpha: 0.5)) : null,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ui.glassy
            ? scheme.surface.withValues(alpha: 0.92)
            : scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ui.radius)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: skin.accent,
        thumbColor: skin.accent,
        overlayColor: skin.accent.withValues(alpha: 0.15),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SkinStyle>(
      valueListenable: skinNotifier,
      builder: (context, skin, _) {
        final themeMode = _resolveThemeMode(skin.dark);
        return MaterialApp(
          title: 'GoMusic',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      // 桌面端：允许鼠标拖拽滚动列表（Flutter 默认只支持触屏/触控笔）
      scrollBehavior: const _DesktopScrollBehavior(),
      theme: _buildTheme(skin, Brightness.light),
      darkTheme: _buildTheme(skin, Brightness.dark),
      themeMode: themeMode,
      // 全局动态背景：唯一实例，位于所有页面之下，切页不闪屏、动画不重启
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          const DynamicBackground(),
          child ?? const SizedBox.shrink(),
        ],
      ),
      home: const MainScreen(),
        );
      },
    );
  }
}

/// 桌面端：允许鼠标拖拽滚动列表（Flutter 默认只支持触屏/触控笔）
class _DesktopScrollBehavior extends MaterialScrollBehavior {
  const _DesktopScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
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
      backgroundColor: Colors.transparent, // 透出全局动态背景
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(),
          BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _currentIndex,
            onTap: (index) {
              // 切换 Tab：收起键盘（输入框失焦，避免手机端键盘一直弹出）
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _currentIndex = index);
              // 切换到播放页时刷新
              if (index == 1) _playlistKey.currentState?.refresh();
            },
            selectedItemColor: Theme.of(context).colorScheme.primary,
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
