import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/settings_service.dart';
import '../services/bilibili_api.dart';

/// B站自动登录页
class BilibiliLoginPage extends StatefulWidget {
  const BilibiliLoginPage({super.key});
  @override
  State<BilibiliLoginPage> createState() => _BilibiliLoginPageState();
}

class _BilibiliLoginPageState extends State<BilibiliLoginPage> {
  bool _loading = true;
  bool _extracting = false;
  double _progress = 0;
  String _status = '请在页面中登录B站';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('B站登录'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _extracting ? null : _extractCookies,
            child: Text(_extracting ? '提取中...' : '完成登录'),
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
              // 检测登录成功跳转（延迟500ms等Cookie写入）
              if (url != null &&
                  url.toString().contains('bilibili.com') &&
                  !url.toString().contains('passport')) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted && !_extracting) _extractCookies();
                });
              }
            },
            onProgressChanged: (_, p) {
              if (mounted) setState(() => _progress = p / 100);
            },
          ),
          if (_loading)
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(value: _progress),
            ),
          if (_extracting)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(_status, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ),
    );
  }

  Future<void> _extractCookies() async {
    setState(() {
      _extracting = true;
      _status = '正在提取Cookie...';
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final cookieManager = CookieManager.instance();

      // 尝试多个域名（B站Cookie可能在 .bilibili.com 下）
      var allCookies = await cookieManager.getCookies(
        url: WebUri('https://www.bilibili.com'),
      );
      if (allCookies.isEmpty) {
        allCookies = await cookieManager.getCookies(
          url: WebUri('https://bilibili.com'),
        );
      }
      if (allCookies.isEmpty) {
        allCookies = await cookieManager.getCookies(
          url: WebUri('https://.bilibili.com'),
        );
      }

      if (allCookies.isEmpty) {
        setState(() {
          _extracting = false;
          _status = '未获取到Cookie，请确认已登录后再点"完成登录"';
        });
        return;
      }

      // 检查 SESSDATA
      final hasSessdata = allCookies.any((c) => c.name == 'SESSDATA');
      if (!hasSessdata) {
        setState(() {
          _extracting = false;
          _status = '未获取到SESSDATA(${allCookies.length}个Cookie)，请确认已登录';
        });
        return;
      }

      // 构建Cookie字符串
      final parts = <String>[];
      for (final c in allCookies) {
        parts.add('${c.name}=${c.value}');
      }
      final cookieStr = parts.join('; ');

      // 保存
      final service = await SettingsService.getInstance();
      await service.setBilibiliCookie(cookieStr);
      BilibiliApi.cookie = cookieStr;

      if (!mounted) return;
      setState(() => _status = '登录成功！${allCookies.length}个Cookie已保存');
      messenger.showSnackBar(
        SnackBar(content: Text('登录成功！获取到${allCookies.length}个Cookie(含SESSDATA)'),
            backgroundColor: Colors.green),
      );
      await Future.delayed(const Duration(milliseconds: 500));
      navigator.pop(true);
    } catch (e) {
      setState(() {
        _extracting = false;
        _status = '提取失败: $e';
      });
    }
  }
}
