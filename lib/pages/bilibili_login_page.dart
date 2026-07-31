import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/settings_service.dart';
import '../services/bilibili_api.dart';

/// B站自动登录页 — 通过拦截请求头捕获完整 Cookie（含 httpOnly）
class BilibiliLoginPage extends StatefulWidget {
  const BilibiliLoginPage({super.key});
  @override
  State<BilibiliLoginPage> createState() => _BilibiliLoginPageState();
}

class _BilibiliLoginPageState extends State<BilibiliLoginPage> {
  bool _loading = true;
  double _progress = 0;
  String _status = '请在页面中登录B站';
  String? _capturedCookie;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('B站登录'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _capturedCookie != null ? _saveAndClose : null,
            child: Text(_capturedCookie != null ? '保存并关闭' : '登录中...'),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri('https://passport.bilibili.com/login'),
            ),
            initialSettings: InAppWebViewSettings(
              useWideViewPort: true,
              supportZoom: false,
            ),
            onLoadStart: (_, url) {
              if (mounted) setState(() => _loading = true);
            },
            onLoadStop: (_, url) {
              if (mounted) setState(() => _loading = false);
            },
            onProgressChanged: (_, p) {
              if (mounted) setState(() => _progress = p / 100);
            },
            // 核心：拦截请求头，捕获 Cookie
            shouldInterceptRequest: (_, request) {
              _tryCaptureCookie(request.headers);
              return Future.value(null);
            },
          ),
          if (_loading)
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(value: _progress),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          _capturedCookie != null ? '已捕获登录Cookie ✅' : _status,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: _capturedCookie != null ? Colors.green : Colors.grey,
          ),
        ),
      ),
    );
  }

  void _tryCaptureCookie(Map<String, String>? headers) {
    if (_capturedCookie != null || headers == null) return;

    // 从请求头中找 Cookie
    final cookie = headers['Cookie'] ?? headers['cookie'] ?? '';
    if (cookie.contains('SESSDATA') && cookie.contains('DedeUserID')) {
      _capturedCookie = cookie;
      setState(() => _status = '已捕获登录Cookie ✅');
    }
  }

  Future<void> _saveAndClose() async {
    if (_capturedCookie == null) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final service = await SettingsService.getInstance();
    await service.setBilibiliCookie(_capturedCookie!);
    BilibiliApi.cookie = _capturedCookie;

    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('登录成功！Cookie已保存'), backgroundColor: Colors.green),
    );
    navigator.pop(true);
  }
}
