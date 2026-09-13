import 'dart:ui';

import 'package:flutter/cupertino.dart';

/// 桌面端的「液态玻璃」工具组件。
///
/// 设计目标：在不引入 Material 主题的前提下，用 BackdropFilter 实现类
/// macOS / iOS 的玻璃质感；可叠加 tint 颜色与阴影，模拟层次感。
///
/// **仅桌面端使用**：移动端 BackdropFilter 性能虽 OK 但视觉上与原生
/// Cupertino 不一致。调用方应通过 [PlatformFeatures.isDesktop] 守门。
///
/// 性能说明：sigma=18 在 Windows 桌面 release 下不掉帧；若发现掉帧
/// 可降到 12，但模糊半径过小会失去层次。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.sigma = 18,
    this.borderRadius,
    this.tint,
    this.tintOpacity = 0.55,
    this.borderOpacity = 0.18,
    this.boxShadow,
    this.padding,
    this.margin,
  });

  final Widget child;

  /// 高斯模糊半径。值越大越模糊；sigma=18 是 macOS 偏中等的强度。
  final double sigma;

  /// 圆角；不传则无圆角（一般给顶部条用）。
  final BorderRadius? borderRadius;

  /// tint 颜色基色；默认跟随系统（浅色白 / 深色黑）。
  final Color? tint;

  /// tint 不透明度（0–1）。
  final double tintOpacity;

  /// 边缘高亮线不透明度。
  final double borderOpacity;

  /// 自定义阴影；不传则给一组柔和的悬浮阴影。
  final List<BoxShadow>? boxShadow;

  /// 内边距。
  final EdgeInsetsGeometry? padding;

  /// 外边距。
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final defaultTint = brightness == Brightness.dark
        ? CupertinoColors.black
        : CupertinoColors.white;
    final base = tint ?? defaultTint;
    final clampedOpacity = tintOpacity.clamp(0.0, 1.0);
    final clampedBorder = borderOpacity.clamp(0.0, 1.0);

    final decoration = BoxDecoration(
      color: base.withValues(alpha: clampedOpacity),
      borderRadius: borderRadius,
      border: Border.all(
        color: CupertinoColors.white.withValues(alpha: clampedBorder),
        width: 1,
      ),
      boxShadow: boxShadow ??
          const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
    );

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    Widget framed = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(decoration: decoration, child: content),
      ),
    );

    if (margin != null) {
      framed = Padding(padding: margin!, child: framed);
    }
    return framed;
  }
}

/// 桌面端窗口底色：对角线渐变，让玻璃模糊能出层次。
///
/// 单色底 BackdropFilter 模糊出来还是单色，没有「液态玻璃」的层次感。
/// 这里给一组 Apple 风格的渐变：
///   - 浅色：从 systemGroupedBackground 到稍偏蓝的灰
///   - 深色：从 systemBackground 到稍偏紫的深色
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.brightnessOf(context);
    final colors = brightness == Brightness.dark
        ? const [
            Color(0xFF1C1C1E),
            Color(0xFF2C2C30),
            Color(0xFF1F1F23),
          ]
        : const [
            Color(0xFFF2F2F7),
            Color(0xFFE5E8EE),
            Color(0xFFF6F6F9),
          ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// 选中态胶囊：在玻璃面板内部用于高亮当前选中项。
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    required this.color,
  });

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

/// 一个统一的桌面端玻璃入口：把 `GlassSurface` + 圆角 + 阴影打包成静态方法，
/// 方便在卡片 / 顶栏 / 弹窗里以最简方式拿到玻璃效果。
class Glass {
  Glass._();

  /// 顶部条（无圆角或仅底部圆角）
  static Widget bar({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
  }) {
    return GlassSurface(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      padding: padding,
      margin: margin,
      child: child,
    );
  }

  /// 卡片（四周圆角 + 阴影）
  static Widget card({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    BorderRadius? borderRadius,
  }) {
    return GlassSurface(
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(18)),
      padding: padding,
      margin: margin,
      child: child,
    );
  }

  /// 浮岛（用于悬浮导航）
  static Widget island({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    BorderRadius? borderRadius,
  }) {
    return GlassSurface(
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(22)),
      padding: padding,
      margin: margin,
      child: child,
    );
  }
}

/// 把任何子 widget 套上玻璃卡片。
///
/// 与 [Glass.card] 的区别：本组件只做「模糊背景层 + 边框 + 阴影 + 圆角」，
/// 不画 tint 色（tintOpacity=0），让调用方提供的子 widget 自己负责前景色。
/// 适合在 CupertinoListSection 这种本身有背景色的 widget 外面套一层。
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.sigma = 18,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  final Widget child;
  final double sigma;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      sigma: sigma,
      borderRadius: borderRadius,
      tintOpacity: 0,
      borderOpacity: 0.22,
      boxShadow: const [
        BoxShadow(
          color: Color(0x12000000),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ],
      child: child,
    );
  }
}

