import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../services/audio_player_service.dart';
import '../services/settings_service.dart';
import '../ui/dynamic_background.dart';
import '../ui/skin.dart';
import '../widgets/gradient_button.dart';
import 'bilibili_login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> with SingleTickerProviderStateMixin {
  String _downloadPath = '';
  String _skinId = 'plain_dark'; // 当前皮肤 id
  bool _loaded = false;

  // 皮肤画廊预览动画（8 张缩略图共享一个 ticker，开销小）
  late final AnimationController _previewController;

  @override
  void initState() {
    super.initState();
    _previewController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 120),
    )..repeat();
    _loadSettings();
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final service = await SettingsService.getInstance();
    final path = await service.getDownloadPath();
    if (mounted) {
      setState(() {
        _downloadPath = path;
        _skinId = skinNotifier.value.id;
        _loaded = true;
      });
    }
  }

  Future<void> _setSkin(SkinStyle skin) async {
    setState(() => _skinId = skin.id);
    skinNotifier.value = skin; // 全局立即生效（动态背景/主题色）
    final service = await SettingsService.getInstance();
    await service.setSkin(skin.id); // 持久化
  }

  /// 全屏主题选择器：遮罩 + 全屏展示全部 8 套 + 竖向滚动 + 确定/取消
  Future<void> _showSkinPicker() async {
    final pickedId = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '更多主题',
      barrierColor: Colors.black54, // 背后遮罩
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (context, anim, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic))
                .animate(anim),
            child: child,
          ),
        );
      },
      pageBuilder: (context, _, __) => _SkinPickerScreen(
        initialSkinId: _skinId,
        animation: _previewController,
      ),
    );
    if (pickedId != null && pickedId != _skinId) {
      await _setSkin(Skins.byId(pickedId));
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
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板'), duration: Duration(seconds: 2)));
            },
            child: const Text('复制'),
          ),
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
      backgroundColor: Colors.transparent, // 透出全局动态背景
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
          // 音量（仅 Windows：应用内独立音量，不影响系统音量）
          if (Platform.isWindows) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.volume_up_outlined, size: 20),
                        const SizedBox(width: 8),
                        const Text('音量', style: TextStyle(fontSize: 15)),
                        const Spacer(),
                        ValueListenableBuilder<double>(
                          valueListenable: AudioPlayerService().volumeNotifier,
                          builder: (_, v, __) => Text(
                            '${v.round()}%',
                            style: const TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder<double>(
                      valueListenable: AudioPlayerService().volumeNotifier,
                      builder: (_, v, __) => Slider(
                        value: v,
                        min: 5,
                        max: 100,
                        divisions: 19,
                        label: '${v.round()}%',
                        onChanged: (nv) => AudioPlayerService().setVolume(nv),
                      ),
                    ),
                    const Text(
                      '快捷键：Ctrl+Alt+↑/↓ 音量±5%，Ctrl+Alt+←/→ 切歌（后台也生效）',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
// 界面皮肤：默认显示 3 套预览 + "更多主题"全屏选择
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('界面皮肤', style: TextStyle(fontSize: 15)),
                    const Spacer(),
                    // 右上角：更多主题入口
                    InkWell(
                      onTap: _showSkinPicker,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text('更多主题', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary)),
                          const Icon(Icons.chevron_right, size: 16),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // 前 3 套预览（点击直接切换）
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                    children: [
                      for (final skin in Skins.all.take(3))
                        _SkinCard(
                          skin: skin,
                          selected: skin.id == _skinId,
                          animation: _previewController,
                          onTap: () => _setSkin(skin),
                        ),
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

/// 全屏主题选择页：遮罩路由 + 全屏展示全部皮肤（竖向滚动）+ 底部确定/取消
class _SkinPickerScreen extends StatefulWidget {
  final String initialSkinId;
  final Animation<double> animation;
  const _SkinPickerScreen({required this.initialSkinId, required this.animation});
  @override
  State<_SkinPickerScreen> createState() => _SkinPickerScreenState();
}

class _SkinPickerScreenState extends State<_SkinPickerScreen> {
  late String _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSkinId;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(children: [
          // 标题行 + 关闭
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(children: [
              const Text('选择主题', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Text(
                Skins.byId(_selectedId).name,
                style: TextStyle(fontSize: 13, color: scheme.primary),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
              ),
            ]),
          ),
          const Divider(height: 1),
          // 全部皮肤：竖向滚动网格（3 列）
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.62,
              ),
              itemCount: Skins.all.length,
              itemBuilder: (_, i) {
                final skin = Skins.all[i];
                return _SkinCard(
                  skin: skin,
                  selected: skin.id == _selectedId,
                  animation: widget.animation,
                  onTap: () => setState(() => _selectedId = skin.id),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // 底部：取消 / 确定
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GradientButton(
                  colors: skinNotifier.value.buttonGradient,
                  radius: 12,
                  height: 48,
                  onPressed: () => Navigator.pop(context, _selectedId),
                  child: const Text('确定', style: TextStyle(fontSize: 15)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SkinCard extends StatelessWidget {
  final SkinStyle skin;
  final bool selected;
  final Animation<double> animation;
  final VoidCallback onTap;

  const _SkinCard({required this.skin, required this.selected, required this.animation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // 迷你预览（动态皮肤实时动画，素皮肤纯色），自适应网格单元大小
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? accent : Colors.grey.withValues(alpha: 0.25),
                  width: selected ? 2.5 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                SkinPreview(skin: skin, animation: animation),
                if (selected)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            skin.name,
            style: TextStyle(
              fontSize: 13,
              color: selected ? accent : Colors.grey,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
