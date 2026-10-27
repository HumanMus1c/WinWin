import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/gestures.dart'
    show GestureBinding, PointerSignalEvent, PointerScrollEvent;
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixTabRow, MiuixTabRowColors, MiuixTabRowDefaults, MiuixTheme;

import 'package:winwin/common/widgets/miuix_frosted_surface.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/style.dart';

/// 宽/窄形态切换阈值（**逻辑像素，按窗口宽度**判定）。
///
/// 选 700 的依据：窗口最小宽度为 640（`main.dart` 的 `minimumSize`），
/// 640–699 是桌面实测可拖出的窄屏带；Material 的 600 在该约束下几乎不可达，
/// 840 则会把 800×600 的桌面窗口误判为移动形态。
///
/// 判定读 `MediaQuery.sizeOf`（整窗宽）而不是控件自身约束：同一窗口内
/// 首页顶栏、历史分类条、动态页 Tab 的左右内距不同，按控件宽度判定会让
/// 三者在同一窗口宽度下切换时机不一致。
const double kAppTabBreakpoint = 700;

/// 标签栏形态。
///
/// - [rail]：**宽屏/鼠标**——紧凑胶囊轨道，内容自适应宽、左对齐、横向滚动，
///   hover + 手型光标 + 滚轮横滚（首页/历史现行观感）；
/// - [wide]：**窄屏/手指**——宽体页签（76–98 × 42），胶囊选中、横向滚动并可
///   自动居中选中项（动态页现行观感）；
/// - [auto]：按 [kAppTabBreakpoint] 自动选择。
enum AppTabForm { auto, rail, wide }

/// 解析当前窗口宽度对应的形态。
///
/// 显式传入 [form]（非 auto）时直接采用，供页面按语义强制形态。
AppTabForm resolveAppTabForm(
  BuildContext context, {
  AppTabForm form = AppTabForm.auto,
  double breakpoint = kAppTabBreakpoint,
}) {
  if (form != AppTabForm.auto) return form;
  return MediaQuery.sizeOf(context).width >= breakpoint
      ? AppTabForm.rail
      : AppTabForm.wide;
}

/// WinWin 通用 Tab 体系（Miuix 轨道），取代 Material 的
/// [TabBar] + [TabBarView] + [TabController] 三元组。
///
/// 拆成两个可独立落位的部件，均由同一 [AppTabController] 驱动：
/// - [AppTabBar]：头部标签栏（flutter_miuix [MiuixTabRow]，胶囊选中指示，
///   超出宽度自动横向滚动居中选中项）；
/// - [AppTabBody]：主体内容（[PageView]，保留原有左右滑动切换语义）。
///
/// 之所以拆开而非合成单控件：项目内 Tab 头与体常落在不同槽位
/// （`AppScaffold.topBar` + `body`、`SliverPersistentHeader` + `body`），
/// 合成控件无法同时适配。头/体结构简单并列时可直接用 [AppTabView]。
///
/// 联动规则：
/// - 点击头部或程序化 [AppTabController.animateTo] → 主体动画切页；
/// - 主体手势滑动 → 回写控制器索引 → 头部高亮跟随。
class AppTabController extends ChangeNotifier {
  AppTabController({required int length, int initialIndex = 0})
      : assert(length > 0, 'AppTabController.length 必须大于 0'),
        _length = length,
        _index = length > 1 ? initialIndex.clamp(0, length - 1) : 0;

  final int _length;
  int _index;

  /// 标签数量。
  int get length => _length;

  /// 当前选中索引。
  int get index => _index;

  /// 动画切换到 [value]（头部点击与程序化定位的统一入口）。
  void animateTo(int value) {
    final next = _normalize(value);
    if (next == _index) return;
    _index = next;
    notifyListeners();
  }

  /// 主体滑动回写（不触发主体自身的再次动画）。
  void _setIndexFromView(int value) {
    final next = _normalize(value);
    if (next == _index) return;
    _index = next;
    notifyListeners();
  }

  int _normalize(int value) => _length > 1 ? value.clamp(0, _length - 1) : 0;
}

/// 表现层标签条：只认 `selectedIndex / onSelected`，不持有控制器。
///
/// 与 [AppTabBar] 的分工：需要与 [AppTabBody] 联动（有 PageView）的页面用
/// [AppTabBar]；只有“分类切换、无翻页主体”的页面（首页分类、历史分类）直接
/// 用本组件即可——历史分类由服务端下发、数量会变，而 [AppTabController] 的
/// 长度是 final，不适合这类场景。
///
/// 两种形态的规格（细节原因见 [AppTabForm]）：
/// - 宽屏 [AppTabForm.rail]：行高默认 32，项宽随文字、左对齐、横向滚动；
///   hover 6% / 按压 sink 0.98 / 手型光标 / 滚轮横滚 / 选中项滚入可见；
/// - 窄屏 [AppTabForm.wide]：直接复用 flutter_miuix [MiuixTabRow]（76–98 宽、
///   42 高、胶囊选中），并保留库缺失的 hover 与按压反馈（见 [_AppWideTabRow]）。
class AppTabStrip extends StatefulWidget {
  const AppTabStrip({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.form = AppTabForm.auto,
    this.breakpoint = kAppTabBreakpoint,
    this.railHeight = 32,
    this.wideHeight = 42,
    this.railPadding = EdgeInsets.zero,
    this.widePadding = EdgeInsets.zero,
    this.railItemPadding = const EdgeInsets.symmetric(horizontal: 14),
    this.railItemInset = 0,
    this.itemGap = Style.sm,
    this.labelFontSize = 13,
    this.wideMinWidth,
    this.wideMaxWidth,
    this.wideColors,
    this.wideCornerRadius,
    this.contentAlignment,
    this.surface = false,
    this.surfacePadding = const EdgeInsets.symmetric(
      horizontal: Style.sm,
      vertical: Style.xs,
    ),
    this.surfaceRadius,
    this.surfaceOutline = true,
  });

