import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:winwin/common/widgets/image/image_gallery_viewer.dart';
import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/core/emote/emote_store.dart';
import 'package:winwin/models/video/reply_item.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/utils/bilibili_emotes.dart';
import 'package:winwin/utils/image_utils.dart';

/// 将评论正文按官方表情转义符（`[xxx]`）拆分为图文混排 Span。
///
/// 表情 URL 优先取评论接口 `content.emote` 映射（含动图 gif_url），
/// 其次回退 [EmoteStore] 官方缓存（与表情面板同源），最后回退内置对照表
/// [BilibiliEmotes.defaultEmotes]；
/// 仍未命中则保留原文。表情尺寸 = 20px × 尺寸档位（meta.size，上限 40px）。
List<InlineSpan> buildReplyEmoteSpans(
  BuildContext context,
  String text,
  Map<String, ReplyEmote>? emotes,
  TextStyle? style,
) {
  if (text.isEmpty) return const [];
  final spans = <InlineSpan>[];
  var lastEnd = 0;

  for (final match in BilibiliEmotes.emotePattern.allMatches(text)) {
    if (match.start > lastEnd) {
      spans.add(
        TextSpan(text: text.substring(lastEnd, match.start), style: style),
      );
    }
    final emoteCode = match.group(0)!;
    final emote = emotes?[emoteCode];
    final emoteUrl = emote?.displayUrl?.isNotEmpty == true
        ? emote!.displayUrl
        : (EmoteStore.instance.urlOf(emoteCode) ??
              BilibiliEmotes.getEmoteUrl(emoteCode));

    if (emoteUrl != null && emoteUrl.isNotEmpty) {
      final emoteSize = (20.0 * (emote?.size ?? 1)).clamp(20.0, 40.0);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Image.network(
              ImageUtils.thumbnailUrl(emoteUrl, type: 'emote'),
              width: emoteSize,
              height: emoteSize,
              fit: BoxFit.contain,
              cacheWidth: ImageUtils.decodeClamp(emoteSize, context, max: 128),
              cacheHeight: ImageUtils.decodeClamp(emoteSize, context, max: 128),
              errorBuilder: (_, _, _) => Text(emoteCode, style: style),
            ),
          ),
        ),
      );
    } else {
      spans.add(TextSpan(text: emoteCode, style: style));
    }
    lastEnd = match.end;
  }

  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd), style: style));
  }
  return spans;
}

/// 评论区富内容视图：正文（官方表情图文混排）+ 附带图片网格。
///
/// 图片点击进入动态页同款全屏画廊（[showImageGallery]）预览；
/// GIF 源图片按原图直连保留动画，静态图走 CDN 缩略图。
class ReplyContentView extends StatelessWidget {
  const ReplyContentView({
    super.key,
    required this.content,
    this.textStyle,
    this.maxSingleImageWidth = 380,
    this.maxSingleImageHeight = 240,
    this.cellMinWidth = 50,
    this.cellMaxWidth = 130,
  });

  final ReplyContent? content;
  final TextStyle? textStyle;

  /// 单图展示尺寸上限（会随接口 picture_scale 放大）。
  final double maxSingleImageWidth;
  final double maxSingleImageHeight;

  /// 多图单元格边长范围。
  final double cellMinWidth;
  final double cellMaxWidth;

  @override
  Widget build(BuildContext context) {
    final message = content?.message ?? '';
    final pictures = content?.pictures ?? const <ReplyPicture>[];
    if (message.isEmpty && pictures.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isNotEmpty)
          Text.rich(
            TextSpan(
              children: buildReplyEmoteSpans(
                context,
                message,
                content?.emote,
                textStyle,
              ),
            ),
            style: textStyle,
          ),
        if (pictures.isNotEmpty) ...[
          const SizedBox(height: Style.xs + 2),
          ReplyPictureGrid(
            pictures: pictures,
            pictureScale: content?.pictureScale,
            maxSingleImageWidth: maxSingleImageWidth,
            maxSingleImageHeight: maxSingleImageHeight,
            cellMinWidth: cellMinWidth,
            cellMaxWidth: cellMaxWidth,
          ),
        ],
      ],
    );
  }
}

