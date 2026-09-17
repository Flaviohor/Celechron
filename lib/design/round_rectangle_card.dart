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

  const RoundRectangleCard({
    super.key,
    required this.child,
    this.onTap,
    this.animate = true,
    this.padding = const EdgeInsets.all(12),
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
    if (PlatformFeatures.isDesktop) {
      final List<BoxShadow>? shadows = widget.boxShadow.isEmpty
          ? const <BoxShadow>[]
          : (isDark ? null : widget.boxShadow);
      core = GlassSurface(
        sigma: 16,
        borderRadius: BorderRadius.circular(12),
        tintOpacity: isDark ? 0.085 : 0.80,
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
    return Stack(
      children: [
        Positioned.fill(
            child: SizedBox(
                child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: CupertinoDynamicColor.resolve(foreheadColor, context),
            boxShadow: const [],
          ),
        ))),
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
                child: child,
              ),
            ],
          ),
        )
      ],
    );
  }
}
