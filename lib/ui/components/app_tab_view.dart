import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixTabRow, MiuixTabRowColors, MiuixTabRowDefaults, MiuixTheme;

import 'package:winwin/common/widgets/miuix_frosted_surface.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/style.dart';

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

/// Tab 头部标签栏：[MiuixTabRow] 的封装，并补齐库缺失的交互与材质。
///
/// flutter_miuix 1.3.0 的 `MiuixTabRow` 内部只用 `GestureDetector(onTap:)`
/// 承载标签项，**没有 hover 与按压反馈**；条形底色也是不透明的 `ColoredBox`，
/// **无法承载模糊**。库为外部依赖不可改，故本组件在外层补齐：
/// - **hover / 按压反馈**：自算标签项矩形（复刻库内宽度算法）后，在库组件
///   **下层**绘制圆角高亮（未选标签项自身透明，可透出），按压时高亮加深并按
///   项目既有 sink 口径（`sinkAmount` 0.98）整体轻微微缩；
/// - **毛玻璃底**（[blurBackground]）：与 `lib/common/widgets/miuix_overlay_panel.dart`
///   同口径（blur 16 + 半透明底 × [kMiuixSurfaceAlpha] + 可选 1px 描边（[outline]）
///   + 下投影），同时把库内底色改为透明，使滚动内容从栏后经过时呈模糊；
/// - **全圆胶囊**：面板与选中项默认都取自身高度的一半作圆角（[borderRadius] 传
///   null），配合 [panelPadding] 的四向内缩，得到上游 PiliPlus 分类条的
///   「浅底胶囊 + 浮起白色胶囊」观感；
/// - **去掉逐格描边**：库的未选中标签项自带 1px insetsquircle 描边
///   （`_InsetSquircleBorderPainter`，取 `MiuixTheme.colors.outline`，库内无开关），
///   实机上看着像"每格一个额外容器"并连成整行上下细线；故在局部 [MiuixTheme]
///   覆盖中把 `outline` 置透明（仅影响本子树，不动全局主题与库）。
///
/// 与 [AppTabBody] 共享 [controller]；点击项经 [AppTabController.animateTo]
/// 驱动主体切页。可落在 `AppScaffold.topBar`、`SliverPersistentHeader`
/// 或任意行内（配固定宽度即可收缩）。
class AppTabBar extends StatefulWidget {
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
    this.blurSigma = 16,
    this.borderRadius,
    this.panelPadding = const EdgeInsets.all(Style.xs),
    this.outline = true,
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

  /// 是否由本组件自绘毛玻璃底（默认 true）。
  ///
  /// 置 false 时不画毛玻璃面板（标签条自身透明），供宿主自带背景的场合使用
  /// （如空间页按钮行：该行已有通栏毛玻璃带，避免两层材质叠加发灰）。
  final bool blurBackground;

  /// 毛玻璃模糊半径（默认 16，对齐 `MiuixOverlayPanel`）。
  final double blurSigma;

  /// 圆角（同时用于面板与选中指示）。
  ///
  /// 默认 `null` = **全圆胶囊**：面板取整条高度的一半（[preferredHeight] / 2），
  /// 选中指示取自身高度的一半（行高 / 2），与上游 PiliPlus 的分类
  /// 胶囊同观感；显式传值（含 0）时统一按该值作用于面板与选中项（旧口径）。
  final double? borderRadius;

  /// 面板内缩（标签条与面板边缘的间距，默认 [Style.xs]）。
  ///
  /// 四向留白让选中胶囊**浮**在面板内（贴边时会与面板外轮廓重合而看不出层次），
  /// 同时把标签行高压缩到 `高度 - 2×[Style.xs]`，选中胶囊据此取自身半径。
  final EdgeInsets panelPadding;

  /// 是否画面板 1px 描边（默认 true；置 false 时只保留毛玻璃与投影）。
  final bool outline;

  /// 默认标签行高（= flutter_miuix [MiuixTabRowDefaults.tabRowHeight]）。
  ///
  /// 供宿主计算"通栏毛玻璃带"总高或 Sliver 委托的固定 extent 使用，避免各处硬编码 42。
  static const double defaultHeight = MiuixTabRowDefaults.tabRowHeight;

  /// 头部实际高度（含覆盖值），供 Sliver 委托等需要固定 extent 的场景使用。
  double get preferredHeight => height ?? MiuixTabRowDefaults.tabRowHeight;

  @override
  State<AppTabBar> createState() => _AppTabBarState();
}

class _AppTabBarState extends State<AppTabBar> {
  /// 高亮淡入淡出时长。
  static const Duration _feedbackDuration = Duration(milliseconds: 120);

  /// 按压微缩时长。
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

  double get _rowHeight {
    final inner =
        (widget.height ?? MiuixTabRowDefaults.tabRowHeight) -
        widget.panelPadding.vertical;
    return inner > 0 ? inner : MiuixTabRowDefaults.tabRowHeight;
  }

  /// 面板圆角：未显式覆盖时取全圆（整条高度的一半），得到胶囊外轮廓。
  double get _panelRadius => widget.borderRadius ?? widget.preferredHeight / 2;

  /// 选中项 / hover 高亮圆角：未显式覆盖时取全圆（自身高度的一半）；
  /// 面板内缩后高亮层比面板矮，故不能沿用面板半径，否则会退化成方角。
  double get _pillRadius => widget.borderRadius ?? _rowHeight / 2;

  double get _spacing => MiuixTabRowDefaults.tabRowItemSpacing;

