import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/image_utils.dart';

/// A cached network image layer with fade animation, rounded corners and a
/// gray placeholder. [type] can be 'emote', 'avatar' or 'default'.
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
  });

  final String? src;
  final double width;
  final double height;
  final String type;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  @override
  Widget build(BuildContext context) {
    final isEmote = type == 'emote';
    final isAvatar = type == 'avatar';
    if (src?.isNotEmpty == true) {
      final child = _buildImage(context);
      if (isEmote) {
        return child;
      } else if (isAvatar) {
        return ClipOval(child: child);
      } else {
        return ClipRRect(borderRadius: borderRadius, child: child);
      }
    }
    return _placeholder(context, isAvatar: isAvatar);
  }

  Widget _buildImage(BuildContext context) {
    int? memCacheWidth, memCacheHeight;
    if (width <= height) {
      memCacheWidth = ImageUtils.cacheSize(width, context);
    } else {
      memCacheHeight = ImageUtils.cacheSize(height, context);
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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: isAvatar ? BoxShape.circle : BoxShape.rectangle,
        color: Theme.of(
          context,
        ).colorScheme.onInverseSurface.withValues(alpha: 0.4),
        borderRadius: isAvatar ? null : borderRadius,
      ),
    );
  }
}
