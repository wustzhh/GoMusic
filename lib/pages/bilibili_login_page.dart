import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/settings_service.dart';
import '../services/bilibili_api.dart';

/// B站自动登录页 — 全平台 InAppWebView + CookieManager 获取全部 Cookie
class BilibiliLoginPage extends StatefulWidget {
  const BilibiliLoginPage({super.key});
  @override
  State<BilibiliLoginPage> createState() => _BilibiliLoginPageState();
}

class _BilibiliLoginPageState extends State<BilibiliLoginPage> {
  InAppWebViewController? _ctrl;
  bool _loading = true;
  bool _extracted = false;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('B站登录'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _extractCookies,
            child: const Text('完成登录'),
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
            onWebViewCreated: (c) => _ctrl = c,
            onLoadStart: (_, url) {
              if (mounted) setState(() => _loading = true);
            },
            onLoadStop: (_, url) {
              if (mounted) setState(() => _loading = false);
              // 登录成功后自动提取
              if (url != null &&
                  url.toString().contains('bilibili.com') &&
                  !url.toString().contains('passport')) {
                _extractCookies();
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
        ],
      ),
    );
  }

  Future<void> _extractCookies() async {
    if (_extracted) return;
    _extracted = true;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final cookieManager = CookieManager.instance();
      final allCookies = await cookieManager.getCookies(
        url: WebUri('https://bilibili.com'),
      );

      if (allCookies.isEmpty) {
        _extracted = false;
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('未检测到登录状态，请先登录')),
          );
        }
        return;
      }

      // 取所有 B站域名的 Cookie（不过滤，因为需要 httpOnly 的）
      final parts = <String>[];
      for (final c in allCookies) {
        parts.add('${c.name}=${c.value}');
      }
      final cookieStr = parts.join('; ');

      // 验证是否有关键的 SESSDATA
      final hasSessdata = allCookies.any((c) => c.name == 'SESSDATA');
      if (!hasSessdata) {
        _extracted = false;
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('未获取到登录凭证(SESSDATA)，请在浏览器中完成登录')),
          );
        }
        return;
      }

      // 保存
      final service = await SettingsService.getInstance();
      await service.setBilibiliCookie(cookieStr);
      BilibiliApi.cookie = cookieStr;

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('登录成功！已获取全部Cookie'), backgroundColor: Colors.green),
      );
      navigator.pop(true);
    } catch (e) {
      _extracted = false;
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('提取失败: $e')),
        );
      }
    }
  }
}
