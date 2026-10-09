import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/log/app_logger.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/utils/image_utils.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_dialogs.dart';

/// 弹出多图画廊全屏浏览弹窗。
///
/// [imageUrls] 为要浏览的图片 URL 列表。
/// [initialIndex] 为初始展示的图片索引（从 0 开始）。
/// 弹出多图画廊全屏浏览弹窗。
///
/// [imageUrls] 为要浏览的图片 URL 列表。
/// [thumbnailUrls] 为对应的缩略图 URL 列表（可选，若提供则在原图未加载完成前以缩略图即时秒显，彻底消除开启动画掉帧与白屏）。
/// [initialIndex] 为初始展示的图片索引（从 0 开始）。
void showImageGallery(
  BuildContext context, {
  required List<String> imageUrls,
  List<String>? thumbnailUrls,
  int initialIndex = 0,
}) {
  if (imageUrls.isEmpty) return;
  final validIndex = initialIndex.clamp(0, imageUrls.length - 1);
  AppLogger.w(
    'Coverage',
    'gallery opened images=${imageUrls.length} initialIndex=$validIndex',
  );
  Navigator.of(context).push(
    _ImageGalleryRoute(
      builder: (context) => ImageGalleryViewer(
        imageUrls: imageUrls,
        thumbnailUrls: thumbnailUrls,
        initialIndex: validIndex,
      ),
    ),
  );
}

/// 图片画廊专用路由：以 [PopupRoute]（而非 PageRoute）承载。
///
/// 项目的 [RouteObserver] 类型为 `RouteObserver<PageRoute<dynamic>>`，仅当新压栈
/// 路由同为 PageRoute 时才向前一页派发 `didPushNext`。画廊改由 PopupRoute 承载后
/// 不再触发播放页的"离页暂停 / 卸载监听"逻辑，预览图片不会打断视频播放；
/// 关闭画廊时同理不触发 `didPopNext` 的重新加载与弹幕重建。
class _ImageGalleryRoute extends PopupRoute<void> {
  _ImageGalleryRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '关闭图片预览';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
      child: child,
    );
  }
}

/// 多图画廊全屏查看组件（全面对标 PiliPlus GalleryViewer 手势体验）。
///
/// 特性：
/// - **点击图片边界外关闭**：精准计算图片实际渲染尺寸，点击黑边空白区域立即关闭画廊；
/// - **触摸滑动关闭（Swipe to Dismiss）**：在未放大状态下单指上下拖拽，背景透明度平滑衰减、图片等比缩小并跟随手指，松手超阈值自动关闭，否则弹性复原；
/// - **双击放大/复原**：双击图片任意位置平滑缩放到 2.5x 并居中该坐标，再次双击还原；
/// - **双指缩放与自由平移**：支持 1.0x ~ 6.0x 自由缩放，放大后拖拽限制在图片边缘内；
/// - **长按菜单**：长按触发震动反馈，呼出保存图片到本地、复制图片直链等操作菜单；
/// - **桌面端全能快捷控制**：支持鼠标滚轮缩放、左右方向键翻页、Esc 键退出及左右悬浮箭头。
class ImageGalleryViewer extends StatefulWidget {
  const ImageGalleryViewer({
    super.key,
    required this.imageUrls,
    this.thumbnailUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final List<String>? thumbnailUrls;
  final int initialIndex;

  /// 剥除 B站 CDN 缩略图后缀，获取原始高清大图 URL。
  static String getRawUrl(String url) => _ImageGalleryViewerState.getRawUrl(url);

  @override
  State<ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _GalleryDragState {
  final Offset offset;
  final double progress;
  const _GalleryDragState(this.offset, this.progress);
  static const zero = _GalleryDragState(Offset.zero, 0.0);
}

class _ImageGalleryViewerState extends State<ImageGalleryViewer>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late int _currentIndex;
  final FocusNode _focusNode = FocusNode();

  bool _isZoomed = false;

  // 滑动关闭手势状态（基于 ValueNotifier，拖拽时无需触发 setState 导致整树高频重构）
  final ValueNotifier<_GalleryDragState> _dragNotifier =
      ValueNotifier<_GalleryDragState>(_GalleryDragState.zero);
  bool _isDismissDragging = false;
  late final AnimationController _resetAnimController;
  Animation<Offset>? _offsetResetAnimation;
  Animation<double>? _progressResetAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _resetAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        final offset = _offsetResetAnimation?.value ?? Offset.zero;
        final progress = _progressResetAnimation?.value ?? 0.0;
        _dragNotifier.value = _GalleryDragState(offset, progress);
      });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    AppLogger.w('Coverage', 'gallery closed at index=$_currentIndex');
    _focusNode.dispose();
    _pageController.dispose();
    _dragNotifier.dispose();
    _resetAnimController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentIndex < widget.imageUrls.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _prevPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _prevPage();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _nextPage();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// 剥除 B站 CDN 缩略图后缀，获取原始高清大图 URL。
  static String getRawUrl(String url) {
    String cleanUrl = url.replaceFirst('http://', 'https://');
    final atIndex = cleanUrl.indexOf('@');
    if (atIndex != -1) {
      cleanUrl = cleanUrl.substring(0, atIndex);
    }
    return cleanUrl;
  }

