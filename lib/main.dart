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
  } catch (e) {
    // 媒体会话失败不影响正常使用，但记录原因（媒体会话失败会导致无通知栏/耳机键/前台服务）
    _logMs('media session init FAILED: $e');
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
    final cardBorder = ui.cardStyle == SkinCardStyle.neon || ui.neonGlow
        ? BorderSide(color: ui.buttonBorder == Colors.transparent ? skin.accent.withValues(alpha: 0.85) : ui.buttonBorder, width: 1.6)
        : ui.glassy
            ? BorderSide(color: skin.accent.withValues(alpha: 0.30), width: 1.0)
            : BorderSide.none;
    final buttonShape = switch (ui.buttonShape) {
      SkinButtonShape.capsule => const StadiumBorder(),
      SkinButtonShape.cutCorner => const BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(2))),
      SkinButtonShape.hexagon => const BeveledRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      SkinButtonShape.pixel => const BeveledRectangleBorder(borderRadius: BorderRadius.zero),
      SkinButtonShape.rounded => RoundedRectangleBorder(borderRadius: radius),
    };
    final buttonSide = ui.buttonBorder == Colors.transparent ? null : BorderSide(color: ui.buttonBorder, width: 1.2);
    final buttonShadow = ui.buttonShadow == Colors.transparent ? null : [BoxShadow(color: ui.buttonShadow.withValues(alpha: 0.45), blurRadius: ui.neonGlow ? 14 : 6, spreadRadius: 1)];
    // Flutter ThemeData 不能直接表达渐变，先确保每套主题使用独立主色；
    // 复杂渐变由 ThemeComponents/页面局部组件提供。
    final buttonBackground = ui.buttonStart;
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
        color: ui.cardStyle == SkinCardStyle.metal
            ? Color.alphaBlend(Colors.white.withValues(alpha: 0.06), cardColor)
            : cardColor,
        elevation: ui.cardStyle == SkinCardStyle.neon ? 4 : (ui.cardStyle == SkinCardStyle.metal ? 2 : 0),
        shadowColor: ui.buttonShadow == Colors.transparent ? skin.accent.withValues(alpha: 0.18) : ui.buttonShadow,
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
        type: ui.navStyle == SkinNavStyle.segmented
            ? BottomNavigationBarType.shifting
            : BottomNavigationBarType.fixed,
        backgroundColor: ui.navStyle == SkinNavStyle.rail
            ? Color.alphaBlend(skin.accent.withValues(alpha: 0.16), scheme.surface)
            : ui.navStyle == SkinNavStyle.glass || ui.navTransparent
                ? scheme.surface.withValues(alpha: 0.65)
                : scheme.surface,
        elevation: ui.navStyle == SkinNavStyle.rail ? 8 : 0,
        selectedItemColor: skin.accent,
        unselectedItemColor: scheme.onSurface.withValues(alpha: 0.6),
        selectedIconTheme: IconThemeData(size: ui.navStyle == SkinNavStyle.rail ? 28 : 24),
      ),
      // 按钮：全局圆角随主题
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(buttonShape),
          backgroundColor: WidgetStatePropertyAll(buttonBackground),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          side: WidgetStatePropertyAll(buttonSide),
          shadowColor: WidgetStatePropertyAll(ui.buttonShadow == Colors.transparent ? skin.accent : ui.buttonShadow),
          elevation: WidgetStatePropertyAll(ui.neonGlow ? 5 : 1),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 12)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(buttonShape),
          backgroundColor: WidgetStatePropertyAll(buttonBackground ?? ui.buttonStart),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          side: WidgetStatePropertyAll(buttonSide),
          shadowColor: WidgetStatePropertyAll(ui.buttonShadow == Colors.transparent ? skin.accent : ui.buttonShadow),
          elevation: WidgetStatePropertyAll(ui.neonGlow ? 5 : 2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(buttonShape),
          side: WidgetStatePropertyAll(buttonSide ?? BorderSide(color: skin.accent.withValues(alpha: 0.6))),
          foregroundColor: WidgetStatePropertyAll(skin.accent),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: ui.inputFill != Colors.transparent,
        fillColor: ui.inputFill == Colors.transparent ? null : ui.inputFill,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: skin.accent.withValues(alpha: 0.35))),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: skin.accent, width: 1.6)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface.withValues(alpha: ui.dialogOpacity),
        shape: RoundedRectangleBorder(borderRadius: radius, side: cardBorder),
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
