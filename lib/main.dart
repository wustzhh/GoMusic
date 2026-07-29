import 'package:flutter/material.dart';
import 'pages/download_page.dart';
import 'pages/playlist_page.dart';
import 'pages/settings_page.dart';

void main() {
  runApp(const GoMusicApp());
}

class GoMusicApp extends StatelessWidget {
  const GoMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GoMusic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark, // 默认深色
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
  int _currentIndex = 0; // 默认下载页（最左）

  // 每个Tab独立维护导航栈
  final List<Widget> _pages = const [
    DownloadPage(),
    PlaylistPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            selectedItemColor: Colors.deepPurple,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.download), label: '下载'),
              BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline), label: '播放'),
              BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '设置'),
            ],
          ),
    );
  }
}
