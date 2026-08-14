import 'package:flutter/material.dart';

/// 粒子特效类型
enum SkinParticle { none, star, meteor, ember, spark }

/// 一套主题的完整 UI 风格参数（不只是背景：卡片/按钮/导航/形状全部跟随）
class UiStyle {
  final double radius; // 全局圆角基数（小=锐利，大=圆润）
  final bool glassy; // 卡片玻璃拟态（半透明+边框）
  final double glassOpacity; // 玻璃卡片不透明度
  final bool neonGlow; // 霓虹发光边框（强调色描边发光）
  final bool gradientButtons; // 主要按钮使用渐变
  final bool appBarTransparent; // AppBar 透明融入背景
  final bool navTransparent; // 底部导航玻璃化
  const UiStyle({
    this.radius = 12,
    this.glassy = false,
    this.glassOpacity = 0.55,
    this.neonGlow = false,
    this.gradientButtons = false,
    this.appBarTransparent = false,
    this.navTransparent = false,
  });
}

/// 一团漂移光晕：颜色、位置（相对坐标 0~1）、半径（相对短边）、漂移参数
class GlowOrb {
  final Color color;
  final double cx; // 中心 x（0~1）
  final double cy; // 中心 y（0~1）
  final double radius; // 半径（相对屏幕短边的比例）
  final double ampX; // 水平漂移振幅（相对短边）
  final double ampY; // 垂直漂移振幅（相对短边）
  final double period; // 漂移周期（秒）
  final double phase; // 相位
  const GlowOrb({
    required this.color,
    required this.cx,
    required this.cy,
    required this.radius,
    this.ampX = 0.04,
    this.ampY = 0.06,
    this.period = 24,
    this.phase = 0,
  });
}

/// 一套界面皮肤：背景基调 + 光晕 + 粒子 + 强调色 + 明暗 + 完整 UI 风格
class SkinStyle {
  final String id;
  final String name;
  final Color background;
  final List<GlowOrb> orbs;
  final SkinParticle particles;
  final Color accent;
  final bool animated; // 素皮肤无动画
  final bool dark; // 决定 MaterialApp 的 themeMode
  final UiStyle ui; // 完整 UI 风格（卡片/按钮/导航/形状）
  const SkinStyle({
    required this.id,
    required this.name,
    required this.background,
    required this.orbs,
    required this.particles,
    required this.accent,
    required this.animated,
    required this.dark,
    this.ui = const UiStyle(),
  });

  /// 主要按钮的渐变配色（随主题）
  List<Color> get buttonGradient {
    switch (id) {
      case 'aurora':
        return const [Color(0xFF7C4DFF), Color(0xFF00BFA5)];
      case 'cyber_neon':
        return const [Color(0xFF00F0FF), Color(0xFFFF2E9A)];
      case 'rainbow':
        return const [Color(0xFFFF5252), Color(0xFFFFA726), Color(0xFF29B6F6)];
      case 'galaxy':
        return const [Color(0xFF4C3FFF), Color(0xFF00CFFF)];
      case 'flame':
        return const [Color(0xFFFF7A00), Color(0xFFFF2E2E)];
      case 'electric':
        return const [Color(0xFF00E0FF), Color(0xFF169BFF)];
      default:
        return [accent, accent];
    }
  }
}

/// 内置皮肤全集
class Skins {
  // 0/1：原始素皮肤（无动画，保留原 deepPurple 主题）
  static final plainLight = SkinStyle(
    id: 'plain_light',
    name: '素·浅色',
    background: const Color(0xFFF7F2FA),
    orbs: const [],
    particles: SkinParticle.none,
    accent: Colors.deepPurple,
    animated: false,
    dark: false,
    ui: UiStyle(radius: 8, glassy: false),
  );
  static final plainDark = SkinStyle(
    id: 'plain_dark',
    name: '素·深色',
    background: const Color(0xFF1A1520),
    orbs: const [],
    particles: SkinParticle.none,
    accent: Colors.deepPurple,
    animated: false,
    dark: true,
    ui: UiStyle(radius: 8, glassy: false),
  );

