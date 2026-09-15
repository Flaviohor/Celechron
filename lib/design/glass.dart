import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart' show PointerHoverEvent, PointerMoveEvent;

/// 桌面端的「液态玻璃 / 沉浸光感」工具组件。
///
/// 与早期版本（只有「模糊 + 均匀 1px 白边」）相比，这里补上了玻璃真正
/// 需要的东西：
///
///   1. **背景要透得出东西**。纯色底模糊出来还是纯色，所以 [AppBackdrop]
///      除了渐变，还会铺几团柔和色斑，并让一团柔光跟着指针走。
///   2. **棱与厚**。边缘用受光的渐变描边（顶部亮、底部淡），内侧再加一条
///      顶部高光带，玻璃才有「厚度」而不是一块磨砂塑料。
///   3. **材质会提色**。Apple / 鸿蒙的系统材质都会抬升底层的饱和度和亮度，
///      这里用 color matrix 叠在模糊之后。
///   4. **光要动**。桌面没有陀螺仪，改让指针当光源：[PointerLight] 记录指针
///      位置，玻璃面板上叠一层随指针走的镜面高光。
///
/// **仅桌面端使用**：调用方应通过 `PlatformFeatures.isDesktop` 守门。
///
/// 性能：模糊仍是 sigma=18（release 下不掉帧）。新增的描边 / 高光都是单次
/// drawRRect / drawCircle；随指针重绘的只有一层渐变圆，开销可忽略。

/// 全局指针位置（**屏幕**坐标，逻辑像素）。null 表示还没收到过 hover。
///
/// 用全局单例而不是 InheritedWidget：玻璃面板可能在很深的位置，而指针位置
/// 每帧都在变，走 InheritedWidget 会把整棵子树标脏。
class PointerLight extends ValueNotifier<Offset?> {
  PointerLight._() : super(null);

  static final PointerLight instance = PointerLight._();
}

/// 包住子树，开始跟踪指针位置供 [PointerLight] 消费。
///
/// 用 [Listener] 而不是 `MouseRegion`：MouseRegion 默认 `opaque: true`，
/// 会挡住它下面的区域，套在根节点上会影响手势。
class PointerLightScope extends StatelessWidget {
  const PointerLightScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: (PointerHoverEvent e) =>
          PointerLight.instance.value = e.position,
      onPointerMove: (PointerMoveEvent e) =>
          PointerLight.instance.value = e.position,
      child: child,
    );
  }
}

/// 饱和度 + 亮度矩阵：叠在模糊之后，模拟系统材质对底层的「提色」。
List<double> _materialMatrix(double saturate, double brighten) {
  const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final double s = saturate;
  final double sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
  final double add = brighten * 255.0;
  return <double>[
    sr + s, sg, sb, 0, add, //
    sr, sg + s, sb, 0, add, //
    sr, sg, sb + s, 0, add, //
    0, 0, 0, 1, 0, //
  ];
}

/// 把屏幕坐标换算成本地坐标；拿不到 RenderBox 时返回 null。
Offset? _toLocal(GlobalKey key, Offset screenPoint) {
  final RenderObject? ro = key.currentContext?.findRenderObject();
  if (ro is! RenderBox || !ro.hasSize) return null;
  return screenPoint - ro.localToGlobal(Offset.zero);
}

/// 悬浮阴影：近处一层紧实、远处一层弥散，比单层阴影更「离得开桌面」。
List<BoxShadow> _floatingShadow(bool isDark) {
  return <BoxShadow>[
    BoxShadow(
      color: CupertinoColors.black.withValues(alpha: isDark ? 0.30 : 0.085),
      blurRadius: 34,
      spreadRadius: -8,
      offset: const Offset(0, 14),
    ),
    BoxShadow(
      color: CupertinoColors.black.withValues(alpha: isDark ? 0.16 : 0.05),
      blurRadius: 8,
      spreadRadius: -2,
      offset: const Offset(0, 3),
    ),
  ];
}

