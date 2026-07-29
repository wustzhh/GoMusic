import 'package:flutter/material.dart';
import '../services/settings_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: true),
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
          // B站 Cookie
          Card(
            child: ListTile(
              leading: const Icon(Icons.cookie_outlined),
              title: const Text('B站 Cookie', style: TextStyle(fontSize: 15)),
              subtitle: const Text('配置后支持需登录的视频', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
    final service = await SettingsService.getInstance();
    if (!mounted) return;
    final current = await service.getBilibiliCookie();
    if (!mounted) return;
    final controller = TextEditingController(text: current);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('B站 Cookie'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: '从浏览器F12 → Network → 请求头中复制Cookie',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );

    if (result == true) {
      await service.setBilibiliCookie(controller.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cookie 已保存')),
        );
      }
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