  // ── 滑动关闭（Swipe-to-Dismiss）手势处理 ──

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isZoomed) return;
    _resetAnimController.stop();
    _isDismissDragging = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenHeight) {
    if (!_isDismissDragging || _isZoomed) return;
    final currentOffset = _dragNotifier.value.offset + details.delta;
    final progress =
        (currentOffset.dy.abs() / (screenHeight * 0.7)).clamp(0.0, 1.0);
    _dragNotifier.value = _GalleryDragState(currentOffset, progress);
  }

  void _onVerticalDragEnd(DragEndDetails details, double screenHeight) {
    if (!_isDismissDragging || _isZoomed) return;
    _isDismissDragging = false;

    final velocity = details.primaryVelocity ?? 0.0;
    final currentOffset = _dragNotifier.value.offset;
    final currentProgress = _dragNotifier.value.progress;
    final shouldDismiss = currentProgress > 0.18 || velocity.abs() > 500;

    if (shouldDismiss) {
      Navigator.of(context).pop();
    } else {
      // 弹性复原动画
      _offsetResetAnimation = Tween<Offset>(
        begin: currentOffset,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _resetAnimController,
        curve: Curves.easeOutCubic,
      ));
      _progressResetAnimation = Tween<double>(
        begin: currentProgress,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _resetAnimController,
        curve: Curves.easeOutCubic,
      ));
      _resetAnimController.forward(from: 0.0);
    }
  }

  Future<void> _saveImage(BuildContext context, String rawUrl) async {
    try {
      final res = await Request().get<List<int>>(
        rawUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('下载图片数据为空');
      }

      final fileName = 'bilibili_img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final fileUri = await FilePicker.saveFile(
        dialogTitle: '保存图片到本地',
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        type: FileType.image,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (fileUri == null) return;

      final savedPath = fileUri.isScheme('file')
          ? fileUri.toFilePath()
          : fileUri.toString();

      if (context.mounted) {
        showToast(
          context,
          '图片已成功保存至 $savedPath',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          '保存图片失败：$e',
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  void _showActionMenu(BuildContext context, String rawUrl) {
    HapticFeedback.mediumImpact();
    showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = AppThemeHost.of(ctx).colors;
        return Container(
          decoration: BoxDecoration(
            color: cs.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: AppIcon(AppIcons.download()),
                  title: const Text('保存图片到本地'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _saveImage(context, rawUrl);
                  },
                ),
                ListTile(
                  leading: Icon(AppIcons.copy()),
                  title: const Text('复制图片直链'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Clipboard.setData(ClipboardData(text: rawUrl));
                    showToast(
                      context,
                      '已复制图片直链到剪贴板',
                      duration: const Duration(seconds: 1),
                    );
                  },
                ),
                ListTile(
                  leading: AppIcon(AppIcons.clear()),
                  title: const Text('关闭预览'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).pop();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;
    final screenSize = MediaQuery.sizeOf(context);

    // 核心 PageView 画廊组件，作为 child 透传给 ValueListenableBuilder，手势拖拽时不发生任何重建
    final galleryPageView = PageView.builder(
      controller: _pageController,
      itemCount: total,
      physics: _isZoomed
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
          _isZoomed = false;
        });
      },
      itemBuilder: (context, index) {
        final rawUrl = getRawUrl(widget.imageUrls[index]);
        final thumbUrl = widget.thumbnailUrls != null &&
                index < widget.thumbnailUrls!.length
            ? widget.thumbnailUrls![index]
            : widget.imageUrls[index];

        return _GalleryItemView(
          key: ValueKey(rawUrl),
          rawUrl: rawUrl,
          thumbnailUrl: thumbUrl,
          onZoomChanged: (zoomed) {
            if (_isZoomed != zoomed) {
              setState(() => _isZoomed = zoomed);
            }
          },
          onTapOutside: () => Navigator.of(context).pop(),
          onLongPress: () => _showActionMenu(context, rawUrl),
        );
      },
    );

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: ValueListenableBuilder<_GalleryDragState>(
          valueListenable: _dragNotifier,
          child: galleryPageView,
          builder: (context, dragState, child) {
            final bgAlpha =
                (0.92 * (1.0 - dragState.progress)).clamp(0.0, 0.92);
            final dismissScale =
                (1.0 - dragState.progress * 0.35).clamp(0.5, 1.0);

            return Container(
              color: Colors.black.withValues(alpha: bgAlpha),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 核心手势与图片画廊
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: _onVerticalDragStart,
                    onVerticalDragUpdate: (d) =>
                        _onVerticalDragUpdate(d, screenSize.height),
                    onVerticalDragEnd: (d) =>
                        _onVerticalDragEnd(d, screenSize.height),
                    child: Transform.translate(
                      offset: dragState.offset,
                      child: Transform.scale(
                        scale: dismissScale,
                        child: child,
                      ),
                    ),
                  ),

              // 桌面端左翻页箭头
              if (total > 1 && _currentIndex > 0)
                Positioned(
                  left: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        hoverColor: Colors.black.withValues(alpha: 0.75),
                        padding: const EdgeInsets.all(12),
                      ),
                      onPressed: _prevPage,
                      icon: const Icon(Icons.chevron_left, size: 28),
                      tooltip: '上一张 (←)',
                    ),
                  ),
                ),

              // 桌面端右翻页箭头
              if (total > 1 && _currentIndex < total - 1)
                Positioned(
                  right: 24,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        hoverColor: Colors.black.withValues(alpha: 0.75),
                        padding: const EdgeInsets.all(12),
                      ),
                      onPressed: _nextPage,
                      icon: AppIcon(AppIcons.chevronForward(), size: 28),
                      tooltip: '下一张 (→)',
                    ),
                  ),
                ),

              // 顶部导航栏（图片序号指示器、保存、复制、关闭）
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        // 序号指示器
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / $total',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // 保存到本地
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.4),
                            foregroundColor: Colors.white,
                            hoverColor: Colors.black.withValues(alpha: 0.6),
                          ),
                          icon: AppIcon(AppIcons.download(), size: 18),
                          tooltip: '保存图片',
                          onPressed: () {
                            final curUrl =
                                getRawUrl(widget.imageUrls[_currentIndex]);
                            _saveImage(context, curUrl);
                          },
                        ),
                        const SizedBox(width: 8),
                        // 复制图片链接
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.4),
                            foregroundColor: Colors.white,
                            hoverColor: Colors.black.withValues(alpha: 0.6),
                          ),
                          icon: Icon(AppIcons.copy(), size: 18),
                          tooltip: '复制图片链接',
                          onPressed: () {
                            final curUrl =
                                getRawUrl(widget.imageUrls[_currentIndex]);
                            Clipboard.setData(ClipboardData(text: curUrl));
                            showToast(
                              context,
                              '已复制图片链接到剪贴板',
                              duration: const Duration(seconds: 1),
                            );
                          },
                        ),
                        const SizedBox(width: 8),
                        // 关闭按钮
                        IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.4),
                            foregroundColor: Colors.white,
                            hoverColor: Colors.black.withValues(alpha: 0.6),
                          ),
                          icon: AppIcon(AppIcons.clear(), size: 20),
                          tooltip: '关闭 (Esc)',
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ],
            ),
          );
          },
        ),
      ),
    );
  }
}

