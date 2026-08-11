import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'audio_player_service.dart';

/// Windows 全局快捷键（应用在后台也生效）：
///   Ctrl+Alt+Q              →  播放 / 暂停切换
///   Ctrl+Alt+← / Ctrl+Alt+→  →  上一曲 / 下一曲
///   Ctrl+Alt+↑ / Ctrl+Alt+↓  →  音量 +5% / -5%（钳位 5~100）
/// 仅 Windows 注册；Android 不注册（无全局热键需求）。
class HotkeyService {
  static final HotkeyService instance = HotkeyService._();
  HotkeyService._();

  bool _registered = false;

  Future<void> init() async {
    if (!Platform.isWindows || _registered) return;
    _registered = true; // 先置位，避免并发重复注册
    try {
      await hotKeyManager.unregisterAll();
      const mods = [HotKeyModifier.control, HotKeyModifier.alt];
      await _register(
        HotKey(key: PhysicalKeyboardKey.keyQ, modifiers: mods),
        () => AudioPlayerService().togglePause(),
      );
      await _register(
        HotKey(key: PhysicalKeyboardKey.arrowRight, modifiers: mods),
        () => unawaited(AudioPlayerService().next()),
      );
      await _register(
        HotKey(key: PhysicalKeyboardKey.arrowLeft, modifiers: mods),
        () => unawaited(AudioPlayerService().prev()),
      );
      await _register(
        HotKey(key: PhysicalKeyboardKey.arrowUp, modifiers: mods),
        () => unawaited(AudioPlayerService().changeVolume(5)),
      );
      await _register(
        HotKey(key: PhysicalKeyboardKey.arrowDown, modifiers: mods),
        () => unawaited(AudioPlayerService().changeVolume(-5)),
      );
    } catch (_) {
      // 注册失败（热键被占用等）静默降级：功能不可用但不影响应用
      _registered = false;
    }
  }

  Future<void> _register(HotKey hotKey, void Function() action) async {
    await hotKeyManager.register(hotKey, keyDownHandler: (_) => action());
  }

  Future<void> dispose() async {
    if (!_registered) return;
    _registered = false;
    try {
      await hotKeyManager.unregisterAll();
    } catch (_) {}
  }
}
