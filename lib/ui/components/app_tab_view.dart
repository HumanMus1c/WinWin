import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart'
    show MiuixTabRow, MiuixTabRowColors, MiuixTabRowDefaults;

/// WinWin 通用 Tab 体系（Miuix 轨道），取代 Material 的
/// [TabBar] + [TabBarView] + [TabController] 三元组。
///
/// 拆成两个可独立落位的部件，均由同一 [AppTabController] 驱动：
/// - [AppTabBar]：头部标签栏（flutter_miuix [MiuixTabRow]，胶囊选中指示 +
///   squircle 描边，超出宽度自动横向滚动居中选中项）；
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

/// Tab 头部标签栏：flutter_miuix [MiuixTabRow] 的薄封装。
///
/// 与 [AppTabBody] 共享 [controller]；点击项经 [AppTabController.animateTo]
/// 驱动主体切页。可落在 `AppScaffold.topBar` 或 `SliverPersistentHeader` 中。
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

  /// 头部实际高度（含覆盖值），供 Sliver 委托等需要固定 extent 的场景使用。
  double get preferredHeight => height ?? MiuixTabRowDefaults.tabRowHeight;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final count = tabs.length;
        return MiuixTabRow(
          tabs: tabs,
          selectedTabIndex: count == 0 ? 0 : controller.index.clamp(0, count - 1),
          onTabSelected: controller.animateTo,
          colors: colors,
          minWidth: minWidth ?? MiuixTabRowDefaults.tabRowMinWidth,
          maxWidth: maxWidth ?? MiuixTabRowDefaults.tabRowMaxWidth,
          height: height ?? MiuixTabRowDefaults.tabRowHeight,
          contentAlignment: contentAlignment ?? Alignment.center,
        );
      },
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

/// [AppTabBar] + [AppTabBody] 的纵向组合，适用于头体直接上下并列的场景
/// （如侧栏、对话框内）。头体落在不同槽位时改用两个部件分别落位。
class AppTabView extends StatelessWidget {
  const AppTabView({
    super.key,
    required this.controller,
    required this.tabs,
    required this.children,
    this.barHeight,
    this.colors,
  });

  final AppTabController controller;
  final List<String> tabs;
  final List<Widget> children;
  final double? barHeight;
  final MiuixTabRowColors? colors;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppTabBar(
          controller: controller,
          tabs: tabs,
          height: barHeight,
          colors: colors,
        ),
        Expanded(
          child: AppTabBody(controller: controller, children: children),
        ),
      ],
    );
  }
}