/// 评论附带图片网格：单图按自然比例（0.5~2.0），多图九宫格（最多 9 张）。
class ReplyPictureGrid extends StatelessWidget {
  const ReplyPictureGrid({
    super.key,
    required this.pictures,
    this.pictureScale,
    this.maxSingleImageWidth = 380,
    this.maxSingleImageHeight = 240,
    this.cellMinWidth = 50,
    this.cellMaxWidth = 130,
  });

  final List<ReplyPicture> pictures;
  final double? pictureScale;
  final double maxSingleImageWidth;
  final double maxSingleImageHeight;
  final double cellMinWidth;
  final double cellMaxWidth;

  static const double _spacing = 4;

  List<String> get _galleryUrls => [
        for (final p in pictures.take(9))
          if (p.imgSrc?.isNotEmpty == true)
            p.imgSrc!.replaceFirst('http://', 'https://'),
      ];

  void _openGallery(BuildContext context, int index) {
    final urls = _galleryUrls;
    if (urls.isEmpty) return;
    showImageGallery(
      context,
      imageUrls: urls,
      thumbnailUrls: urls,
      initialIndex: index.clamp(0, urls.length - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayPics = pictures.take(9).toList();
    if (displayPics.isEmpty) return const SizedBox.shrink();
    if (displayPics.length == 1) {
      return _buildSingle(context, displayPics.first);
    }

    final crossAxisCount =
        displayPics.length == 4 ? 2 : (displayPics.length >= 3 ? 3 : 2);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 380.0;
        final rawItemWidth =
            (totalWidth - _spacing * (crossAxisCount - 1)) / crossAxisCount;
        final itemWidth = rawItemWidth.clamp(cellMinWidth, cellMaxWidth);

        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (var i = 0; i < displayPics.length; i++)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _openGallery(context, i),
                  child: _PictureCellBox(
                    pic: displayPics[i],
                    width: itemWidth,
                    height: itemWidth,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSingle(BuildContext context, ReplyPicture pic) {
    final w = pic.imgWidth ?? 16;
    final h = pic.imgHeight ?? 9;
    final aspect = (w > 0 && h > 0) ? (w / h).clamp(0.5, 2.0) : 16 / 9;
    final scale = (pictureScale ?? 1.0).clamp(0.8, 1.6);
    final maxW = maxSingleImageWidth * scale;
    final maxH = maxSingleImageHeight * scale;

    return LayoutBuilder(
      builder: (context, constraints) {
        var boxWidth = maxW;
        if (constraints.maxWidth.isFinite) {
          boxWidth = math.min(boxWidth, constraints.maxWidth);
        }
        var boxHeight = boxWidth / aspect;
        if (boxHeight > maxH) {
          boxHeight = maxH;
          boxWidth = boxHeight * aspect;
        }
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => _openGallery(context, 0),
            child: _PictureCellBox(
              pic: pic,
              width: boxWidth,
              height: boxHeight,
            ),
          ),
        );
      },
    );
  }
}

/// 单张评论图片（含右上角角标叠加）。
class _PictureCellBox extends StatelessWidget {
  const _PictureCellBox({
    required this.pic,
    required this.width,
    required this.height,
  });

  final ReplyPicture pic;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final icon = pic.topRightIcon;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: NetworkImgLayer(
              src: pic.imgSrc,
              width: width,
              height: height,
              borderRadius: BorderRadius.circular(Style.radiusSm),
            ),
          ),
          if (icon != null && icon.isNotEmpty)
            Positioned(
              top: 4,
              right: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.network(
                  ImageUtils.thumbnailUrl(icon, width: 32),
                  height: 16,
                  fit: BoxFit.contain,
                  cacheWidth: ImageUtils.decodeClamp(32, context, max: 64),
                  cacheHeight: ImageUtils.decodeClamp(16, context, max: 64),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