  /// 标签文本（顺序与索引一一对应）。
  final List<String> tabs;

  /// 当前选中索引。
  final int selectedIndex;

  /// 选中回调（传标签索引）。
  final ValueChanged<int> onSelected;

  /// 形态；[AppTabForm.auto] 时按窗口宽度自动选择。
  final AppTabForm form;

  /// 自动形态的切换阈值。
  final double breakpoint;

  /// 宽屏轨道行高（默认 32，沿用首页分类条）。
  final double railHeight;

  /// 窄屏宽体行高（默认 42 = `MiuixTabRowDefaults.tabRowHeight`）。
  final double wideHeight;

  /// 宽屏轨道左右内距（默认 0）。
  ///
  /// **不要再用它做页面级缩进**：页面级位置由宿主的外层 `Padding` 提供，
  /// 容器内部距统一由 [surfacePadding] 决定（否则会出现「左内距过大」）。
  final EdgeInsets railPadding;

  /// 窄屏页签左右内距（默认 0，口径同 [railPadding]）。
  final EdgeInsets widePadding;

  /// 宽屏胶囊的左右内距。
  final EdgeInsets railItemPadding;

  /// 宽屏胶囊的上下内缩（0 = 胶囊填满行高；历史页传 5 保持原观感）。
  final double railItemInset;

  /// 项间距（两种形态共用，默认 `Style.sm`）。
  final double itemGap;

  /// 宽屏胶囊字号（默认 13）。
  final double labelFontSize;

  /// 窄屏页签的最小/最大项宽（默认取库值 76/98）。
  final double? wideMinWidth;
  final double? wideMaxWidth;

  /// 窄屏页签配色覆盖（默认取 Miuix 主题默认色）。
  final MiuixTabRowColors? wideColors;

  /// 窄屏页签圆角覆盖（默认取“自身高度的一半”全圆胶囊）。
  final double? wideCornerRadius;

  /// 窄屏页签内容对齐方式。
  final AlignmentGeometry? contentAlignment;

  /// 是否由本组件自绘**悬浮容器**（默认 false）。
  ///
  /// 开启后容器宽度**随标签数量收缩**（不再占满整行），并在左侧落位；
  /// 独立 TAB 栏（历史 / 直播 / 番剧 / 动态等）统一开启，首页「搜索框 +
  /// 分类器」合并控件由宿主自带材质，保持 false。
  final bool surface;

  /// 悬浮容器内距（标签行与容器边缘的间距）。
  ///
  /// 水平默认 [Style.sm]（8）：容器是全圆胶囊，4px 时末端圆弧会切到首/末
  /// 胶囊的圆角（实机反馈「最后一个胶囊无法完整显示」）；8px 是能容纳
  /// 34 高胶囊圆角的最小常用档。
  final EdgeInsets surfacePadding;

  /// 悬浮容器圆角；null = 全圆胶囊（容器总高的一半）。
  final double? surfaceRadius;

  /// 悬浮容器 1px 描边（默认 true，与动态页一致）。
  final bool surfaceOutline;

  @override
  State<AppTabStrip> createState() => _AppTabStripState();
}

