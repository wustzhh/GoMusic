import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/settings_service.dart';

/// B站自动登录页（WebView 内嵌登录，自动提取 Cookie）
class BilibiliLoginPage extends StatefulWidget {
  const BilibiliLoginPage({super.key});

  @override
  State<BilibiliLoginPage> createState() => _BilibiliLoginPageState();
}

class _BilibiliLoginPageState extends State<BilibiliLoginPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _extractingCookie = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
            // 登录成功后自动提取 Cookie
            _tryExtractCookie();
          },
          onUrlChange: (change) {
            // 登录成功后通常会跳转到 bilibili.com 首页
            if (change.url?.contains('bilibili.com') == true &&
                !change.url!.contains('passport')) {
              _tryExtractCookie();
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://passport.bilibili.com/login'));
  }

  Future<void> _tryExtractCookie() async {
    if (_extractingCookie) return;
    _extractingCookie = true;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final cookies = await _runJs("document.cookie");
      if (cookies is String && cookies.isNotEmpty) {
        final biliCookies = _filterBiliCookies(cookies);
        if (biliCookies.isNotEmpty) {
          final service = await SettingsService.getInstance();
          await service.setBilibiliCookie(biliCookies);

          if (!mounted) { _extractingCookie = false; return; }
          messenger.showSnackBar(
            const SnackBar(content: Text('已自动获取B站登录信息'), backgroundColor: Colors.green),
          );
          navigator.pop(true);
          _extractingCookie = false;
          return;
        }
      }
    } catch (_) {}

    _extractingCookie = false;
  }

  String _filterBiliCookies(String allCookies) {
    // 只保留 B站相关的关键 Cookie
    final parts = allCookies.split(';');
    final keepKeys = [
      'DedeUserID', 'DedeUserID__ckMd5', 'SESSDATA', 'bili_jct',
      'buvid3', 'buvid4', 'b_nut', '_uuid',
    ];
    final result = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      for (final key in keepKeys) {
        if (trimmed.startsWith('$key=')) {
          result.add(trimmed);
          break;
        }
      }
    }
    return result.join('; ');
  }

  Future<Object?> _runJs(String js) async {
    try {
      return await _controller.runJavaScriptReturningResult(js);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('B站登录'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              final cookies = await _runJs("document.cookie");
              if (cookies is String && cookies.isNotEmpty) {
                final bili = _filterBiliCookies(cookies);
                if (bili.isNotEmpty) {
                  final service = await SettingsService.getInstance();
                  await service.setBilibiliCookie(bili);
                  if (!mounted) return;
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Cookie 已保存')),
                  );
                  navigator.pop(true);
                }
              }
            },
            child: const Text('手动提取'),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
