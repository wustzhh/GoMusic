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

  /// 获取默认下载路径（exe所在目录下的 downloads 文件夹）
  static Future<String> getDefaultDownloadPath() async {
    if (Platform.isWindows) {
      // exe 所在目录，如 D:\pyProj\GoMusic\build\windows\x64\runner\Release\
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      return '$exeDir\\downloads';
    } else {
      // Android/其他：应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/downloads';
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
