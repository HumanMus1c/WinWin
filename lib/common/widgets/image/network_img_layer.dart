import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// A cached network image layer with fast fade animation, rounded corners and a
/// gray placeholder. [type] can be 'emote', 'avatar' or 'default'.
///
/// 流畅度优化：
/// - 接入 [ImageUtils.thumbnailUrl] 边缘智能裁切，杜绝 4K 原图下载与全分辨率解码。
/// - 优化 [fadeInDuration] 为短平快过渡，消除滚动时大量并发 Ticker 动画。
/// - 保证 [memCacheWidth] / [memCacheHeight] 在无限尺寸时仍有安全上限。
class NetworkImgLayer extends StatelessWidget {
  const NetworkImgLayer({
    super.key,
    required this.src,
    required this.width,
    required this.height,
    this.type = 'default',
    this.borderRadius = const BorderRadius.all(Radius.circular(Style.radiusMd)),
    this.fit = BoxFit.cover,
    this.fadeInDuration = const Duration(milliseconds: 50),
    this.fadeOutDuration = Duration.zero,
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
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final isAvatar = type == 'avatar';
    // 演示模式：直接输出占位（灰块/灰圆），不构建图片、不发起加载。
    return ValueListenableBuilder<bool>(
      valueListenable: Pref.demoModeNotifier,
      builder: (context, demo, _) {
        if (demo) return _placeholder(context, isAvatar: isAvatar);
        return _buildImageLayer(context);
      },
    );
  }

  Widget _buildImageLayer(BuildContext context) {
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
    int? reqWidth, reqHeight;

    if (width.isFinite && height.isFinite && width > 0 && height > 0) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final pWidth = (width * dpr).round().clamp(64, 1080);
      final pHeight = (height * dpr).round().clamp(64, 1080);
      if (width <= height) {
        memCacheWidth = pWidth;
      } else {
        memCacheHeight = pHeight;
      }
      reqWidth = pWidth;
      reqHeight = pHeight;
    } else {
      // 兜底安全边界（避免 double.infinity 导致加载无限制超大图）
      if (type == 'avatar') {
        memCacheWidth = 120;
        memCacheHeight = 120;
      } else if (type == 'emote') {
        memCacheWidth = 64;
        memCacheHeight = 64;
      } else if (type == 'background') {
        memCacheWidth = 1280;
      } else {
        memCacheWidth = 480;
      }
    }

    final targetUrl = ImageUtils.thumbnailUrl(
      src,
      width: reqWidth,
      height: reqHeight,
      type: type,
    );

    return CachedNetworkImage(
      imageUrl: targetUrl,
      width: width,
      height: height,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fit: fit,
      fadeOutDuration: fadeOutDuration,
      fadeInDuration: fadeInDuration,
      filterQuality: FilterQuality.low,
      useOldImageOnUrlChange: true,
      placeholder: (context, url) => _placeholder(context, isAvatar: type == 'avatar'),
      errorBuilder: (context, error, stackTrace) => _placeholder(context, isAvatar: type == 'avatar'),
    );
  }

  Widget _placeholder(BuildContext context, {bool isAvatar = false}) {
    final cs = AppThemeHost.of(context).colors;
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
