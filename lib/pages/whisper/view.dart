import 'package:flutter_miuix/miuix.dart' show MiuixHorizontalDivider;
import 'package:flutter/widgets.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/app_top_bar_surface.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/msg.dart';
import 'package:winwin/pages/whisper/msg_feed/at_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/like_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/reply_me_page.dart';
import 'package:winwin/pages/whisper/msg_feed/sys_msg_page.dart';
import 'package:winwin/pages/whisper/session/session_list_section.dart';
import 'package:winwin/services/msg_unread_service.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/hover_container.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_scaffold.dart';

/// 消息页（Phase 7.7.3）。
///
/// 参照 PiliPlus 的 `WhisperPage`：顶部 4 个 CircleAvatar 入口
/// （回复/艾特/点赞/系统），下方为未读数汇总。
/// 桌面端精简：不实现完整私信会话列表（需 IM SDK），聚焦消息中心入口。
class WhisperPage extends StatefulWidget {
  const WhisperPage({super.key});

  @override
  State<WhisperPage> createState() => _WhisperPageState();
}

class _WhisperPageState extends State<WhisperPage>
    with AutomaticKeepAliveClientMixin {
  final GlobalKey<SessionListSectionState> _sessionListKey =
      GlobalKey<SessionListSectionState>();
  LoadingState<Map<String, dynamic>> _unreadState = LoadingState.loading();
  bool _loading = false;

  /// 会话筛选类型（服务端 `session_type`）——由顶部「分类栏」选定，下传列表区。
  int _sessionType = 4;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    _load();
    // 演示模式切换时重建（未读角标与列表占位即时生效）。
    Pref.demoModeNotifier.addListener(_onDemoChanged);
  }

  void _onDemoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    AccountService().removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    if (AccountService().isLogin) {
      _load();
    } else {
      setState(() {
        _unreadState = LoadingState.loading();
      });
    }
  }

  Future<void> _load() async {
    if (!AccountService().isLogin) {
      setState(() {
        _unreadState = const Success({});
      });
      return;
    }
    if (_loading) return;
    _loading = true;
    setState(() {
      _unreadState = LoadingState.loading();
    });
    await ensureBootstrap();
    final results = await Future.wait([
      MsgHttp.msgUnread(),
      MsgUnreadService().fetchUnread(),
    ]);
    if (!mounted) return;
    final unreadRes = results[0] as LoadingState<Map<String, dynamic>>;
    setState(() {
      _unreadState = unreadRes;
    });
    _loading = false;
  }

  int get _replyUnread => MsgUnreadService().reply;
  int get _atUnread => MsgUnreadService().at;
  int get _likeUnread => MsgUnreadService().like;
  int get _sysUnread => MsgUnreadService().system;

  /// 顶部合并栏**首帧**的避让回退值（面板高度由内容自撑，首帧尚无法实测）：
  /// 面板外缩（[Style.sm]×2）+ 互动行（[Style.md]×2 + 头像 52 + 间距 6 + 标签行 ~20）
  /// + 分隔线 1 + 分类行（[SessionFilterBar] 统一 TAB 栏高 42）+ 下沿间隙 [Style.sm]。
  static const double _headerReserve =
      Style.sm * 2 + Style.md * 2 + 52 + 6 + 20 + 1 + 42 + Style.sm;

  /// 分类栏与面板下缘之间的底距：把 chips 抬出面板下缘那条「背景（空白页底 +
  /// 面板自身投影）被 σ16 模糊从下缘向内浸入」的 ~3σ 带，避免筛选项发虚。
  static const double _filterBarBottomGap = 24;

  final GlobalKey _headerKey = GlobalKey();

  /// 顶部合并栏的**实测**高度（＝会话列表的顶部避让量）。
  ///
  /// 面板高度由内容决定；用预算常量估高/估矮会让列表首行被面板遮住、或在面板
  /// 下方露出空白页底，故首帧后按实际布局回填，作为 `topInset`。
  double? _headerHeight;

  void _measureHeader() {
    final box = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || box == null || !box.hasSize) return;
    final height = box.size.height;
    if (height == _headerHeight) return;
    setState(() => _headerHeight = height);
  }

  void _selectSessionType(int type) {
    if (type == _sessionType) return;
    setState(() => _sessionType = type);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tokens = AppThemeHost.of(context);
    // 面板高度由内容自撑，用预算常量估高/估矮都会露馅：首帧后实测回填
    // （回调内 setState 仅在高度变化时触发，收敛后不再重建）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureHeader());
    // 顶部「四类互动入口 + 分类栏」合并为一个**浮动毛玻璃面板**（对齐首页
    // 「搜索框 + 分类器合并栏」）；会话列表铺满并滚到面板后方穿过 → 毛玻璃可见，
    // 列表顶部按面板实测高度避让（见 SessionListSection.topInset）。
    return AppScaffold(
      title: '消息',
      body: Stack(
        children: [
          Positioned.fill(
            // B7-c5 反馈轮：观感统一（与其它页面同款自绘紧凑环）+ 回拉不滚内容，
            // 换回 AppRefreshIndicator；处理器仍保持「不清列表」，故反馈轮#2
            // 的「居中加载环与下拉指示器叠加」不会回退。
            child: AppRefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  _load(),
                  _sessionListKey.currentState?.reload() ?? Future.value(),
                ]);
              },
              child: SessionListSection(
                key: _sessionListKey,
                sessionType: _sessionType,
                topInset: _headerHeight ?? _headerReserve,
                onRefreshUnread: () => _clearDmUnread(),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: RepaintBoundary(
              child: SizedBox(
                key: _headerKey,
                child: _buildFrostedHeader(tokens),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部浮动合并栏：互动入口行 + 分隔线 + 分类栏（合并为一个毛玻璃面板）。
  ///
  /// 材质与首页合并栏**同源**——统一走 [AppTopBarSurface]（`cs.surface` α0.72 +
  /// 模糊 20 + 外壳圆角 `chrome.containerRadius` + 外距 `lg/sm`）。此前用
  /// `MiuixFrostedSurface`（硬编码底 `0xFF262626`/`0xFFEAEAEA` × 0.85 + 模糊 16
  /// + 圆角 12），底色不随主题 `surface` 走，实机观感与本页/首页背景不和谐
  /// （CVO 反馈「顶栏背景模糊的颜色亮度未对齐程序整体背景」）。改为同一材质后
  /// 两页天然对齐。
  ///
  /// 面板背后/下缘外侧是空白页底；`AppTopBarSurface` 不含面板下投影，故此前
  /// 「面板自身 4px 下投影被 σ 模糊从下缘向内采样 → 分类栏下发白浸润带」的成因
  /// 已随材质替换消除（见 `miuix_frosted_surface.dart` 的 `shadow` 说明）。
  Widget _buildFrostedHeader(AppTokens tokens) {
    return AppTopBarSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.md,
              vertical: Style.md,
            ),
            child: _buildEntries(tokens),
          ),
          const MiuixHorizontalDivider(),
          SessionFilterBar(
            selectedType: _sessionType,
            onSelected: _selectSessionType,
          ),
          const SizedBox(height: _filterBarBottomGap),
        ],
      ),
    );
  }

  Widget _buildEntries(AppTokens tokens) {
    return ListenableBuilder(
      listenable: MsgUnreadService(),
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _EntryItem(
              icon: AppIcon(AppIcons.reply()),
              label: '回复我的',
              count: Pref.demoMode ? 0 : _replyUnread,
              color: iosBlue,
              onTap: () {
                _clearFeedUnread('reply');
                showReplyMePage(context);
              },
            ),
            _EntryItem(
              icon: AppIcon(AppIcons.atMe()),
              label: '艾特我的',
              count: Pref.demoMode ? 0 : _atUnread,
              color: iosOrange,
              onTap: () {
                _clearFeedUnread('at');
                showAtMePage(context);
              },
            ),
            _EntryItem(
              icon: AppIcon(AppIcons.like(active: true)),
              label: '点赞我的',
              count: Pref.demoMode ? 0 : _likeUnread,
              color: iosPink,
              onTap: () {
                _clearFeedUnread('like');
                showLikeMePage(context);
              },
            ),
            _EntryItem(
              icon: AppIcon(AppIcons.sysNotice()),
              label: '系统消息',
              count: Pref.demoMode ? 0 : _sysUnread,
              color: iosTeal,
              onTap: () {
                _clearFeedUnread('system');
                showSysMsgPage(context);
              },
            ),
          ],
        );
      },
    );
  }

  /// 乐观清零某类消息流未读角标（实际未读数下次刷新恢复）。
  void _clearFeedUnread(String key) {
    MsgUnreadService().clearKey(key);
  }

  /// 乐观清零私信未读角标。
  void _clearDmUnread() {
    final data = _unreadState.dataOrNull;
    if (data != null && (data['follow_unread'] as num? ?? 0) > 0) {
      setState(() => data['follow_unread'] = 0);
    }
  }
}

/// 顶部圆形入口项。
class _EntryItem extends StatelessWidget {
  const _EntryItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    // hover 反馈：以条目强调色 8% 底衬显示可点击外形（复测反馈）。
    return HoverContainer(
      onTap: onTap,
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      hoverColor: color.withValues(alpha: 0.08),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: IconTheme(
                  data: IconThemeData(color: color, size: 24),
                  child: icon,
                ),
              ),
              if (count > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: tokens.colors.error,
                      border: Border.all(color: tokens.colors.background, width: 1.5),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: tokens.text.labelMedium,
          ),
        ],
      ),
    );
  }
}
