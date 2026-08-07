import 'dart:io';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import 'bilibili_login_page.dart';
import '../widgets/top_toast.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _downloadPath = '';
  int _themeMode = 1; // 0:浅色 1:深色 2:跟随系统
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final service = await SettingsService.getInstance();
    final path = await service.getDownloadPath();
    if (mounted) {
      setState(() {
        _downloadPath = path;
        _loaded = true;
      });
    }
  }

  Future<void> _changeDownloadPath() async {
    final controller = TextEditingController(text: _downloadPath);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改下载路径'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入新的下载路径',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );

    if (result == true) {
      final newPath = controller.text.trim();
      if (newPath.isNotEmpty) {
        final service = await SettingsService.getInstance();
        await service.setDownloadPath(newPath);
        setState(() => _downloadPath = newPath);
      }
    }
  }

  void _showDebugLog() {
    String content = '';
    try {
      final tmp = Directory.systemTemp;
      final f = File('${tmp.path}${Platform.pathSeparator}gomusic_debug.log');
      content = f.existsSync() ? f.readAsStringSync() : '(暂无日志文件)';
    } catch (e) {
      content = '读取失败: $e';
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('调试日志', style: TextStyle(fontSize: 15)),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: SelectableText(content, style: const TextStyle(fontSize: 11)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          TextButton(onPressed: () {
            Navigator.pop(ctx);
            try {
              final tmp = Directory.systemTemp;
              File('${tmp.path}${Platform.pathSeparator}gomusic_debug.log').writeAsStringSync('');
            } catch (_) {}
          }, child: const Text('清空')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.bug_report_outlined, size: 20), tooltip: '', onPressed: _showDebugLog),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 下载路径
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('下载路径', style: TextStyle(fontSize: 15)),
              subtitle: Text(
                _loaded ? _downloadPath : '加载中...',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changeDownloadPath,
            ),
          ),
          const SizedBox(height: 8),
          // 主题
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('主题', style: TextStyle(fontSize: 15)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _ThemeOption(label: '浅色', selected: _themeMode == 0, onTap: () => setState(() => _themeMode = 0)),
                      const SizedBox(width: 12),
                      _ThemeOption(label: '深色', selected: _themeMode == 1, onTap: () => setState(() => _themeMode = 1)),
                      const SizedBox(width: 12),
                      _ThemeOption(label: '跟随系统', selected: _themeMode == 2, onTap: () => setState(() => _themeMode = 2)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // B站登录
          Card(
            child: ListTile(
              leading: const Icon(Icons.login_outlined),
              title: const Text('B站登录', style: TextStyle(fontSize: 15)),
              subtitle: const Text('登录后可解析需会员的视频（自动获取Cookie）', style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _changeCookie,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // 关于
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('关于 GoMusic', style: TextStyle(fontSize: 15)),
              subtitle: Text('版本 1.0.0', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeCookie() async {
    // 所有平台统一使用 WebView 自动登录
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const BilibiliLoginPage()),
    );
    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('B站登录信息已保存')),
      );
    }
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18,
            color: selected ? Colors.deepPurple : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 13, color: selected ? Colors.deepPurple : Colors.grey)),
        ],
      ),
    );
  }
}
