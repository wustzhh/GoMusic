import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../services/settings_service.dart';
import '../services/bilibili_api.dart';

/// B站自动登录页
/// - Windows: webview_windows (Edge WebView2)
/// - Android: webview_flutter (系统WebView)
class BilibiliLoginPage extends StatefulWidget {
  const BilibiliLoginPage({super.key});
  @override
  State<BilibiliLoginPage> createState() => _BilibiliLoginPageState();
}

class _BilibiliLoginPageState extends State<BilibiliLoginPage> {
  bool _loading = true;
  bool _extracted = false;

  WebViewController? _androidCtrl;
  WebviewController? _wndCtrl;
  StreamSubscription? _wndUrlSub;
  StreamSubscription? _wndLoadingSub;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      _initWindows();
    } else {
      _initAndroid();
    }
  }

  @override
  void dispose() {
    _wndUrlSub?.cancel();
    _wndLoadingSub?.cancel();
    _wndCtrl?.dispose();
    super.dispose();
  }

  // ==================== Android ====================

  void _initAndroid() {
    _androidCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => _setLoading(true),
        onPageFinished: (_) {
          _setLoading(false);
          _tryAndroid();
        },
        onUrlChange: (change) {
          if ((change.url ?? '').contains('bilibili.com') &&
              !(change.url ?? '').contains('passport')) {
            _tryAndroid();
          }
        },
      ))
      ..loadRequest(Uri.parse('https://passport.bilibili.com/login'));
  }

  Future<void> _tryAndroid() async {
    if (_extracted || _androidCtrl == null) return;
    _extracted = true;
    try {
      final raw = await _androidCtrl!.runJavaScriptReturningResult('document.cookie');
      await _saveCookie((raw as String?) ?? '');
    } catch (_) {
      _extracted = false;
    }
  }

  // ==================== Windows ====================

  void _initWindows() async {
    try {
      final ctrl = WebviewController();
      await ctrl.initialize();
      ctrl.loadUrl('https://passport.bilibili.com/login');

      // 监听 URL
      _wndUrlSub = ctrl.url.listen((url) {
        if (url.contains('bilibili.com') && !url.contains('passport')) {
          _tryWindows();
        }
      });

      // 监听加载状态
      _wndLoadingSub = ctrl.loadingState.listen((state) {
        if (state == LoadingState.loading) {
          _setLoading(true);
        } else {
          _setLoading(false);
          _tryWindows();
        }
      });

      setState(() => _wndCtrl = ctrl);
    } catch (_) {}
  }

  Future<void> _tryWindows() async {
    if (_extracted || _wndCtrl == null) return;
    _extracted = true;
    try {
      final raw = await _wndCtrl!.executeScript('document.cookie');
      await _saveCookie(raw?.toString() ?? '');
    } catch (_) {
      _extracted = false;
    }
  }

  // ==================== 通用 ====================

  void _setLoading(bool v) {
    if (mounted) setState(() => _loading = v);
  }

  String _filterCookies(String raw) {
    final keep = [
      'DedeUserID', 'DedeUserID__ckMd5', 'SESSDATA', 'bili_jct',
      'buvid3', 'buvid4', 'b_nut', '_uuid',
    ];
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

  Future<void> _saveCookie(String raw) async {
    final filtered = _filterCookies(raw);
    if (filtered.isEmpty) {
      _extracted = false;
      return;
    }
    final service = await SettingsService.getInstance();
    await service.setBilibiliCookie(filtered);
    BilibiliApi.cookie = filtered; // 同步到 API 实例
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('登录成功！'), backgroundColor: Colors.green),
    );
    Navigator.pop(context, true);
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('B站登录'), centerTitle: true),
      body: Stack(
        children: [
          if (Platform.isAndroid && _androidCtrl != null)
            WebViewWidget(controller: _androidCtrl!),
          if (Platform.isWindows && _wndCtrl != null)
            Webview(_wndCtrl!),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