class _AppTabStripState extends State<AppTabStrip> {
  @override
  Widget build(BuildContext context) {
    final form = resolveAppTabForm(
      context,
      form: widget.form,
      breakpoint: widget.breakpoint,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final available =
            constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity;
        final height =
            form == AppTabForm.rail ? widget.railHeight : widget.wideHeight;
        final surfacePadding = widget.surface ? widget.surfacePadding : EdgeInsets.zero;
        final maxRowWidth = available.isFinite
            ? math.max(0.0, available - surfacePadding.horizontal)
            : double.infinity;
        // 容器宽度随标签数量收缩（不再由父级撑满整行）；父级需给本组件松约束。
        final rowWidth = _resolveRowWidth(context, form, maxRowWidth);
        final row = SizedBox(
          width: rowWidth,
          height: height,
          child: form == AppTabForm.rail ? _buildRail() : _buildWideRow(),
        );
        if (!widget.surface) return row;

        final totalHeight = height + surfacePadding.vertical;
        final totalWidth = rowWidth + surfacePadding.horizontal;
        final radius = widget.surfaceRadius ?? totalHeight / 2;
        final inner = Padding(padding: surfacePadding, child: row);
        return SizedBox(
          width: totalWidth,
          height: totalHeight,
          // 容器**不填任何背景**（CVO：容器背景应为空或与窗口背景一致），
          // 只保留悬浮投影 + 1px 描边，由圆角轮廓定义胶囊形状。
          child: _TabFloatingSurface(
            radius: radius,
            outline: widget.surfaceOutline,
            child: inner,
          ),
        );
      },
    );
  }

  Widget _buildRail() {
    return _AppTabRail(
      tabs: widget.tabs,
      selectedIndex: widget.selectedIndex,
      onSelected: widget.onSelected,
      height: widget.railHeight,
      padding: widget.railPadding,
      itemPadding: widget.railItemPadding,
      itemInset: widget.railItemInset,
      gap: widget.itemGap,
      fontSize: widget.labelFontSize,
    );
  }

  Widget _buildWideRow() {
    return _AppWideTabRow(
      tabs: widget.tabs,
      selectedIndex: widget.selectedIndex,
      onSelected: widget.onSelected,
      height: widget.wideHeight,
      padding: widget.widePadding,
      gap: widget.itemGap,
      minWidth: widget.wideMinWidth,
      maxWidth: widget.wideMaxWidth,
      colors: widget.wideColors,
      cornerRadius: widget.wideCornerRadius,
      contentAlignment: widget.contentAlignment,
    );
  }

  /// 标签行所需宽度：容器随标签数量/文字宽度收缩的唯一口径。
  ///
  /// - 宽屏轨道：每项 = 文字宽 + 左右内距，逐项累加（与 [_AppTabRail] 一致）；
  /// - 窄屏页签：库内项宽是**统一值**，故取“所有标签都不省略”的最小统一宽
  ///   （文字宽 + 库内水平内距 × 2，clamp 到 76–98），再乘数量。
  ///
  /// 文字宽度用与渲染同源的 [TextStyle] + [MediaQuery.textScalerOf] 实测；
  /// 选中态按加粗测量（更宽者优先），避免切换选中时容器宽度抖动。
  double _resolveRowWidth(BuildContext context, AppTabForm form, double maxWidth) {
    final tabs = widget.tabs;
    if (tabs.isEmpty) return 0;
    double total;
    if (form == AppTabForm.rail) {
      final style = _railMeasureStyle(context);
      total = widget.railPadding.horizontal;
      for (final label in tabs) {
        // 文字宽向上取整 + 每项 1px 余量：避免亚像素/字体回退导致容器比
        // 真实内容窄 1~2px（会表现为「末项被裁」或「可向左短滑一下」）。
        total += _textWidth(context, label, style).ceilToDouble() +
            widget.railItemPadding.horizontal +
            1;
      }
      total += widget.itemGap * (tabs.length - 1);
    } else {
      final fontSize = MiuixTheme.of(context).textStyles.body1.fontSize ?? 16;
      final style = _wideMeasureStyle(context, fontSize);
      final minWidth = widget.wideMinWidth ?? MiuixTabRowDefaults.tabRowMinWidth;
      final maxWidthTab = widget.wideMaxWidth ?? MiuixTabRowDefaults.tabRowMaxWidth;
      double widest = minWidth;
      for (final label in tabs) {
        final raw = _textWidth(context, label, style) +
            MiuixTabRowDefaults.itemHorizontalPadding * 2 +
            2;
        widest = math.max(widest, raw.clamp(minWidth, maxWidthTab));
      }
      total = widget.widePadding.horizontal +
          widest * tabs.length +
          widget.itemGap * (tabs.length - 1);
    }
    return maxWidth.isFinite ? math.min(total, maxWidth) : total;
  }

  TextStyle _railMeasureStyle(BuildContext context) {
    return DefaultTextStyle.of(context).style.copyWith(
      fontSize: widget.labelFontSize,
      fontWeight: FontWeight.w600,
      height: 1.2,
      decoration: TextDecoration.none,
    );
  }

  TextStyle _wideMeasureStyle(BuildContext context, double fontSize) {
    return DefaultTextStyle.of(context).style.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      decoration: TextDecoration.none,
    );
  }

  double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }
}

/// TAB 栏悬浮容器：**无背景色**，只有投影 + 1px 描边。
///
/// CVO 口径：容器背景应为空（或与窗口背景一致），不得再叠毛玻璃 / 实色底；
/// 形状完全由圆角轮廓 + 悬浮投影定义。描边用 [foregroundDecoration]
/// （只画不占布局），否则 `Container` 会把 border 折算成内距，
/// 使末端胶囊被额外挤窄 1~2px（上一轮「最后一个胶囊显示不全」的成因之一）。
class _TabFloatingSurface extends StatelessWidget {
  const _TabFloatingSurface({
    required this.radius,
    required this.outline,
    required this.child,
  });

  final double radius;
  final bool outline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final isDark = tokens.isDark;
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.black.withValues(alpha: isDark ? 0.35 : 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      foregroundDecoration: outline
          ? BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: MiuixFrostedSurface.outlineColor(isDark: isDark),
              ),
            )
          : null,
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }
}

/// TAB 轨道的滚动行为：剔除鼠标拖动（保留触摸 / 触控笔）。
///
/// 桌面端“按住鼠标拖动标签条”没有任何收益，却会让轨道产生几像素的整体位移；
/// 溢出时的横向滚动通过滚轮（[_AppTabRail] 的 PointerSignal 映射）完成。
class _TabRailScrollBehavior extends ScrollBehavior {
  const _TabRailScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      };
}

