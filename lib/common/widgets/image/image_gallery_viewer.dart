import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 弹出多图画廊全屏浏览弹窗。
///
/// [imageUrls] 为要浏览的图片 URL 列表。
/// [initialIndex] 为初始展示的图片索引（从 0 开始）。
void showImageGallery(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
}) {
  if (imageUrls.isEmpty) return;
  final validIndex = initialIndex.clamp(0, imageUrls.length - 1);
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      pageBuilder: (context, _, _) => ImageGalleryViewer(
        imageUrls: imageUrls,
        initialIndex: validIndex,
      ),
      transitionsBuilder: (context, animation, _, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

/// 多图画廊全屏查看组件（对标 PiliPlus GalleryViewer）。
///
/// 特性：
/// - 支持鼠标滚轮/手势缩放与平移（[InteractiveViewer]）；
/// - 支持多图左右滑动与切换；
/// - 桌面端快捷键：左右方向键翻页，Esc 键快速关闭；
/// - 桌面端悬浮半透明左右翻页按钮；
/// - 顶部显示当前图片序号与复制图片链接功能。
class ImageGalleryViewer extends StatefulWidget {
  const ImageGalleryViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<ImageGalleryViewer> {
  late final PageController _pageController;
  late int _currentIndex;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _pageController.dispose();
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
  String _getRawUrl(String url) {
    String cleanUrl = url.replaceFirst('http://', 'https://');
    final atIndex = cleanUrl.indexOf('@');
    if (atIndex != -1) {
      cleanUrl = cleanUrl.substring(0, atIndex);
    }
    return cleanUrl;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 点击空白背景区域退出
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),

            // 图片 PageView
            PageView.builder(
              controller: _pageController,
              itemCount: total,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                final url = _getRawUrl(widget.imageUrls[index]);
                return Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 6.0,
                    clipBehavior: Clip.none,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      placeholder: (context, _) => const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white70,
                          ),
                        ),
                      ),
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
                );
              },
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
                    icon: const Icon(Icons.chevron_right, size: 28),
                    tooltip: '下一张 (→)',
                  ),
                ),
              ),

            // 顶部导航栏（图片序号指示器、复制、关闭）
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
                      // 复制图片链接
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.4),
                          foregroundColor: Colors.white,
                          hoverColor: Colors.black.withValues(alpha: 0.6),
                        ),
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: '复制图片链接',
                        onPressed: () {
                          final curUrl = _getRawUrl(widget.imageUrls[_currentIndex]);
                          Clipboard.setData(ClipboardData(text: curUrl));
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(
                              content: Text('已复制图片链接到剪贴板'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // 关闭按钮
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.4),
                          foregroundColor: Colors.white,
                          hoverColor: Colors.black.withValues(alpha: 0.6),
                        ),
                        icon: const Icon(Icons.close, size: 20),
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
      ),
    );
  }
}
