import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _downloadPath = '/storage/emulated/0/GoMusic';
  int _themeMode = 1; // 0:浅色 1:深色 2:跟随系统

  void _changeDownloadPath() {
    final controller = TextEditingController(text: _downloadPath);
    showDialog(
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              setState(() => _downloadPath = controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
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
              subtitle: Text(_downloadPath, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