/// 玻璃面板。
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.sigma = 18,
    this.borderRadius,
    this.tint,
    this.tintOpacity,
    this.borderOpacity = 0.18,
    this.boxShadow,
    this.padding,
    this.margin,
    this.saturate = 1.35,
    this.brighten = 0.035,
    this.sheen = true,
    this.specular = false,
  });

  final Widget child;

  /// 高斯模糊半径。值越大越模糊；sigma=18 是 macOS 偏中等的强度。
  final double sigma;

  /// 圆角；不传则无圆角（一般给顶部条用）。
  final BorderRadius? borderRadius;

  /// tint 颜色基色；不传则用白色（深浅色都靠不透明度控制）。
  final Color? tint;

  /// tint 不透明度。
  ///
  /// **不传则按主题自动**：浅色 0.60（白磨砂板）、深色 0.085。
  /// 深色下玻璃是「比背景略亮的半透明板」，用黑色 tint 会变成一块暗洞，
  /// 反而比背景更黑、更平。传 0 表示不画 tint（留给子 widget 自己铺底）。
  final double? tintOpacity;

  /// 边缘高亮线不透明度（顶部会再亮一些）。
  final double borderOpacity;

  /// 自定义阴影；不传则给一组柔和的悬浮阴影。
  final List<BoxShadow>? boxShadow;

  /// 内边距。
  final EdgeInsetsGeometry? padding;

  /// 外边距。
  final EdgeInsetsGeometry? margin;

  /// 底层饱和度提升倍数。1.0 = 不变。
  final double saturate;

  /// 底层亮度抬升量（0–1，映射成 0–255 的加性偏移）。
  final double brighten;

  /// 内侧顶部高光带（玻璃厚度感）。
  final bool sheen;

  /// 是否叠一层随指针移动的镜面高光。
  final bool specular;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = CupertinoTheme.brightnessOf(context);
    final bool isDark = brightness == Brightness.dark;
    final Color base = tint ?? CupertinoColors.white;
    final BorderRadius br = borderRadius ?? BorderRadius.zero;
    final double alpha = tintOpacity ?? (isDark ? 0.085 : 0.60);
    final double edge = borderOpacity.clamp(0.0, 1.0);

    Widget body = child;
    if (padding != null) {
      body = Padding(padding: padding!, child: body);
    }

    final Widget layered = Stack(
      children: <Widget>[
        // 1) tint 底色
        if (alpha > 0.001)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: base.withValues(alpha: alpha),
                borderRadius: br,
              ),
            ),
          ),
        // 2) 内侧顶部高光：模拟玻璃上沿受光
        if (sheen)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: br,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      CupertinoColors.white
                          .withValues(alpha: isDark ? 0.055 : 0.42),
                      CupertinoColors.white.withValues(alpha: 0.012),
                      CupertinoColors.white.withValues(alpha: 0.0),
                    ],
                    stops: const <double>[0.0, 0.36, 0.75],
                  ),
                ),
              ),
            ),
          ),
        // 3) 内容（决定尺寸）
        body,
        // 4) 指针镜面高光
        if (specular)
          Positioned.fill(
            child: IgnorePointer(
              child: _SpecularLayer(isDark: isDark),
            ),
          ),
        // 5) 受光边缘
        if (edge > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _EdgeGlowPainter(
                  borderRadius: br,
                  opacity: edge,
                  isDark: isDark,
                ),
              ),
            ),
          ),
      ],
    );

    final ui.ImageFilter filter = ui.ImageFilter.compose(
      outer: ColorFilter.matrix(_materialMatrix(saturate, brighten)),
      inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );

    Widget framed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: boxShadow ?? _floatingShadow(isDark),
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(filter: filter, child: layered),
      ),
    );

    if (margin != null) {
      framed = Padding(padding: margin!, child: framed);
    }
    return framed;
  }
}

/// 随指针移动的镜面高光。用 [PointerLight] 作为 repaint 源，
/// 指针移动时只重绘这一层，不重建 widget 树。
class _SpecularLayer extends StatefulWidget {
  const _SpecularLayer({required this.isDark});

  final bool isDark;

  @override
  State<_SpecularLayer> createState() => _SpecularLayerState();
}

class _SpecularLayerState extends State<_SpecularLayer> {
  final GlobalKey _boxKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: _boxKey,
      painter: _SpecularPainter(
        repaint: PointerLight.instance,
        boxKey: _boxKey,
        isDark: widget.isDark,
      ),
    );
  }
}

class _SpecularPainter extends CustomPainter {
  _SpecularPainter({
    required Listenable repaint,
    required this.boxKey,
    required this.isDark,
  }) : super(repaint: repaint);

  final GlobalKey boxKey;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Offset? pointer = PointerLight.instance.value;
    if (pointer == null) return;
    final Offset? local = _toLocal(boxKey, pointer);
    if (local == null || !size.contains(local)) return;

