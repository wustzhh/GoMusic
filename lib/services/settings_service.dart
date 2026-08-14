import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置服务
class SettingsService {
  static const _keyDownloadPath = 'download_path';
  static const _keyBilibiliCookie = 'bilibili_cookie';
  static const _keyThemeMode = 'theme_mode'; // 0:浅色 1:深色 2:跟随系统
  static const _keySkin = 'ui_skin'; // 皮肤 id（Skins.byId 查询，默认素·深色）

  static Future<SettingsService>? _instanceFuture;
  late SharedPreferences _prefs;

  SettingsService._();

  static Future<SettingsService> getInstance() {
    // 用 Future 缓存避免并发竞态：多个调用同时进入时只初始化一次，
    // 其余调用等待同一个 Future 完成后再取实例。
    return _instanceFuture ??= _initInstance();
  }

  static Future<SettingsService> _initInstance() async {
    final s = SettingsService._();
    s._prefs = await SharedPreferences.getInstance();
    return s;
  }

  /// 获取默认下载路径（exe所在目录下的 downloads 文件夹）
  static Future<String> getDefaultDownloadPath() async {
    if (Platform.isWindows) {
      // 项目根目录/downloads（不在build里，避免flutter clean误删）
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      // exeDir = .../build/windows/x64/runner/Release → 往上5级到项目根
      final projRoot = File(exeDir).parent.parent.parent.parent.parent.path;
      return '$projRoot\\downloads';
    } else {
      // Android: 公共 Download 目录（用户文件管理器可见，需"所有文件访问"权限）
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) {
          final d = '${ext.path}/Download/GoMusic';
          Directory(d).createSync(recursive: true);
          return d;
        }
      } catch (_) {}
      final dir = await getApplicationDocumentsDirectory();
      return '${dir.path}/downloads';
    }
  }

  /// 获取下载路径（持久化，首次自动使用默认值）
  Future<String> getDownloadPath() async {
    final saved = _prefs.getString(_keyDownloadPath);
    if (saved != null && saved.isNotEmpty) {
      // 旧路径在build里(已被flutter clean删)，自动迁移到新路径
      if (saved.contains('\\build\\')) {
        final newPath = await getDefaultDownloadPath();
        await setDownloadPath(newPath);
        return newPath;
      }
      return saved;
    }

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

  /// 读取主题模式（0:浅色 1:深色 2:跟随系统，默认深色=1）
  int getThemeMode() {
    return _prefs.getInt(_keyThemeMode) ?? 1;
  }

  /// 保存主题模式
  Future<void> setThemeMode(int mode) async {
    await _prefs.setInt(_keyThemeMode, mode);
  }

  /// 读取界面皮肤 id（默认极光：启动即有动态背景）
  String getSkin() {
    return _prefs.getString(_keySkin) ?? 'aurora';
  }

  /// 保存界面皮肤
  Future<void> setSkin(String skinId) async {
    await _prefs.setString(_keySkin, skinId);
  }
}
