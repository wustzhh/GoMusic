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
  bool _saved = false;

  @override
  Widget build(BuildContext context) {
    // 用户可能不点"保存并关闭"直接返回：捕获到 Cookie 时自动保存并返回成功
    return PopScope(
      canPop: _capturedCookie == null || _saved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_capturedCookie != null && !_saved) {
          final service = await SettingsService.getInstance();
          await service.setBilibiliCookie(_capturedCookie!);
          BilibiliApi.cookie = _capturedCookie;
          if (!mounted) return;
          setState(() => _saved = true);
          Navigator.pop(context, true);
        }
      },
      child: Scaffold(
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
              // Android 的 shouldInterceptRequest 拿不到 Cookie 头（内核管理），
              // 必须从 CookieManager 读取完整 cookie（含 httpOnly）
              _captureFromCookieManager();
            },
            onProgressChanged: (_, p) {
              if (mounted) setState(() => _progress = p / 100);
            },
            // 拦截请求头作为辅助（Windows 可用）；Android 主靠 CookieManager
            shouldInterceptRequest: (_, request) {
              _tryCaptureCookie(request.headers);
              _captureFromCookieManager();
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

  /// 从 WebView CookieManager 读取完整 cookie（含 httpOnly）。
  /// Android 的 shouldInterceptRequest 拿不到 Cookie 头，必须走这里；
  /// 登录成功后 .bilibili.com 域下会出现 SESSDATA/DedeUserID。
  Future<void> _captureFromCookieManager() async {
    if (_capturedCookie != null) return;
    try {
      final cookies = await CookieManager.instance()
          .getCookies(url: WebUri('https://www.bilibili.com'));
      if (cookies.isEmpty) return;
      final cookieStr = cookies.map((c) => '${c.name}=${c.value}').join('; ');
      if (cookieStr.contains('SESSDATA') && cookieStr.contains('DedeUserID')) {
        if (!mounted) return;
        setState(() {
          _capturedCookie = cookieStr;
          _status = '已捕获登录Cookie ✅';
        });
      }
    } catch (_) {
      // CookieManager 不可用时静默（仍可走 shouldInterceptRequest 捕获）
    }
  }

  Future<void> _saveAndClose() async {
    if (_capturedCookie == null) return;

    final service = await SettingsService.getInstance();
    await service.setBilibiliCookie(_capturedCookie!);
    BilibiliApi.cookie = _capturedCookie;

    if (!mounted) return;
    setState(() => _saved = true);
    // 提示由调用方（设置页）显示，避免重复
    Navigator.pop(context, true);
  }
}