/// 单张图片的交互展示层。
///
/// 包含图片固有尺寸解析、双击平滑缩放、双指多点触控与边界外点击识别。
class _GalleryItemView extends StatefulWidget {
  const _GalleryItemView({
    super.key,
    required this.rawUrl,
    this.thumbnailUrl,
    required this.onZoomChanged,
    required this.onTapOutside,
    required this.onLongPress,
  });

  final String rawUrl;
  final String? thumbnailUrl;
  final ValueChanged<bool> onZoomChanged;
  final VoidCallback onTapOutside;
  final VoidCallback onLongPress;

  @override
  State<_GalleryItemView> createState() => _GalleryItemViewState();
}

class _GalleryItemViewState extends State<_GalleryItemView>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformController;
  late final AnimationController _zoomAnimController;
  Animation<Matrix4>? _zoomAnimation;

  Size? _intrinsicImageSize;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController()
      ..addListener(_onTransformUpdated);

    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        if (_zoomAnimation != null) {
          _transformController.value = _zoomAnimation!.value;
        }
      });

    _resolveImageDimensions();
  }

  void _resolveImageDimensions() {
    // 优先从已缓存的缩略图解析比例与尺寸，秒级完成并确保点击图片外退出逻辑精准无误
    final resolveUrl =
        (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
            ? widget.thumbnailUrl!
            : widget.rawUrl;

    // 尺寸探测只需比例：限制解码尺寸，避免为解析尺寸而整图解码（等比缩放不影响比例）。
    final provider = CachedNetworkImageProvider(
      resolveUrl,
      maxWidth: 256,
      maxHeight: 256,
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (mounted) {
          setState(() {
            _intrinsicImageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );
          });
        }
        stream.removeListener(listener);
      },
      onError: (_, _) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformUpdated);
    _transformController.dispose();
    _zoomAnimController.dispose();
    super.dispose();
  }

  void _onTransformUpdated() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = currentScale > 1.05;
    if (zoomed != _isZoomed) {
      _isZoomed = zoomed;
      widget.onZoomChanged(zoomed);
    }
  }

  void _handleDoubleTap(TapDownDetails details) {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final Matrix4 endMatrix;

    if (currentScale > 1.1) {
      // 当前处于放大状态，双击复原
      endMatrix = Matrix4.identity();
    } else {
      // 双击放大至 2.5 倍，并以双击点击处为中心
      const targetScale = 2.5;
      final tapPos = details.localPosition;
      final x = -tapPos.dx * (targetScale - 1);
      final y = -tapPos.dy * (targetScale - 1);

      // ignore: deprecated_member_use
      endMatrix = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(x, y)
        // ignore: deprecated_member_use
        ..scale(targetScale);
    }

    _zoomAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _zoomAnimController,
      curve: Curves.easeInOutCubic,
    ));

    _zoomAnimController.forward(from: 0.0);
  }

  /// 计算在 BoxFit.contain 下图片在屏幕上的实际绘制 Rect
  Rect _calculateRenderedImageRect(Size containerSize) {
    if (_intrinsicImageSize == null ||
        _intrinsicImageSize!.width <= 0 ||
        _intrinsicImageSize!.height <= 0) {
      return Rect.fromLTWH(0, 0, containerSize.width, containerSize.height);
    }

    final fittedSize = applyBoxFit(
      BoxFit.contain,
      _intrinsicImageSize!,
      containerSize,
    ).destination;

    final left = (containerSize.width - fittedSize.width) / 2;
    final top = (containerSize.height - fittedSize.height) / 2;
    return Rect.fromLTWH(left, top, fittedSize.width, fittedSize.height);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        final renderedRect = _calculateRenderedImageRect(containerSize);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: _handleDoubleTap,
          onDoubleTap: () {}, // 占位激活 onDoubleTapDown
          onLongPress: widget.onLongPress,
          onSecondaryTapUp: (_) => widget.onLongPress(),
          onTapUp: (details) {
            // 精确判断是否点击在图片实际显示区域以外（仅图片外黑边点击关闭）
            if (!_isZoomed && !renderedRect.contains(details.localPosition)) {
              widget.onTapOutside();
            }
          },
          child: Center(
            child: InteractiveViewer(
              transformationController: _transformController,
              minScale: 1.0,
              maxScale: 6.0,
              panEnabled: _isZoomed,
              scaleEnabled: true,
              clipBehavior: Clip.none,
              child: CachedNetworkImage(
                imageUrl: widget.rawUrl,
                fit: BoxFit.contain,
                // 全屏大图按屏幕尺寸限制解码（而非原图），并为 6× 放大保留余量。
                memCacheWidth: ImageUtils.decodeClamp(
                    containerSize.width, context,
                    max: 2048),
                memCacheHeight: ImageUtils.decodeClamp(
                    containerSize.height, context,
                    max: 2048),
                fadeInDuration: const Duration(milliseconds: 180),
                fadeOutDuration: Duration.zero,
                placeholder: (context, _) {
                  if (widget.thumbnailUrl != null &&
                      widget.thumbnailUrl!.isNotEmpty &&
                      widget.thumbnailUrl != widget.rawUrl) {
                    return CachedNetworkImage(
                      imageUrl: widget.thumbnailUrl!,
                      fit: BoxFit.contain,
                      memCacheWidth: ImageUtils.decodeClamp(
                          containerSize.width, context,
                          max: 1080),
                      memCacheHeight: ImageUtils.decodeClamp(
                          containerSize.height, context,
                          max: 1080),
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      placeholder: (context, _) => const SizedBox.shrink(),
                      errorBuilder: (context, _, _) => const Center(
                        child: SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    );
                  }
                  return const Center(
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, _, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.broken_image_outlined,
                      size: 56,
                      color: Colors.white54,
                    ),
                    SizedBox(height: 12),
                    Text(
                      '图片加载失败',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
