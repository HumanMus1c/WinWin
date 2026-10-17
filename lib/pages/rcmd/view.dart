import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:winwin/common/widgets/app_scroll_bar.dart';
import 'package:winwin/common/widgets/refresh_indicator.dart';
import 'package:winwin/common/skeleton/video_card_v.dart';
import 'package:winwin/common/widgets/demo_mask.dart';
import 'package:winwin/common/widgets/video_card/video_card_v.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/rcmd/controller.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/grid.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:flutter_miuix/miuix.dart';

/// Recommended videos feed — ported from PiliPlus's RcmdPage.
class RcmdPage extends StatefulWidget {
  const RcmdPage({super.key});

  @override
  State<RcmdPage> createState() => _RcmdPageState();
}

class _RcmdPageState extends State<RcmdPage>
    with AutomaticKeepAliveClientMixin {
  final RcmdController controller = Get.put(RcmdController());

  /// 演示模式：本地生成的演示卡片数量（向下滚动每次追加"一行"）。
  int _demoCount = 12;

  /// 演示模式：上次追加行的滚动位置（需继续滚动约半屏后才再追加）。
  double _demoLastAppendAt = double.negativeInfinity;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    Pref.demoModeNotifier.addListener(_onDemoChanged);
    controller.scrollController.addListener(_onDemoScroll);
  }

  @override
  void dispose() {
    controller.scrollController.removeListener(_onDemoScroll);
    Pref.demoModeNotifier.removeListener(_onDemoChanged);
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = AppThemeHost.of(context).colors;
    return AppScrollBar(
      controller: controller.scrollController,
      child: AppRefreshIndicator(
        // 实机反馈#5：指示器出现在可见滚动区域顶部（浮动组合控件下方，页内预留 120）。
        displacement: 12,
        edgeOffset: 120,
        strokeWidth: 2.5,
        onRefresh: controller.onRefresh,
        child: CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              // Extra top padding (120) to clear the floating top bar (52)
              // and the category tabs row (~36) rendered above in a Stack.
              padding: const EdgeInsets.fromLTRB(Style.safeSpace, 120, Style.safeSpace, 100),
              sliver: Obx(
                () => _buildBody(colorScheme, controller.loadingState.value),
              ),
            ),
          ],
        ),
      ),
    );
  }

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: 240.0,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
  );

  Widget _buildBody(
    AppPalette colorScheme,
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
                    heroTag: 'rcmd_${response[index].bvid}',
                    onTap: () {
                      final item = response[index];
                      // 推荐流同时可能是 App 模型或 Web 模型，二者均继承
                      // BaseRcmdVideoItemModel（含 bvid/cover）。
                      if (item is! BaseRcmdVideoItemModel) return;
                      final bvid = item.bvid;
                      if (bvid == null) return;
                      Navigator.push(
                        context,
                        AppRoute(
                          builder: (_) => VideoDetailPage(
                            bvid: bvid,
                            cover: item.cover,
                            heroTag: 'rcmd_$bvid',
                          ),
                        ),
                      );
                    },
                    onRemove: () {
                      if (controller.loadingState.value case Success(:final response)) {
                        if (response != null && index < response.length) {
                          response.removeAt(index);
                          controller.loadingState.refresh();
                        }
                      }
                    },
                  );
                },
                itemCount: response.length,
              )
            : _buildError(colorScheme),
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
      AppRoute(
        builder: (_) => VideoDetailPage(bvid: 'BV1demo$index'),
      ),
    );
  }

  /// Empty / error state with a reload button.
  Widget _buildError(AppPalette colorScheme, [String? errMsg]) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(
            AppIcons.loadFailed(),
            size: 48,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              errMsg ?? '没有数据',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          MiuixButton(onPressed: controller.onReload, child: const Text('点击重试')),
        ],
      ),
    );
  }
}
