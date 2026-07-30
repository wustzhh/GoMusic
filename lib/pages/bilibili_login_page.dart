import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/settings_service.dart';

/// B站登录页
/// - Android：内嵌 WebView，登录后自动提取 Cookie
/// - Windows：引导用户在浏览器中登录，手动粘贴 Cookie
class BilibiliLoginPage extends StatefulWidget {
  const BilibiliLoginPage({super.key});

  @override
  State<BilibiliLoginPage> createState() => _BilibiliLoginPageState();
}

class _BilibiliLoginPageState extends State<BilibiliLoginPage> {
  // Android WebView
  late final WebViewController _webController;
  bool _webLoading = true;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _initWebView();
    } else {
      // Windows：直接弹对话框
      WidgetsBinding.instance.addPostFrameCallback((_) => _showCookieDialog());
    }
  }

  void _initWebView() {
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _webLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _webLoading = false);
            _tryAutoExtract();
          },
          onUrlChange: (change) {
            if (change.url?.contains('bilibili.com') == true &&
                !change.url!.contains('passport')) {
              _tryAutoExtract();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://passport.bilibili.com/login'));
  }

  Future<void> _tryAutoExtract() async {
    try {
      final result = await _webController.runJavaScriptReturningResult("document.cookie");
      final cookies = (result as String?) ?? '';
      if (cookies.isNotEmpty) {
        final filtered = _filterCookies(cookies);
        if (filtered.isNotEmpty) {
          await _saveCookie(filtered);
        }
      }
    } catch (_) {}
  }

  String _filterCookies(String raw) {
    final keep = ['DedeUserID', 'DedeUserID__ckMd5', 'SESSDATA', 'bili_jct', 'buvid3', 'buvid4', 'b_nut', '_uuid'];
    final parts = raw.split(';');
    final result = <String>[];
    for (final p in parts) {
      final t = p.trim();
      for (final k in keep) {
        if (t.startsWith('$k=')) { result.add(t); break; }
      }
    }
    return result.join('; ');
  }

  Future<void> _saveCookie(String cookie) async {
    final service = await SettingsService.getInstance();
    await service.setBilibiliCookie(cookie);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('登录成功！'), backgroundColor: Colors.green),
    );
    Navigator.pop(context, true);
  }

  // ==================== Windows：浏览器 + 手动粘贴 ====================

  void _showCookieDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CookieInputDialog(
        onSaved: () {
          Navigator.pop(ctx);
          if (mounted) Navigator.pop(context, true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(title: const Text('B站登录'), centerTitle: true),
        body: Stack(
          children: [
            WebViewWidget(controller: _webController),
            if (_webLoading) const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    }

    // Windows：空白页（对话框在 initState 弹出）
    return Scaffold(
      appBar: AppBar(title: const Text('B站登录'), centerTitle: true),
      body: const Center(child: Text('请在弹窗中操作')),
    );
  }
}

/// Windows 端 Cookie 输入对话框
class _CookieInputDialog extends StatefulWidget {
  final VoidCallback onSaved;
  const _CookieInputDialog({required this.onSaved});

  @override
  State<_CookieInputDialog> createState() => _CookieInputDialogState();
}

class _CookieInputDialogState extends State<_CookieInputDialog> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openBrowser() async {
    final uri = Uri.parse('https://passport.bilibili.com/login');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _save() async {
    final cookie = _controller.text.trim();
    if (cookie.isEmpty) return;

    setState(() => _saving = true);
    final service = await SettingsService.getInstance();
    await service.setBilibiliCookie(cookie);
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('B站登录'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('步骤1：点击下方按钮在浏览器中打开B站并登录',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openBrowser,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('打开浏览器登录'),
              ),
            ),
            const SizedBox(height: 16),
            const Text('步骤2：登录后，按 F12 → Application → Cookies',
                style: TextStyle(fontSize: 13)),
            const Text('复制以下关键字段，格式为 字段名=值（分号分隔）',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'DedeUserID=xxx; SESSDATA=xxx; bili_jct=xxx; buvid3=xxx',
                style: TextStyle(fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: '粘贴 Cookie...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }
}