    final double r = math.max(size.width, size.height) * 0.8;
    final double a = isDark ? 0.13 : 0.28;
    canvas.drawCircle(
      local,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          local,
          r,
          <Color>[
            CupertinoColors.white.withValues(alpha: a),
            CupertinoColors.white.withValues(alpha: a * 0.3),
            CupertinoColors.white.withValues(alpha: 0.0),
          ],
          const <double>[0.0, 0.45, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_SpecularPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// 受光边缘：一圈渐变描边，顶部最亮、底部最淡；再在顶部补一条更亮的细线。
class _EdgeGlowPainter extends CustomPainter {
  _EdgeGlowPainter({
    required this.borderRadius,
    required this.opacity,
    required this.isDark,
  });

  final BorderRadius borderRadius;
  final double opacity;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final RRect rrect = borderRadius.toRRect(Offset.zero & size).deflate(0.6);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            CupertinoColors.white.withValues(alpha: opacity * 1.7),
            CupertinoColors.white.withValues(alpha: opacity * 0.9),
            CupertinoColors.white.withValues(alpha: opacity * 0.22),
          ],
          stops: const <double>[0.0, 0.45, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_EdgeGlowPainter oldDelegate) =>
      oldDelegate.opacity != opacity ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.isDark != isDark;
}

/// 桌面端窗口底色 + 环境光。
///
/// 玻璃要有东西可透才像玻璃。这里铺三层：
///   1. 对角线渐变（基础明暗）
///   2. 几团固定的柔和色斑（给模糊提供结构，否则糊出来还是一片灰）
///   3. 一团跟着指针走的柔光（沉浸光感的来源，透过玻璃会被糊开）
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, this.pointerGlow = true});

  final Widget child;

  /// 是否启用「光随指针走」。
  final bool pointerGlow;

  @override
  Widget build(BuildContext context) {
    final bool isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final List<Color> colors = isDark
        ? const <Color>[
            Color(0xFF1B1B22),
            Color(0xFF26262F),
            Color(0xFF1D1D25),
          ]
        : const <Color>[
            Color(0xFFF3F3F8),
            Color(0xFFE7EAF2),
            Color(0xFFF7F7FA),
          ];
    return PointerLightScope(
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                  stops: const <double>[0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _AmbientGlowPainter(isDark: isDark)),
          ),
          if (pointerGlow)
            Positioned.fill(child: _PointerGlow(isDark: isDark)),
          child,
        ],
      ),
    );
  }
}

/// 固定的几团柔和色斑：冷暖各一，偏角落分布，避免中心过花。
class _AmbientGlowPainter extends CustomPainter {
  const _AmbientGlowPainter({required this.isDark});

  final bool isDark;

  void _blob(
    Canvas canvas,
    Size size,
    Alignment align,
    double radiusFactor,
    Color color,
    double alpha,
  ) {
    final Rect rect = Offset.zero & size;
    final Offset c = align.inscribe(Size(size.width, size.height), rect).center;
    final double r = math.max(size.width, size.height) * radiusFactor;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r,
          <Color>[
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0.0),
          ],
        ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final double k = isDark ? 1.0 : 0.62;
    _blob(canvas, size, const Alignment(-0.85, -0.95), 0.62,
        const Color(0xFF3B6CF0), 0.22 * k);
    _blob(canvas, size, const Alignment(0.95, -0.35), 0.55,
        const Color(0xFF8B5CF6), 0.18 * k);
    _blob(canvas, size, const Alignment(0.15, 1.05), 0.60,
        const Color(0xFF14B8A6), 0.13 * k);
  }

  @override
  bool shouldRepaint(_AmbientGlowPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// 跟着指针走的大面积柔光。半径给得大、alpha 给得低，
/// 目的是让玻璃有「光在动」的观感，而不是一个刺眼的光斑。
class _PointerGlow extends StatefulWidget {
  const _PointerGlow({required this.isDark});

  final bool isDark;

  @override
  State<_PointerGlow> createState() => _PointerGlowState();
}

class _PointerGlowState extends State<_PointerGlow> {
  final GlobalKey _boxKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: _boxKey,
      painter: _PointerGlowPainter(
        repaint: PointerLight.instance,
        boxKey: _boxKey,
        isDark: widget.isDark,
      ),
    );
  }
}

class _PointerGlowPainter extends CustomPainter {
  _PointerGlowPainter({
    required Listenable repaint,
    required this.boxKey,
    required this.isDark,
  }) : super(repaint: repaint);

  final GlobalKey boxKey;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Offset? pointer = PointerLight.instance.value;
    if (pointer == null) return;
    final Offset? local = _toLocal(boxKey, pointer);
    if (local == null) return;

    final double r = math.max(size.width, size.height) * 0.45;
    final double a = isDark ? 0.055 : 0.10;
    canvas.drawCircle(
      local,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          local,
          r,
          <Color>[
            CupertinoColors.white.withValues(alpha: a),
            CupertinoColors.white.withValues(alpha: 0.0),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_PointerGlowPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
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
    bool specular = false,
  }) {
    return GlassSurface(
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(18)),
      padding: padding,
      margin: margin,
      specular: specular,
      child: child,
    );
  }

  /// 浮岛（用于悬浮导航）。默认开启指针光斑——这是最显眼的玻璃面。
  static Widget island({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    BorderRadius? borderRadius,
    bool specular = true,
  }) {
    return GlassSurface(
      borderRadius: borderRadius ?? const BorderRadius.all(Radius.circular(22)),
      padding: padding,
      margin: margin,
      specular: specular,
      child: child,
    );
  }
}

/// 把任何子 widget 套上玻璃卡片。
///
/// 与 [Glass.card] 的区别：本组件只做「模糊背景层 + 边框 + 高光 + 阴影 + 圆角」，
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
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: CupertinoColors.black.withValues(alpha: 0.10),
          blurRadius: 22,
          spreadRadius: -6,
          offset: const Offset(0, 8),
        ),
      ],
      child: child,
    );
  }
}