  // 2：极光——深紫底，紫+青绿两团大光晕慢漂移，星点闪烁
  static final aurora = SkinStyle(
    id: 'aurora',
    name: '极光',
    background: const Color(0xFF0E0B20),
    orbs: const [
      GlowOrb(color: Color(0xE07C4DFF), cx: 0.22, cy: 0.30, radius: 0.85, ampX: 0.08, ampY: 0.10, period: 26, phase: 0),
      GlowOrb(color: Color(0xC000E5A0), cx: 0.80, cy: 0.72, radius: 0.75, ampX: 0.10, ampY: 0.08, period: 22, phase: 2.4),
      GlowOrb(color: Color(0x854A6CF7), cx: 0.60, cy: 0.18, radius: 0.55, ampX: 0.06, ampY: 0.05, period: 30, phase: 4.8),
    ],
    particles: SkinParticle.star,
    accent: const Color(0xFF9C7CFF),
    ui: UiStyle(radius: 16, glassy: true, glassOpacity: 0.55, gradientButtons: true, appBarTransparent: true, navTransparent: true),
    animated: true,
    dark: true,
  );

  // 3：赛博霓虹——蓝黑底，青+粉对角光晕交错，速度最快
  static final cyberNeon = SkinStyle(
    id: 'cyber_neon',
    name: '赛博霓虹',
    background: const Color(0xFF05060F),
    orbs: const [
      GlowOrb(color: Color(0xC000F0FF), cx: 0.20, cy: 0.25, radius: 0.70, ampX: 0.14, ampY: 0.12, period: 12, phase: 0),
      GlowOrb(color: Color(0xC0FF2E9A), cx: 0.82, cy: 0.78, radius: 0.70, ampX: 0.12, ampY: 0.14, period: 14, phase: 1.7),
      GlowOrb(color: Color(0x705B8CFF), cx: 0.72, cy: 0.15, radius: 0.60, ampX: 0.10, ampY: 0.08, period: 10, phase: 3.2),
    ],
    particles: SkinParticle.spark,
    accent: const Color(0xFF00F0FF),
    ui: UiStyle(radius: 6, glassy: true, glassOpacity: 0.5, neonGlow: true, gradientButtons: true, appBarTransparent: true, navTransparent: true),
    animated: true,
    dark: true,
  );

  // 4：幻彩彩虹——近黑底，6 色光晕环形排布缓慢旋转
  static final rainbow = SkinStyle(
    id: 'rainbow',
    name: '幻彩彩虹',
    background: const Color(0xFF0A0A12),
    orbs: const [
      GlowOrb(color: Color(0x8CFF5252), cx: 0.25, cy: 0.30, radius: 0.55, ampX: 0.13, ampY: 0.09, period: 18, phase: 0),
      GlowOrb(color: Color(0x8CFFA726), cx: 0.75, cy: 0.30, radius: 0.55, ampX: 0.09, ampY: 0.13, period: 20, phase: 1.05),
      GlowOrb(color: Color(0x8CFFEE58), cx: 0.85, cy: 0.65, radius: 0.55, ampX: 0.11, ampY: 0.10, period: 19, phase: 2.1),
      GlowOrb(color: Color(0x8C66BB6A), cx: 0.50, cy: 0.85, radius: 0.55, ampX: 0.12, ampY: 0.08, period: 21, phase: 3.15),
      GlowOrb(color: Color(0x8C29B6F6), cx: 0.15, cy: 0.70, radius: 0.55, ampX: 0.08, ampY: 0.12, period: 17, phase: 4.2),
      GlowOrb(color: Color(0x8CAB47BC), cx: 0.45, cy: 0.15, radius: 0.55, ampX: 0.10, ampY: 0.09, period: 23, phase: 5.25),
    ],
    particles: SkinParticle.star,
    accent: const Color(0xFFFF6EC7),
    ui: UiStyle(radius: 14, glassy: true, glassOpacity: 0.55, gradientButtons: true, appBarTransparent: true, navTransparent: true),
    animated: true,
    dark: true,
  );

