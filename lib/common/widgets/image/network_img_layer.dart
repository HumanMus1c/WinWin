import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/image_utils.dart';

/// A cached network image layer with fade animation, rounded corners and a
/// gray placeholder. [type] can be 'emote', 'avatar' or 'default'.
///
/// Phase 7.5.4 增强：
/// - [heroTag]：非空时用 [Hero] 包裹图像，用于视频卡片→详情页转场。
/// - 渐变占位：placeholder 由纯色升级为 surfaceVariant→outlineVariant 渐变。
class NetworkImgLayer extends StatelessWidget {
  const NetworkImgLayer({
    super.key,
    required this.src,
    required this.width,
    required this.height,
    this.type = 'default',
    this.borderRadius = const BorderRadius.all(Radius.circular(Style.radiusMd)),
    this.fit = BoxFit.cover,
    this.fadeInDuration = const Duration(milliseconds: 120),
    this.fadeOutDuration = const Duration(milliseconds: 120),
    this.heroTag,
  });

  final String? src;
  final double width;
  final double height;
  final String type;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  /// Hero 共享元素 tag（非空时启用）。视频卡片与详情页需使用相同 tag。
  /// 通常用 `'cover_$bvid'` 形式确保唯一。
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final isEmote = type == 'emote';
    final isAvatar = type == 'avatar';
    if (src?.isNotEmpty == true) {
      final child = _buildImage(context);
      Widget clipped;
      if (isEmote) {
        clipped = child;
      } else if (isAvatar) {
        clipped = ClipOval(child: child);
      } else {
        clipped = ClipRRect(borderRadius: borderRadius, child: child);
      }
      // Hero 包裹：仅当 heroTag 非空且非 emote/avatar 类型时启用
      if (heroTag != null && !isEmote && !isAvatar) {
        return Hero(tag: heroTag!, child: clipped);
      }
      return clipped;
    }
    return _placeholder(context, isAvatar: isAvatar);
  }

  Widget _buildImage(BuildContext context) {
    int? memCacheWidth, memCacheHeight;
    // 仅对有限尺寸计算 memCache 尺寸；double.infinity（如 Stack/AspectRatio 撑满
    // 场景）会导致 (inf * dpr).round() 抛 "Infinity or NaN toInt"。
    if (width.isFinite && height.isFinite) {
      if (width <= height) {
        memCacheWidth = ImageUtils.cacheSize(width, context);
      } else {
        memCacheHeight = ImageUtils.cacheSize(height, context);
      }
    }
    return CachedNetworkImage(
      imageUrl: ImageUtils.thumbnailUrl(src),
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fit: fit,
      fadeOutDuration: fadeOutDuration,
      fadeInDuration: fadeInDuration,
      filterQuality: FilterQuality.low,
      placeholder: (context, url) => _placeholder(context),
      errorWidget: (context, url, error) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context, {bool isAvatar = false}) {
    final cs = Theme.of(context).colorScheme;
    // 渐变占位：从 surfaceVariant 到 outlineVariant，比纯色更有层次
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: isAvatar ? BoxShape.circle : BoxShape.rectangle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHighest.withValues(alpha: 0.6),
            cs.outlineVariant.withValues(alpha: 0.4),
          ],
        ),
        borderRadius: isAvatar ? null : borderRadius,
      ),
    );
  }
}
