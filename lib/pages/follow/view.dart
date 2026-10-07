import 'package:material_ui/material_ui.dart';
import 'package:get/get.dart';
import 'package:winwin/common/skeleton/video_card_v.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/common/widgets/video_card/video_card_v.dart';
import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/follow/controller.dart';
import 'package:winwin/pages/login/login_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/theme/app_icons.dart';

/// 关注动态视频流页（移植自 PiliPlus 关注动态流）。
///
/// 调用 `/x/polymer/web-dynamic/v1/feed/all`（type='video'），offset 游标分页。
/// 需要登录态：未登录时渲染登录引导卡片，登录后展示关注 UP 主的视频动态。
/// 复用 [VideoCardV] 网格，与推荐流/热门流保持一致的卡片与详情页 Hero 转场。
class FollowPage extends StatefulWidget {
  const FollowPage({super.key});

  @override
  State<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends State<FollowPage>
    with AutomaticKeepAliveClientMixin {
  final FollowController controller = Get.put(FollowController());

  @override
  bool get wantKeepAlive => true;

  /// 演示模式：本地生成的演示卡片数量（向下滚动每次追加"一行"）。
  int _demoCount = 12;

  /// 演示模式：上次追加行的滚动位置（需继续滚动约半屏后才再追加）。
  double _demoLastAppendAt = double.negativeInfinity;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    Pref.demoModeNotifier.addListener(_onDemoChanged);
    controller.scrollController.addListener(_onDemoScroll);
  }

  @override
  void dispose() {
    controller.scrollController.removeListener(_onDemoScroll);
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
    AccountService().removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onDemoChanged() {
    if (!mounted) return;
    setState(() {});
    if (!Pref.demoMode && controller.loadingState.value is Loading) {
      controller.onRefresh();
    }
  }

  /// 演示模式滚动追加：到达底部且再滚动约半屏后，追加"一行"本地卡片。
  void _onDemoScroll() {
    if (!Pref.demoMode) return;
    final sc = controller.scrollController;
    if (!sc.hasClients || !sc.position.hasContentDimensions) return;
    final pos = sc.position;
    if (pos.pixels < pos.maxScrollExtent - 240) return;
    if (pos.pixels <= _demoLastAppendAt + pos.viewportDimension * 0.5) {
      return;
    }
    _demoLastAppendAt = pos.pixels;
    final perRow = (pos.viewportDimension / 250).floor().clamp(2, 8);
    setState(() => _demoCount += perRow);
  }

  void _onAccountChanged() {
    if (!mounted) return;
    // 登录态变化时刷新：登录后拉取关注流，登出后重置。
    if (AccountService().isLogin) {
      controller.onRefresh();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 登录态守卫：未登录时展示登录引导。
    if (!AccountService().isLogin) {
      return Padding(
        padding: const EdgeInsets.only(top: 120),
        child: _buildLoginPrompt(context),
      );
    }
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
      child: RefreshIndicator(
        onRefresh: controller.onRefresh,
        child: CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              // 顶部留白避开浮动顶栏(52) + 分类标签行(36)
              padding: const EdgeInsets.only(top: 120, bottom: 100),
              sliver: Obx(
                () => _buildBody(colorScheme, controller.loadingState.value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  late final gridDelegate = Grid.videoCardVDelegate(
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
  );

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<dynamic>?> loadingState,
  ) {
    // 演示模式：完全使用本地生成的卡片（滚动追加一行，不拉取云端）。
    if (Pref.demoMode) return _buildDemoGrid();
    return switch (loadingState) {
      Loading() => _buildSkeleton,
      Success(:final response) =>
        response != null && response.isNotEmpty
            ? SliverGrid.builder(
                gridDelegate: gridDelegate,
                itemBuilder: (context, index) {
                  if (index == response.length - 1) {
                    controller.onLoadMore();
                  }
                  return VideoCardV(
                    videoItem: response[index],
                    heroTag: 'follow_${response[index].bvid}',
                    onTap: () {
                      final item = response[index];
                      if (item is! BaseRcmdVideoItemModel) return;
                      final bvid = item.bvid;
                      if (bvid == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoDetailPage(
                            bvid: bvid,
                            cover: item.cover,
                            heroTag: 'follow_$bvid',
                          ),
                        ),
                      );
                    },
                  );
                },
                itemCount: response.length,
              )
            : _buildEmpty(colorScheme),
      Error(:final errMsg) => _buildError(colorScheme, errMsg),
    };
  }

  Widget get _buildSkeleton => SliverGrid.builder(
    gridDelegate: gridDelegate,
    itemBuilder: (context, index) => const VideoCardVSkeleton(),
    itemCount: 10,
  );

  /// 演示模式：本地生成卡片网格（滚动追加见 [_onDemoScroll]）。
  Widget _buildDemoGrid() {
    return SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemCount: _demoCount,
      itemBuilder: (context, index) => DemoVideoCard(
        seed: index,
        onTap: () => _openDemoDetail(context, index),
      ),
    );
  }

  void _openDemoDetail(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoDetailPage(bvid: 'BV1demo$index'),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme colorScheme) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.subscriptions_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '关注的主还没发动态',
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme colorScheme, [String? errMsg]) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              errMsg ?? '加载失败',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: controller.onReload,
            child: const Text('点击重试'),
          ),
        ],
      ),
    );
  }

  /// 未登录引导卡片。
  Widget _buildLoginPrompt(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.profile(),
            size: 56,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '登录后查看关注动态',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => showLoginPage(context),
            icon: const Icon(Icons.login),
            label: const Text('登录'),
          ),
        ],
      ),
    );
  }
}