  // 5：星河——深空底，紫蓝星云慢漂 + 流星
  static final galaxy = SkinStyle(
    id: 'galaxy',
    name: '星河',
    background: const Color(0xFF050510),
    orbs: const [
      GlowOrb(color: Color(0x854C3FFF), cx: 0.30, cy: 0.35, radius: 0.80, ampX: 0.06, ampY: 0.07, period: 28, phase: 0),
      GlowOrb(color: Color(0x702F6BFF), cx: 0.75, cy: 0.65, radius: 0.70, ampX: 0.07, ampY: 0.06, period: 32, phase: 3.0),
      GlowOrb(color: Color(0x4D00CFFF), cx: 0.55, cy: 0.20, radius: 0.50, ampX: 0.05, ampY: 0.04, period: 25, phase: 5.5),
    ],
    particles: SkinParticle.meteor,
    accent: const Color(0xFF8C9EFF),
    ui: UiStyle(radius: 20, glassy: true, glassOpacity: 0.5, gradientButtons: true, appBarTransparent: true, navTransparent: true),
    animated: true,
    dark: true,
  );

  // 6：烈焰——暗红黑底，橙红上涌光晕 + 上升火星
  // 注意：光晕中心必须保持在画布内（shader 中心出画布会导致部分渲染路径不绘制）
  static final flame = SkinStyle(
    id: 'flame',
    name: '烈焰',
    background: const Color(0xFF120607),
    orbs: const [
      GlowOrb(color: Color(0xD0FF7A00), cx: 0.50, cy: 0.82, radius: 1.25, ampX: 0.06, ampY: 0.10, period: 15, phase: 0),
      GlowOrb(color: Color(0xB8FF2E2E), cx: 0.32, cy: 0.72, radius: 0.85, ampX: 0.08, ampY: 0.09, period: 17, phase: 2.3),
      GlowOrb(color: Color(0x7AFFC400), cx: 0.70, cy: 0.80, radius: 0.70, ampX: 0.07, ampY: 0.08, period: 13, phase: 4.1),
    ],
    particles: SkinParticle.ember,
    accent: const Color(0xFFFF6D2E),
    ui: UiStyle(radius: 12, glassy: true, glassOpacity: 0.6, gradientButtons: true, appBarTransparent: true, navTransparent: true),
    animated: true,
    dark: true,
  );

  // 7：电光——深蓝底，青色脉冲光晕（呼吸明暗）+ 闪电
  static final electric = SkinStyle(
    id: 'electric',
    name: '电光',
    background: const Color(0xFF040A18),
    orbs: const [
      GlowOrb(color: Color(0x8500E0FF), cx: 0.30, cy: 0.40, radius: 0.80, ampX: 0.07, ampY: 0.08, period: 20, phase: 0),
      GlowOrb(color: Color(0x60169BFF), cx: 0.75, cy: 0.55, radius: 0.75, ampX: 0.08, ampY: 0.07, period: 24, phase: 2.8),
      GlowOrb(color: Color(0x4D00FFE5), cx: 0.55, cy: 0.85, radius: 0.60, ampX: 0.06, ampY: 0.05, period: 18, phase: 5.0),
    ],
    particles: SkinParticle.spark,
    accent: const Color(0xFF00E0FF),
    ui: UiStyle(radius: 6, glassy: true, glassOpacity: 0.5, neonGlow: true, gradientButtons: true, appBarTransparent: true, navTransparent: true),
    animated: true,
    dark: true,
  );

  static final all = <SkinStyle>[
    plainLight,
    plainDark,
    aurora,
    cyberNeon,
    rainbow,
    galaxy,
    flame,
    electric,
  ];

  static SkinStyle byId(String id) {
    for (final s in all) {
      if (s.id == id) return s;
    }
    return plainDark;
  }
}
