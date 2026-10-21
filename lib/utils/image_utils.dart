import 'package:flutter/widgets.dart';

/// Image utilities — Bilibili CDN thumbnail URL handling and cache sizing.
abstract final class ImageUtils {

  /// 根据目标尺寸与类型构建 Bilibili CDN 缩略图 URL。
  ///
  /// 支持 @{width}w_{height}h_1c.webp 格式，直接利用 B站 CDN 边缘节点进行等比缩放裁切与 WebP 压缩，
  /// 将单图体积从 2MB~5MB 原图骤降至 15KB~30KB，极大降低内存占用与网络/解码延迟。
  static String thumbnailUrl(
    String? src, {
    int? width,
    int? height,
    int quality = 80,
    String? type,
  }) {
    if (src == null || src.isEmpty) return '';
    String url = src.replaceFirst('http://', 'https://');
    // 协议相对 URL（`//host/path`，B 站搜索接口的直播/专栏/番剧封面即此形态）：
    // 必须补齐 https scheme，否则无 scheme 的 URL 交给 CachedNetworkImage 会抛
    // `No host specified in URI` 导致封面加载失败。此处作为唯一收口点兜底。
    if (url.startsWith('//')) url = 'https:$url';

    // 如果已有 @ 格式的 CDN 参数，直接返回 https 链接
    if (url.contains('@')) return url;

    // GIF 动图保持原样直连：B站 CDN 的 @…webp 转码会将其转为静态首帧，丢失动画
    final path = url.split('?').first.toLowerCase();
    if (path.endsWith('.gif')) return url;

    // 非 B站图片 CDN 域名（如部分外链）不附加规则
    if (!url.contains('.hdslb.com')) return url;

    // 1. 头像类型（120x120 裁切）
    if (type == 'avatar') {
      return '$url@120w_120h_1c.webp';
    }

    // 2. 表情包类型（64x64）
    if (type == 'emote') {
      return '$url@64w_64h_1c.webp';
    }

    // 3. 背景大图类型（降低分辨率至 1280w WebP，兼顾网络加载速度、低内存与大屏视觉质感）
    if (type == 'background') {
      return '$url@1280w.webp';
    }

    // 4. 明确指定了宽高（如 16:9/16:10 卡片封面）
    if (width != null && height != null && width > 0 && height > 0) {
      return '$url@${width}w_${height}h_1c.webp';
    } else if (width != null && width > 0) {
      return '$url@${width}w.webp';
    } else if (height != null && height > 0) {
      return '$url@${height}h.webp';
    }

    // 4. 默认卡片封面缩略图规格（480x300，16:10 裁切，WebP 格式）
    return '$url@480w_300h_1c.webp';
  }

  /// Converts a logical size to a physical pixel size for image
  /// decoding/caching, based on the device pixel ratio.
  static int cacheSize(double px, BuildContext context) {
    return (px * MediaQuery.devicePixelRatioOf(context)).round();
  }

  /// 图片解码尺寸上限（对齐 NetworkImgLayer 策略）：显示尺寸 × DPR，clamp 到 [64, max]。
  ///
  /// 就地补全裸用 CachedNetworkImage/Image 的点时使用，防止原图（可达 1000+px）
  /// 按原始分辨率解码造成大量内存占用（参见 2026-09-27 启动期高内存复盘）。
  static int decodeClamp(double px, BuildContext context, {int max = 1080}) {
    return cacheSize(px, context).clamp(64, max);
  }
}
