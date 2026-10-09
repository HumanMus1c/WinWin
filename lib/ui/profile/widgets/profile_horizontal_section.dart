import 'dart:ui';

import 'package:flutter_miuix/miuix.dart' show MiuixIconButton, MiuixPressable;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 个人页各内容分区的统一标题行（对齐 PiliPlus `ListTile` 标题规范）。
class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.onTapTitle,
    this.onRefresh,
    this.isRefreshing = false,
  });

  final String title;
  final int? count;
  final VoidCallback? onTapTitle;
  final VoidCallback? onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: MiuixPressable(
              onPressed: onTapTitle,
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: tokens.text.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '$count',
                        style: tokens.text.titleSmall?.copyWith(
                          color: biliPink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(width: 4),
                    AppIcon(AppIcons.chevronForward(),
                      size: 14,
                      color: cs.outline,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onRefresh != null)
            MiuixIconButton(

              onPressed: isRefreshing ? null : onRefresh,

              child: Tooltip(message: '刷新$title', child: isRefreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: biliPink,
                      ),
                    )
                  : AppIcon(AppIcons.refresh(), size: 20)),
            ),
        ],
      ),
    );
  }
}

/// 支持桌面端鼠标按住拖拽滑动的横向滚动列表容器。
class ProfileHorizontalList extends StatelessWidget {
  const ProfileHorizontalList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onMore,
    this.hasMore = false,
    this.height = 180,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onMore;
  final bool hasMore;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final totalCount = itemCount + (hasMore && onMore != null ? 1 : 0);

    return SizedBox(
      height: height,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: totalCount,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            if (hasMore && onMore != null && index == itemCount) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Center(
                  child: MiuixIconButton(
                    minWidth: 42,
                    minHeight: 42,
                    backgroundColor: cs.secondaryContainer.withValues(alpha: 0.6),
                    onPressed: onMore,
                    child: Tooltip(
                      message: '查看更多',
                      child: AppIcon(AppIcons.chevronForward(), size: 18, color: biliPink),
                    ),
                  ),
                ),
              );
            }
            return itemBuilder(context, index);
          },
        ),
      ),
    );
  }
}

/// 横向卡片骨架屏（加载中占位）。
class ProfileCardSkeleton extends StatelessWidget {
  const ProfileCardSkeleton({super.key, this.height = 180});

  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final radius = shapes.medium;

    return SizedBox(
      height: height,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.all(radius),
                  child: Container(
                    width: 160,
                    height: 160 * 9 / 16,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 130,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 80,
                  height: 12,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 空态或未登录态占位卡片。
class ProfileEmptyCard extends StatelessWidget {
  const ProfileEmptyCard({
    super.key,
    required this.icon,
    required this.message,
    this.actionText,
    this.onTap,
  });

  final Widget icon;
  final String message;
  final String? actionText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;

    return SizedBox(
      height: 120,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: MiuixPressable(
          onPressed: onTap,
          borderRadius: BorderRadius.all(shapes.medium),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.all(shapes.medium),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
              color: cs.surfaceContainerLow.withValues(alpha: 0.3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(size: 28, color: cs.outline),
                  child: icon,
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: tokens.text.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (actionText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        actionText!,
                        style: tokens.text.labelMedium?.copyWith(
                          color: biliPink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 收藏夹横向展示卡片（高度还原 PiliPlus `FavFolderItem` 的双层折叠阴影）。
class ProfileFavFolderCard extends StatelessWidget {
  const ProfileFavFolderCard({
    super.key,
    required this.title,
    required this.cover,
    required this.count,
    required this.isPublic,
    required this.onTap,
    this.heroTag,
  });

  final String title;
  final String cover;
  final int count;
  final bool isPublic;
  final VoidCallback onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final radius = shapes.medium;

    return MiuixPressable(
      onPressed: onTap,
      borderRadius: BorderRadius.all(radius),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(radius),
                boxShadow: [
                  BoxShadow(
                    color: cs.onInverseSurface.withValues(alpha: 0.4),
                    offset: const Offset(4, -6),
                    blurRadius: 0.0,
                    spreadRadius: 0.0,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.all(radius),
                child: SizedBox(
                  width: 160,
                  height: 160 * 9 / 16,
                  child: cover.isNotEmpty
                      ? NetworkImgLayer(
                          src: cover,
                          width: 160,
                          height: 160 * 9 / 16,
                          heroTag: heroTag,
                        )
                      : Container(
                          color: cs.secondaryContainer.withValues(alpha: 0.4),
                          child: AppIcon(
                            isPublic ? AppIcons.folder() : AppIcons.lock(),
                            size: 32,
                            color: biliPink,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '共$count条视频 · ${isPublic ? '公开' : '私密'}',
              style: tokens.text.labelSmall?.copyWith(
                color: cs.outline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 视频横向展示卡片（用于历史记录、稍后再看、离线缓存）。
class ProfileVideoCard extends StatelessWidget {
  const ProfileVideoCard({
    super.key,
    required this.title,
    required this.cover,
    this.author,
    this.durationBadge,
    this.progressFraction,
    this.subtitle,
    required this.onTap,
    this.heroTag,
  });

  final String title;
  final String cover;
  final String? author;
  final String? durationBadge;
  final double? progressFraction;
  final String? subtitle;
  final VoidCallback onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;
    final radius = shapes.medium;

    return MiuixPressable(
      onPressed: onTap,
      borderRadius: BorderRadius.all(radius),
      child: SizedBox(
        width: 160,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面与角标/进度条
            ClipRRect(
              borderRadius: BorderRadius.all(radius),
              child: SizedBox(
                width: 160,
                height: 160 * 9 / 16,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: NetworkImgLayer(
                        src: cover,
                        width: 160,
                        height: 160 * 9 / 16,
                        heroTag: heroTag,
                      ),
                    ),
                    if (durationBadge != null && durationBadge!.isNotEmpty)
                      Positioned(
                        right: 4,
                        bottom: (progressFraction != null && progressFraction! > 0) ? 7 : 4,
                        child: PBadge(
                          text: durationBadge!,
                          type: PBadgeType.duration,
                        ),
                      ),
                    if (progressFraction != null && progressFraction! > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progressFraction!.clamp(0.0, 1.0),
                          minHeight: 3,
                          backgroundColor: AppColors.black26,
                          valueColor: const AlwaysStoppedAnimation<Color>(biliPink),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // 标题
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tokens.text.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 2),
            // UP主 / 副标题
            Text(
              subtitle ?? author ?? '',
              style: tokens.text.labelSmall?.copyWith(
                color: cs.outline,
                fontSize: 10.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