/// 宽屏形态：紧凑胶囊轨道（鼠标优先）。
///
/// 与旧实现的关键差异：hover / 按压按**单项**判定（每项自带 `MouseRegion`），
/// 不再复刻 flutter_miuix 内部私有的宽度算法（旧 [AppTabBar] 的 `_tabWidth` /
/// `_hitIndex` 镜像会随库升级漂移）。
class _AppTabRail extends StatefulWidget {
  const _AppTabRail({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.height,
    required this.padding,
    required this.itemPadding,
    required this.itemInset,
    required this.gap,
    required this.fontSize,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;
  final EdgeInsets padding;
  final EdgeInsets itemPadding;
  final double itemInset;
  final double gap;
  final double fontSize;

  @override
  State<_AppTabRail> createState() => _AppTabRailState();
}

class _AppTabRailState extends State<_AppTabRail> {
  static const Duration _colorDuration = Duration(milliseconds: 160);
  static const Duration _sinkDuration = Duration(milliseconds: 90);

  static const double _hoverAlpha = 0.06;
  static const double _sinkAmount = 0.98;

  final ScrollController _scroll = ScrollController();

  /// 每项一个 Key：选中项滚入可见时需要取它的 RenderBox。
  List<GlobalKey> _keys = const [];

  int? _hoverIndex;
  int? _pressIndex;

  @override
  void initState() {
    super.initState();
    _rebuildKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected(animate: false));
  }

  @override
  void didUpdateWidget(_AppTabRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_keys.length != widget.tabs.length) {
      _rebuildKeys();
    }
    if (widget.selectedIndex != oldWidget.selectedIndex ||
        widget.tabs.length != oldWidget.tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _rebuildKeys() {
    _keys = List<GlobalKey>.generate(widget.tabs.length, (_) => GlobalKey());
  }

  double get _pillHeight =>
      math.max(0, widget.height - widget.itemInset * 2);

  /// 选中项滚入可见：**只在被裁切时**移动，避免每次换项都把轨道拉回居中。
  void _revealSelected({bool animate = true}) {
    if (!mounted || !_scroll.hasClients) return;
    if (widget.tabs.isEmpty) return;
    final index = widget.selectedIndex.clamp(0, widget.tabs.length - 1);
    final context = _keys[index].currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    final viewport = RenderAbstractViewport.of(box);
    final leading = viewport.getOffsetToReveal(box, 0).offset;
    final trailing = viewport.getOffsetToReveal(box, 1).offset;
    final fullyVisible = leading >= position.pixels &&
        trailing <= position.pixels + position.viewportDimension;
    if (fullyVisible) return;
    final target = viewport
        .getOffsetToReveal(box, 0.5)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return;
    if (animate) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  /// 纵向滚轮 → 轨道横向滚动（桌面浏览器标签条的通行语义）。
  ///
  /// 仅在轨道确实溢出时接管；否则不注册 `PointerSignalResolver`，
  /// 让滚轮继续驱动页面纵向滚动。
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= position.minScrollExtent) return;
    final delta = event.scrollDelta.dy.abs() >= event.scrollDelta.dx.abs()
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    final target = (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (_scroll.hasClients) _scroll.jumpTo(target);
    });
  }

  void _setHover(int? index) {
    if (_hoverIndex == index) return;
    setState(() => _hoverIndex = index);
  }

