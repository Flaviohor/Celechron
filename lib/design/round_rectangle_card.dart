import 'dart:async';

import 'package:flutter/cupertino.dart';

import 'package:celechron/design/glass.dart';
import 'package:celechron/utils/platform_features.dart';

class RoundRectangleCard extends StatefulWidget {
  final Widget child;
  final Function()? onTap;
  final bool animate;
  final List<BoxShadow> boxShadow;
  final EdgeInsets padding;

  /// 桌面端是否用液态玻璃铺底。
  ///
  /// false = 桌面端不铺底、不做模糊，留给外层统一做一整块玻璃
  /// （见 [RoundRectangleCardWithForehead]）。移动端不受影响，始终是实心卡片。
  final bool useGlass;

  const RoundRectangleCard({
    super.key,
    required this.child,
    this.onTap,
    this.animate = true,
    this.padding = const EdgeInsets.all(12),
    this.useGlass = true,
    this.boxShadow = const [
      BoxShadow(
        color: CupertinoColors.systemGrey5,
        spreadRadius: 0,
        blurRadius: 12,
        offset: Offset(0, 6),
      ),
    ],
  });

  @override
  State<RoundRectangleCard> createState() => _RoundRectangleCardState();
}

class _RoundRectangleCardState extends State<RoundRectangleCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 200),
        reverseDuration: const Duration(milliseconds: 400),
      );
      _scaleAnimation = Tween<double>(begin: 1, end: 0.95).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ),
      );
    }
  }

  @override
  void dispose() {
    if (widget.animate) {
      _animationController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.of(context).platformBrightness;
    final bool isDark = brightness == Brightness.dark;
    var isDown = false;
    var isCancel = false;

    // 桌面端把卡片做成液态玻璃：不再用不透明的 secondarySystemBackground，
    // 改成半透明 tint + 背景模糊，让窗口底色里的色斑与随指针走的柔光透上来。
    // 移动端保持原来的实心卡片（玻璃是桌面端专属的观感处理）。
    late final Widget core;
    if (PlatformFeatures.isDesktop && !widget.useGlass) {
      // 外层已经是一整块玻璃，这里只负责内边距和点击动画，
      // 不再铺底、不再二次模糊。
      core = Container(padding: widget.padding, child: widget.child);
    } else if (PlatformFeatures.isDesktop) {
      final List<BoxShadow>? shadows = widget.boxShadow.isEmpty
          ? const <BoxShadow>[]
          : (isDark ? null : widget.boxShadow);
      core = GlassSurface(
        sigma: 16,
        borderRadius: BorderRadius.circular(12),
        // 不传 tint / tintOpacity，走主题自动值：
        // 深色 = 白 @0.085 的微亮半透明板，浅色 = 白磨砂板。
        // 深色下用黑色 tint 会把卡片压成比背景更暗的块，反而更平。
        borderOpacity: isDark ? 0.16 : 0.5,
        boxShadow: shadows,
        padding: widget.padding,
        child: widget.child,
      );
    } else {
      core = Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: isDark ? null : widget.boxShadow,
            color: isDark
                ? CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemBackground, context)
                : CupertinoDynamicColor.resolve(CupertinoColors.white, context),
          ),
          child: widget.child);
    }

    return widget.animate
        ? GestureDetector(
            onTapDown: (_) async {
              isDown = true;
              isCancel = false;
              _animationController.forward();
              await Future.delayed(const Duration(milliseconds: 125));
              isDown = false;
              if (isCancel) {
                if (widget.onTap != null) {
                  widget.onTap?.call();
                }
                _animationController.reverse();
                isCancel = false;
              }
            },
            onTapUp: (_) async {
              isCancel = true;
              if (!isDown) _animationController.reverse();
            },
            onTapCancel: () async => _animationController.reverse(),
            child: ScaleTransition(scale: _scaleAnimation, child: core),
          )
        : GestureDetector(onTap: widget.onTap, child: core);
  }
}

class RoundRectangleCardWithForehead extends StatelessWidget {
  final Widget child;
  final Widget forehead;
  final Color foreheadColor;
  final Function()? onTap;
  final bool animate;

  const RoundRectangleCardWithForehead({
    super.key,
    required this.child,
    required this.forehead,
    this.foreheadColor = CupertinoColors.systemFill,
    this.onTap,
    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color resolved =
        CupertinoDynamicColor.resolve(foreheadColor, context);
    // 桌面端：把整张卡做成一整块「带主题色的玻璃」，而不是一层实色底
    // 再叠一层玻璃——那样额头和内容会分成两层，看着割裂。
    // 移动端：保持原来的实色额头。
    final bool glass = PlatformFeatures.isDesktop;
    return Stack(
      children: [
        Positioned.fill(
          child: glass
              ? GlassSurface(
                  sigma: 16,
                  borderRadius: BorderRadius.circular(12),
                  // 传入的 foreheadColor 自带 alpha（一般 0.25），
                  // 直接当 tint 会被叠成很淡的一层，所以先把 alpha 拉满，
                  // 再由 tintOpacity 统一控制浓度。
                  tint: resolved.withValues(alpha: 1.0),
                  tintOpacity: 0.20,
                  borderOpacity: 0.22,
                  boxShadow: const <BoxShadow>[],
                  child: const SizedBox.expand(),
                )
              : Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: resolved,
                    boxShadow: const [],
                  ),
                ),
        ),
        SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              forehead,
              RoundRectangleCard(
                onTap: onTap,
                animate: animate,
                boxShadow: const [],
                useGlass: false,
                child: child,
              ),
            ],
          ),
        )
      ],
    );
  }
}
