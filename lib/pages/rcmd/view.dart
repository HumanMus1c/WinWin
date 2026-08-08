import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:winwin/common/skeleton/video_card_v.dart';
import 'package:winwin/common/widgets/video_card/video_card_v.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/rcmd/controller.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/grid.dart';

/// Recommended videos feed — ported from PiliPlus's RcmdPage.
class RcmdPage extends StatefulWidget {
  const RcmdPage({super.key});

  @override
  State<RcmdPage> createState() => _RcmdPageState();
}

class _RcmdPageState extends State<RcmdPage>
    with AutomaticKeepAliveClientMixin {
  final RcmdController controller = Get.put(RcmdController());

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = ColorScheme.of(context);
    return Container(
      clipBehavior: Clip.hardEdge,
      margin: const EdgeInsets.symmetric(horizontal: Style.safeSpace),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(Style.mdRadius)),
      ),
      child: RefreshIndicator(
        onRefresh: controller.onRefresh,
        child: CustomScrollView(
          controller: controller.scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              // Extra top padding (120) to clear the floating top bar (52)
              // and the category tabs row (~36) rendered above in a Stack.
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

  late final gridDelegate = SliverGridDelegateWithExtentAndRatio(
    mainAxisSpacing: Style.cardSpace,
    crossAxisSpacing: Style.cardSpace,
    maxCrossAxisExtent: 240.0,
    childAspectRatio: Style.aspectRatio,
    mainAxisExtent: MediaQuery.textScalerOf(context).scale(90),
  );

  Widget _buildBody(
    ColorScheme colorScheme,
    LoadingState<List<dynamic>?> loadingState,
  ) {
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
                    // Phase 7.5.3：Hero 共享元素 tag，为详情页转场预留
                    heroTag: 'cover_${response[index].bvid}',
                    onTap: () {
                      final item = response[index];
                      // 推荐流同时可能是 App 模型或 Web 模型，二者均继承
                      // BaseRcmdVideoItemModel（含 bvid/cover）。
                      if (item is! BaseRcmdVideoItemModel) return;
                      final bvid = item.bvid;
                      if (bvid == null) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VideoDetailPage(
                            bvid: bvid,
                            cover: item.cover,
                          ),
                        ),
                      );
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

  /// Empty / error state with a reload button.
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
              errMsg ?? '没有数据',
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
}