  void _setPress(int? index) {
    if (_pressIndex == index) return;
    setState(() => _pressIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppThemeHost.of(context).colors;
    return SizedBox(
      height: widget.height,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        // 桌面端不允许“按住鼠标拖动”整条轨道（实机反馈：用户空间可向左短滑）；
        // 触摸/触控笔仍可拖，滚轮走上面的 PointerSignal 映射。
        child: ScrollConfiguration(
          behavior: const _TabRailScrollBehavior(),
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: widget.padding,
            child: Row(
              children: [
                for (var i = 0; i < widget.tabs.length; i++) ...[
                  if (i > 0) SizedBox(width: widget.gap),
                  _buildItem(palette, i),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(AppPalette palette, int index) {
    final selected = index == widget.selectedIndex;
    final hovered = _hoverIndex == index || _pressIndex == index;
    final pressed = _pressIndex == index;
    final primary = palette.primary;
    final onSurface = palette.onSurface;
    return MouseRegion(
      key: _keys[index],
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHover(index),
      onExit: (_) => _setHover(null),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          _setHover(index);
          _setPress(index);
        },
        onPointerUp: (_) => _setPress(null),
        onPointerCancel: (_) => _setPress(null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onSelected(index),
          child: AnimatedScale(
            scale: pressed ? _sinkAmount : 1,
            duration: _sinkDuration,
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: _colorDuration,
              curve: Curves.easeOut,
              height: _pillHeight,
              padding: widget.itemPadding,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? primary.withValues(alpha: 0.18)
                    : (hovered
                        ? onSurface.withValues(alpha: _hoverAlpha)
                        : AppColors.transparent),
                borderRadius: BorderRadius.circular(_pillHeight / 2),
              ),
              // 描边只画不占布局：放在 decoration.border 里会让 Container 把
              // border 折算成内距，每项实际宽比测量值多 2px（导致末项被裁）。
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_pillHeight / 2),
                border: Border.all(
                  color: selected
                      ? primary.withValues(alpha: 0.45)
                      : AppColors.transparent,
                ),
              ),
              child: Text(
                widget.tabs[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? primary : palette.onSurfaceVariant,
                  fontSize: widget.fontSize,
                  // 显式行高收紧行盒：消除字体度量导致的下坠，Center 后光学居中。
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 窄屏形态：flutter_miuix [MiuixTabRow] 的封装，并补齐库缺失的交互。
///
/// flutter_miuix 1.3.0 的 `MiuixTabRow` 内部只用 `GestureDetector(onTap:)`
/// 承载标签项，**没有 hover 与按压反馈**；条形底色也是不透明的 `ColoredBox`。
/// 库为外部依赖不可改，故本组件在外层补齐：
/// - **hover / 按压反馈**：自算标签项矩形（复刻库内宽度算法）后，在库组件
///   **下层**绘制圆角高亮，按压时高亮加深并按 sink 口径整体轻微微缩；
/// - **透明条底**：库内底色恒置透明，由宿主决定材质（毛玻璃 / 页面底）；
/// - **去掉逐格描边**：库的未选中标签项自带 1px insetsquircle 描边，
///   实机上像“每格一个额外容器”，故在局部 [MiuixTheme] 覆盖中把 `outline`
///   置透明（仅影响本子树，不动全局主题与库）。
class _AppWideTabRow extends StatefulWidget {
  const _AppWideTabRow({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    required this.height,
    required this.padding,
    required this.gap,
    this.minWidth,
    this.maxWidth,
    this.colors,
    this.cornerRadius,
    this.contentAlignment,
  });

  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;
  final EdgeInsets padding;
  final double gap;
  final double? minWidth;
  final double? maxWidth;
  final MiuixTabRowColors? colors;
  final double? cornerRadius;
  final AlignmentGeometry? contentAlignment;

  @override
  State<_AppWideTabRow> createState() => _AppWideTabRowState();
}

class _AppWideTabRowState extends State<_AppWideTabRow> {
  static const Duration _feedbackDuration = Duration(milliseconds: 120);
  static const Duration _sinkDuration = Duration(milliseconds: 90);

  static const double _hoverAlpha = 0.06;
  static const double _pressAlpha = 0.12;
  static const double _sinkAmount = 0.98;

  /// 交给库的滚动控制器：既能读回偏移量（高亮层定位需要），
  /// 也让库不再自建控制器（由本组件负责释放）。
  final ScrollController _scroll = ScrollController();

  int? _hoverIndex;
  int? _pressIndex;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScrolled);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScrolled);
    _scroll.dispose();
    super.dispose();
  }

  /// 横向滚动会平移高亮层，需重建（仅在标签总宽超出可用宽时才触发）。
  void _onScrolled() {
    if (mounted) setState(() {});
  }

  double get _radius => widget.cornerRadius ?? widget.height / 2;

  /// 复刻 flutter_miuix 1.3.0 `_calculateTabWidth`（库内私有）。
  ///
  /// 库不暴露单项矩形，hover/按压的命中判定必须自算，故此处镜像同一算法；
  /// 算法随库版本变化时会漂移，升级 flutter_miuix 后需复核本函数。
  double _tabWidth(double available) {
    final count = widget.tabs.length;
    final minWidth = widget.minWidth ?? MiuixTabRowDefaults.tabRowMinWidth;
    final maxWidth = widget.maxWidth ?? MiuixTabRowDefaults.tabRowMaxWidth;
    if (count == 0) return minWidth;
    final totalSpacing = count > 1 ? (count - 1) * widget.gap : 0.0;
    final contentWidth = available - totalSpacing;
    if (contentWidth <= 0) return minWidth;
    final ideal = contentWidth / count;
    if (ideal < minWidth) return minWidth;
    if (ideal > maxWidth) {
      final totalMax = maxWidth * count + totalSpacing;
      return totalMax < available ? ideal : maxWidth;
    }
    return ideal;
  }

  /// 指针坐标 → 标签索引（落在标签间距的缝隙里返回 null）。
  int? _hitIndex(Offset local, double width, EdgeInsets padding) {
    final count = widget.tabs.length;
    if (count == 0) return null;
    final available = math.max(0.0, width - padding.horizontal);
    final tabWidth = _tabWidth(available);
    final pitch = tabWidth + widget.gap;
    final x = local.dx - padding.left + (_scroll.hasClients ? _scroll.offset : 0.0);
    if (x < 0) return null;
    final index = (x / pitch).floor();
    if (index < 0 || index >= count) return null;
    if (x - index * pitch > tabWidth) return null;
    return index;
  }

  void _onHover(Offset local, double width, EdgeInsets padding) {
    final index = _hitIndex(local, width, padding);
    if (index == _hoverIndex) return;
    setState(() => _hoverIndex = index);
  }

  void _onPointerDown(Offset local, double width, EdgeInsets padding) {
    final index = _hitIndex(local, width, padding);
    setState(() {
      _pressIndex = index;
      if (index != null) _hoverIndex = index;
    });
  }

  void _clearPress() {
    if (_pressIndex == null) return;
    setState(() => _pressIndex = null);
  }

  void _clearHover() {
    if (_hoverIndex == null) return;
    setState(() => _hoverIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding.resolve(Directionality.of(context));
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
          return Listener(
            // 仅做视觉反馈，不参与手势竞技：点击仍由库内 onTabSelected 处理。
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) =>
                _onPointerDown(event.localPosition, width, padding),
            onPointerUp: (_) => _clearPress(),
            onPointerCancel: (_) => _clearPress(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (event) => _onHover(event.localPosition, width, padding),
              onExit: (_) => _clearHover(),
              child: AnimatedScale(
                scale: _pressIndex == null ? 1.0 : _sinkAmount,
                duration: _sinkDuration,
                curve: Curves.easeOut,
                child: _buildSurface(context, width, padding),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSurface(BuildContext context, double width, EdgeInsets padding) {
    final tokens = AppThemeHost.of(context);
    final count = widget.tabs.length;
    final selected = count == 0 ? 0 : widget.selectedIndex.clamp(0, count - 1);
    // 高亮层常驻（透明度切换）以获得淡入淡出；按压优先于 hover。
    final highlightIndex = _pressIndex ?? _hoverIndex ?? selected;
    final highlightAlpha = _pressIndex != null
        ? _pressAlpha
        : (_hoverIndex != null ? _hoverAlpha : 0.0);
    final available = math.max(0.0, width - padding.horizontal);
    final tabWidth = _tabWidth(available);
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;

    return Stack(
      children: [
        Positioned(
          left: padding.left + highlightIndex * (tabWidth + widget.gap) - offset,
          top: 0,
          width: tabWidth,
          height: widget.height,
          child: AnimatedContainer(
            duration: _feedbackDuration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: tokens.colors.onSurface.withValues(alpha: highlightAlpha),
              borderRadius: BorderRadius.circular(_radius),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: padding.left, right: padding.right),
          child: _buildRow(context),
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context) {
    final count = widget.tabs.length;
    final baseColors = widget.colors ?? MiuixTabRowDefaults.defaultColors(context);
    final theme = MiuixTheme.of(context);
    return ScrollConfiguration(
      behavior: const _TabRailScrollBehavior(),
      child: MiuixTheme(
        // 库未暴露开关：未选中标签项由 `_InsetSquircleBorderPainter` 画 1px
        // insetsquircle 描边，颜色取 `MiuixTheme.colors.outline`。本项目标签条不要
        // 逐格方框（实机反馈：像每格一个额外容器，并连成整行上下细线），故在局部
        // 主题覆盖里把 outline 置透明；只影响本子树，不动全局主题与库。
        data: theme.copyWith(
          colors: theme.colors.copy(outline: AppColors.transparent),
        ),
        child: MiuixTabRow(
          tabs: widget.tabs,
          selectedTabIndex:
              count == 0 ? 0 : widget.selectedIndex.clamp(0, count - 1),
          onTabSelected: widget.onSelected,
          // 库内条底色恒置透明；容器材质由 [AppTabStrip] 的悬浮容器承担。
          colors: MiuixTabRowColors(
            backgroundColor: AppColors.transparent,
            contentColor: baseColors.contentColor,
            selectedBackgroundColor: baseColors.selectedBackgroundColor,
            selectedContentColor: baseColors.selectedContentColor,
          ),
          minWidth: widget.minWidth ?? MiuixTabRowDefaults.tabRowMinWidth,
          maxWidth: widget.maxWidth ?? MiuixTabRowDefaults.tabRowMaxWidth,
          height: widget.height,
          itemSpacing: widget.gap,
          cornerRadius: _radius,
          contentAlignment: widget.contentAlignment ?? Alignment.center,
          scrollController: _scroll,
        ),
      ),
    );
  }
}

/// Tab 头部标签栏：[MiuixTabRow] 的封装（宽/窄两形态），并补齐库缺失的材质。
///
/// 形态由 [AppTabStrip] 按窗口宽度自动选择：
/// - 宽屏（≥ [kAppTabBreakpoint]）：紧凑胶囊轨道（首页/历史观感），
///   行高与面板内距之和仍等于 [preferredHeight]，固定 extent 宿主不受影响；
/// - 窄屏：76–98 × 42 的宽体页签（动态页观感）。
///
/// 与 [AppTabBody] 共享 [controller]；点击项经 [AppTabController.animateTo]
/// 驱动主体切页。可落在 `AppScaffold.topBar`、`SliverPersistentHeader`
/// 或任意行内（配固定宽度即可收缩）。
class AppTabBar extends StatelessWidget {
  const AppTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.height,
    this.minWidth,
    this.maxWidth,
    this.colors,
    this.contentAlignment,
    this.blurBackground = true,
    this.borderRadius,
    this.panelPadding = const EdgeInsets.symmetric(
      horizontal: Style.sm,
      vertical: Style.xs,
    ),
    this.outline = true,
    this.form = AppTabForm.auto,
    this.breakpoint = kAppTabBreakpoint,
  });

  /// 头体共享控制器。
  final AppTabController controller;

  /// 标签文本（顺序与主体 children 一一对应）。
  final List<String> tabs;

  /// 覆盖标签栏高度（默认 [MiuixTabRowDefaults.tabRowHeight]）。
  final double? height;

  /// 覆盖单项最小宽度。
  final double? minWidth;

  /// 覆盖单项最大宽度。
  final double? maxWidth;

  /// 覆盖配色（默认取 Miuix 主题默认色）。
  final MiuixTabRowColors? colors;

  /// 覆盖单项内容对齐方式。
  final AlignmentGeometry? contentAlignment;

  /// 是否由本组件自绘**悬浮容器**（默认 true）。
  ///
  /// 容器本身**无背景色**（CVO 口径），只有圆角轮廓 + 1px 描边 + 下投影。
  /// 置 false 时不画容器，供宿主自带材质的场合使用（如空间页通栏吸顶带）。
  final bool blurBackground;

  /// 圆角（同时用于面板与选中指示）。
  ///
  /// 默认 `null` = **全圆胶囊**：面板取整条高度的一半（[preferredHeight] / 2），
  /// 选中指示取自身高度的一半（行高 / 2），与上游 PiliPlus 的分类
  /// 胶囊同观感；显式传值（含 0）时统一按该值作用于面板与选中项（旧口径）。
  final double? borderRadius;

  /// 面板内缩（标签条与容器边缘的间距，默认水平 [Style.sm] / 垂直 [Style.xs]）。
  ///
  /// 水平 8 是能容纳 34 高胶囊圆角的最小常用档（4px 时末端胶囊贴边）；
  /// 垂直 4 把标签行高压缩到 `高度 - 2×[Style.xs]`，选中胶囊据此取自身半径。
  final EdgeInsets panelPadding;

  /// 是否画面板 1px 描边（默认 true；置 false 时只保留毛玻璃与投影）。
  final bool outline;

  /// 形态覆盖；[AppTabForm.auto] 时按窗口宽度自动选择。
  final AppTabForm form;

  /// 自动形态的切换阈值。
  final double breakpoint;

  /// 默认标签行高（= flutter_miuix [MiuixTabRowDefaults.tabRowHeight]）。
  ///
  /// 供宿主计算"通栏毛玻璃带"总高或 Sliver 委托的固定 extent 使用，避免各处硬编码 42。
  /// **同时是两种形态的高度上限**：宽屏轨道只会更矮，固定 extent 宿主不会被裁切。
  static const double defaultHeight = MiuixTabRowDefaults.tabRowHeight;

  /// 头部实际高度（含覆盖值），供 Sliver 委托等需要固定 extent 的场景使用。
  double get preferredHeight => height ?? MiuixTabRowDefaults.tabRowHeight;

  /// 面板圆角：未显式覆盖时取全圆（整条高度的一半），得到胶囊外轮廓。
  double get _panelRadius => borderRadius ?? preferredHeight / 2;

  /// 标签行高：面板内缩后的净行高，也是选中胶囊的直径。
  double get _rowHeight {
    final inner = preferredHeight - panelPadding.vertical;
    return inner > 0 ? inner : MiuixTabRowDefaults.tabRowHeight;
  }

  /// 选中项 / hover 高亮圆角：未显式覆盖时取全圆（自身高度的一半）；
  /// 面板内缩后高亮层比面板矮，故不能沿用面板半径，否则会退化成方角。
  double get _pillRadius => borderRadius ?? _rowHeight / 2;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final count = tabs.length;
        final selected = count == 0 ? 0 : controller.index.clamp(0, count - 1);
        // 容器宽度由 [AppTabStrip] 按标签数量收缩；此处只负责**左对齐**落位，
        // 不再用 SizedBox(width: ∞) 撑满整行（动态页等独立 TAB 栏的关键改动）。
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: AppTabStrip(
            tabs: tabs,
            selectedIndex: selected,
            onSelected: controller.animateTo,
            form: form,
            breakpoint: breakpoint,
            // 两种形态都用净行高：面板总高 = 净行高 + 面板内距 = preferredHeight，
            // 固定 extent 宿主（番剧播放页 / 空间页吸顶带）不受影响。
            railHeight: _rowHeight,
            wideHeight: _rowHeight,
            railPadding: EdgeInsets.zero,
            widePadding: EdgeInsets.zero,
            itemGap: MiuixTabRowDefaults.tabRowItemSpacing,
            wideMinWidth: minWidth,
            wideMaxWidth: maxWidth,
            wideColors: colors,
            wideCornerRadius: _pillRadius,
            contentAlignment: contentAlignment,
            // 独立 TAB 栏统一使用动态页同款悬浮容器（毛玻璃 + 下投影）；
            // 宿主自带材质的场合（空间页通栏吸顶带）传 blurBackground=false 关闭。
            surface: blurBackground,
            surfacePadding: panelPadding,
            surfaceRadius: _panelRadius,
            surfaceOutline: outline,
          ),
        );
      },
    );
  }
}

/// Tab 主体内容：[PageView] 的薄封装，与 [AppTabBar] 共享 [controller]。
///
/// 宽屏（≥ [kAppTabBreakpoint]）关闭**鼠标拖动**翻页（桌面以点选为主），
/// 触摸 / 触控笔仍可左右滑；窄屏保持全设备可滑。
class AppTabBody extends StatefulWidget {
  const AppTabBody({
    super.key,
    required this.controller,
    required this.children,
  });

  /// 头体共享控制器。
  final AppTabController controller;

  /// 各标签页内容（顺序与头部 tabs 一一对应）。
  final List<Widget> children;

  @override
  State<AppTabBody> createState() => _AppTabBodyState();
}

/// 宽屏下剔除鼠标拖拽的滚动行为：两指滚动/滚轮不受影响，只是不允许“按住拖动翻页”。
class _AppTabPageScrollBehavior extends ScrollBehavior {
  const _AppTabPageScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
      };
}

class _AppTabBodyState extends State<AppTabBody> {
  static const Duration _switchDuration = Duration(milliseconds: 250);

  late final PageController _pageController;
  late int _page;

  /// 程序化切页动画进行中：此时忽略 [PageView.onPageChanged] 的中间页回报，
  /// 避免头部指示器在动画途中来回跳。
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _page = _clampToChildren(widget.controller.index);
    _pageController = PageController(initialPage: _page);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppTabBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    final target = _clampToChildren(widget.controller.index);
    if (target != _page) {
      _page = target;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(target);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _pageController.dispose();
    super.dispose();
  }

  int _clampToChildren(int index) {
    final count = widget.children.length;
    if (count == 0) return 0;
    return index.clamp(0, count - 1);
  }

  void _onControllerChanged() {
    final target = widget.controller.index;
    if (target == _page) return;
    _page = target;
    if (!mounted || !_pageController.hasClients) return;
    if (target < 0 || target >= widget.children.length) return;
    _animating = true;
    _pageController
        .animateToPage(
          target,
          duration: _switchDuration,
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _animating = false);
  }

  void _onPageChanged(int index) {
    if (_animating) return;
    _page = index;
    widget.controller._setIndexFromView(index);
  }

  @override
  Widget build(BuildContext context) {
    final page = PageView(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      children: widget.children,
    );
    if (MediaQuery.sizeOf(context).width < kAppTabBreakpoint) return page;
    return ScrollConfiguration(
      behavior: const _AppTabPageScrollBehavior(),
      child: page,
    );
  }
}

/// [AppTabBar] + [AppTabBody] 的组合：默认纵向并列，[floating] 为真时
/// 标签栏**浮于内容之上**（内容从栏后穿过）。
///
/// 两种落位：
/// - **非浮动态（默认）**：`Column[栏, 内容]`，适用于头体直接上下并列的场景
///   （如侧栏、对话框内）。此时栏在内容**之上**、背后无内容，[AppTabBar] 的
///   毛玻璃只能采样到纯色页底 → **模糊不可见**。
/// - **浮动态（[floating] = true）**：`Stack[内容(铺满), 标签栏(浮于顶部)]`，
///   内容可滚动到栏后方 → 毛玻璃（`BackdropFilter`）采样到滚动内容而**可见**。
///   根页面 Tab 栏要求可见模糊（对齐首页「搜索框 + 分类器合并栏」）时用此档；
///   调用方须在**滚动区**顶部预留 [floatingTopReserve] 避让（见该常量说明）。
///
/// 头体需落在完全不同的槽位（`AppScaffold.topBar` + `body`、
/// `SliverPersistentHeader` + `body`）时改用 [AppTabBar] / [AppTabBody] 分别落位。
class AppTabView extends StatelessWidget {
  const AppTabView({
    super.key,
    required this.controller,
    required this.tabs,
    required this.children,
    this.barHeight,
    this.colors,
    this.floating = false,
  });

  final AppTabController controller;
  final List<String> tabs;
  final List<Widget> children;
  final double? barHeight;
  final MiuixTabRowColors? colors;

  /// 浮动态：标签栏脱离纵向流、浮于内容之上，使内容从栏后穿过而令毛玻璃可见。
  final bool floating;

  /// 浮动态标签栏外缩（与首页合并栏同口径：水平 [Style.lg]、垂直 [Style.sm]）。
  static const EdgeInsets floatingInset = EdgeInsets.symmetric(
    horizontal: Style.lg,
    vertical: Style.sm,
  );

  /// 浮动态下**滚动内容顶部**需预留的高度 = 外缩上下留白（[Style.sm] × 2）
  /// + 标签行高（[AppTabBar.defaultHeight]）+ 下沿间隙（[Style.sm]）。
  ///
  /// 必须施加在**可滚动区内部**（`SliverPadding` / `ListView.padding` / `CustomScrollView`
  /// 的 sliver 内边距）：设在滚动区**外部**会把内容压到栏下方，内容便无法滚到栏后，
  /// 毛玻璃又不可见。
  ///
  /// 按**高度上限**（42）预留：宽屏形态的轨道更矮，只多出一点栏后留白，不会遮内容。
  static const double floatingTopReserve =
      Style.sm * 2 + AppTabBar.defaultHeight + Style.sm;

  @override
  Widget build(BuildContext context) {
    final bar = AppTabBar(
      controller: controller,
      tabs: tabs,
      height: barHeight,
      colors: colors,
    );
    final body = AppTabBody(controller: controller, children: children);

    if (!floating) {
      return Column(
        children: [
          bar,
          Expanded(child: body),
        ],
      );
    }

    // 浮动态：内容铺满整区并滚动，标签栏叠在其上 → 内容从栏后穿过时毛玻璃生效。
    // 栏外缩区域（Padding）非不透明，指针事件仍可穿透到后方内容。
    return Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: RepaintBoundary(
            child: Padding(padding: floatingInset, child: bar),
          ),
        ),
      ],
    );
  }
}