  /// 复刻 flutter_miuix 1.3.0 `_calculateTabWidth`（库内私有）。
  ///
  /// 库不暴露单项矩形，hover/按压的命中判定必须自算，故此处镜像同一算法；
  /// 算法随库版本变化时会漂移，升级 flutter_miuix 后需复核本函数。
  double _tabWidth(double available) {
    final count = widget.tabs.length;
    final minWidth = widget.minWidth ?? MiuixTabRowDefaults.tabRowMinWidth;
    final maxWidth = widget.maxWidth ?? MiuixTabRowDefaults.tabRowMaxWidth;
    if (count == 0) return minWidth;
    final totalSpacing = count > 1 ? (count - 1) * _spacing : 0.0;
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
  int? _hitIndex(Offset local, double width) {
    final count = widget.tabs.length;
    if (count == 0) return null;
    final pad = widget.panelPadding;
    final available = math.max(0.0, width - pad.horizontal);
    final tabWidth = _tabWidth(available);
    final pitch = tabWidth + _spacing;
    final x = local.dx - pad.left + (_scroll.hasClients ? _scroll.offset : 0.0);
    if (x < 0) return null;
    final index = (x / pitch).floor();
    if (index < 0 || index >= count) return null;
    if (x - index * pitch > tabWidth) return null;
    return index;
  }

  void _onHover(Offset local, double width) {
    final index = _hitIndex(local, width);
    if (index == _hoverIndex) return;
    setState(() => _hoverIndex = index);
  }

  void _onPointerDown(Offset local, double width) {
    final index = _hitIndex(local, width);
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
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
          return Listener(
            // 仅做视觉反馈，不参与手势竞技：点击仍由库内 onTabSelected 处理。
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) => _onPointerDown(event.localPosition, width),
            onPointerUp: (_) => _clearPress(),
            onPointerCancel: (_) => _clearPress(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onHover: (event) => _onHover(event.localPosition, width),
              onExit: (_) => _clearHover(),
              child: AnimatedScale(
                scale: _pressIndex == null ? 1.0 : _sinkAmount,
                duration: _sinkDuration,
                curve: Curves.easeOut,
                child: _buildSurface(context, width),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSurface(BuildContext context, double width) {
    final tokens = AppThemeHost.of(context);
    final pad = widget.panelPadding;
    final rowHeight = _rowHeight;
    final count = widget.tabs.length;
    final selected = count == 0 ? 0 : widget.controller.index.clamp(0, count - 1);
    // 高亮层常驻（透明度切换）以获得淡入淡出；按压优先于 hover。
    final highlightIndex = _pressIndex ?? _hoverIndex ?? selected;
    final highlightAlpha = _pressIndex != null
        ? _pressAlpha
        : (_hoverIndex != null ? _hoverAlpha : 0.0);

    final available = math.max(0.0, width - pad.horizontal);
    final tabWidth = _tabWidth(available);
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;

    final content = Stack(
      children: [
        Positioned(
          left: pad.left + highlightIndex * (tabWidth + _spacing) - offset,
          top: pad.top,
          width: tabWidth,
          height: rowHeight,
          child: AnimatedContainer(
            duration: _feedbackDuration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: tokens.colors.onSurface.withValues(alpha: highlightAlpha),
              borderRadius: BorderRadius.circular(_pillRadius),
            ),
          ),
        ),
        Padding(padding: pad, child: _buildRow(context, rowHeight)),
      ],
    );

    if (!widget.blurBackground) {
      return SizedBox(height: widget.preferredHeight, child: content);
    }

    // 毛玻璃面板：复用与 MiuixOverlayPanel 同材质的共享件，面板底由它承担，
    // 库内底色已在 [_buildRow] 改透明（否则会盖住模糊层）。
    return SizedBox(
      height: widget.preferredHeight,
      child: MiuixFrostedSurface(
        borderRadius: _panelRadius,
        blurSigma: widget.blurSigma,
        outline: widget.outline,
        child: content,
      ),
    );
  }

  Widget _buildRow(BuildContext context, double rowHeight) {
    final count = widget.tabs.length;
    final baseColors = widget.colors ?? MiuixTabRowDefaults.defaultColors(context);
    final theme = MiuixTheme.of(context);
    return MiuixTheme(
      // 库未暴露开关：未选中标签项由 `_InsetSquircleBorderPainter` 画 1px
      // insetsquircle 描边，颜色取 `MiuixTheme.colors.outline`。本项目标签条不要
      // 逐格方框（实机反馈：像每格一个额外容器，并连成整行上下细线），故在局部
      // 主题覆盖里把 outline 置透明；只影响本子树，不动全局主题与库。
      data: theme.copyWith(
        colors: theme.colors.copy(outline: AppColors.transparent),
      ),
      child: MiuixTabRow(
        tabs: widget.tabs,
        selectedTabIndex: count == 0 ? 0 : widget.controller.index.clamp(0, count - 1),
        onTabSelected: widget.controller.animateTo,
        // 库内条底色恒置透明：自绘面板时由毛玻璃承担材质，不自绘面板时透出宿主
        // 背景（如空间页按钮行的通栏毛玻璃带）；否则库的 `ColoredBox` 不透明底
        // 会盖住模糊层。
        colors: MiuixTabRowColors(
          backgroundColor: AppColors.transparent,
          contentColor: baseColors.contentColor,
          selectedBackgroundColor: baseColors.selectedBackgroundColor,
          selectedContentColor: baseColors.selectedContentColor,
        ),
        minWidth: widget.minWidth ?? MiuixTabRowDefaults.tabRowMinWidth,
        maxWidth: widget.maxWidth ?? MiuixTabRowDefaults.tabRowMaxWidth,
        height: rowHeight,
        cornerRadius: _pillRadius,
        contentAlignment: widget.contentAlignment ?? Alignment.center,
        scrollController: _scroll,
      ),
    );
  }
}

/// Tab 主体内容：[PageView] 的薄封装，与 [AppTabBar] 共享 [controller]。
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
    return PageView(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      children: widget.children,
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
