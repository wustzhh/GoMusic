import 'package:flutter/material.dart';
import 'pages/download_page.dart';
import 'pages/playlist_page.dart';
import 'pages/settings_page.dart';
import 'services/settings_service.dart';
import 'services/bilibili_api.dart';
import 'services/audio_player_service.dart';
import 'widgets/mini_player_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = await SettingsService.getInstance();
  BilibiliApi.cookie = await service.getBilibiliCookie();

  // 恢复上次播放状态
  final audioService = AudioPlayerService();
  await audioService.restoreLastSong();

  runApp(const GoMusicApp());
}

class GoMusicApp extends StatelessWidget {
  const GoMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoMusic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.light), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: Brightness.dark), useMaterial3: true),
      themeMode: ThemeMode.dark,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final _playlistKey = GlobalKey<PlaylistPageState>();

  late final List<Widget> _pages = [
    const DownloadPage(),
    PlaylistPage(key: _playlistKey),
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
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() => _currentIndex = index);
              // 切换到播放页时刷新
              if (index == 1) _playlistKey.currentState?.refresh();
            },
            selectedItemColor: Colors.deepPurple,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.download), label: '下载'),
              BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline), label: '播放'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '设置'),
            ],
          ),
        ],
      ),
    );
  }
}
