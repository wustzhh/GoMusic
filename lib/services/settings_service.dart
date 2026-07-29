import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置服务
class SettingsService {
  static const _keyDownloadPath = 'download_path';
  static const _keyBilibiliCookie = 'bilibili_cookie';

  static SettingsService? _instance;
  late SharedPreferences _prefs;

  SettingsService._();

  static Future<SettingsService> getInstance() async {
    if (_instance == null) {
      _instance = SettingsService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// 获取默认下载路径（根据平台自动选择）
  static Future<String> getDefaultDownloadPath() async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'] ?? 'C:\\Users\\Default';
      return '$home\\GoMusic';
    } else if (Platform.isAndroid) {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/GoMusic';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/GoMusic';
    }
  }

  /// 获取下载路径（持久化，首次自动使用默认值）
  Future<String> getDownloadPath() async {
    final saved = _prefs.getString(_keyDownloadPath);
    if (saved != null && saved.isNotEmpty) return saved;

    // 首次使用默认路径并保存
    final defaultPath = await getDefaultDownloadPath();
    await setDownloadPath(defaultPath);
    return defaultPath;
  }

  /// 设置下载路径
  Future<void> setDownloadPath(String path) async {
    await _prefs.setString(_keyDownloadPath, path);
  }

  /// B站 Cookie
  Future<String> getBilibiliCookie() async {
    return _prefs.getString(_keyBilibiliCookie) ?? '';
  }

  Future<void> setBilibiliCookie(String cookie) async {
    await _prefs.setString(_keyBilibiliCookie, cookie);
  }
}
