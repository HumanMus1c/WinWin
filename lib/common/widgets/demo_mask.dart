import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/skeleton/skeleton.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/theme/style.dart';

/// 演示模式内容遮罩：演示开启时整块替换为 [skeleton]。
///
/// 用法：
/// ```dart
/// DemoMask(
///   skeleton: () => _buildSkeleton(),
///   child: () => switch (state) { ... },
/// )
/// ```
/// 演示模式下无论页面处于 Loading / Success / Error，均显示骨架
/// （统一观感，不泄露内容与错误信息）；关闭后立即按当前状态恢复真实内容。
class DemoMask extends StatelessWidget {
  const DemoMask({super.key, required this.skeleton, required this.child});

  /// 演示模式下显示的内容（通常为该页现有骨架屏）。
  final Widget Function() skeleton;

  /// 正常状态下显示的内容。
  final Widget Function() child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Pref.demoModeNotifier,
      builder: (context, demo, _) => demo ? skeleton() : child(),
    );
  }
}

/// 演示模式播放器遮罩：覆盖真实画面（视频帧 / 弹幕 / 直播画面）。
///
/// 纯视觉覆盖层：`IgnorePointer` 不拦截交互，不暂停、不改变播放状态；
/// 使用不透明渐变色块，保证截图不含任何真实画面。
class DemoVideoOverlay extends StatelessWidget {
  const DemoVideoOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.surfaceContainerHighest, cs.outlineVariant],
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.play_circle_outline,
          size: 56,
          color: cs.onSurfaceVariant.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

/// 演示模式：通用列表骨架（封面块 + 两行文本，近似卡片列表）。
class DemoListSkeleton extends StatelessWidget {
  const DemoListSkeleton({
    super.key,
    this.itemCount = 8,
    this.coverWidth = 150,
    this.coverHeight = 88,
  });

  final int itemCount;
  final double coverWidth;
  final double coverHeight;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(Style.safeSpace),
      itemCount: itemCount,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: Style.md),
        child: Skeleton(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: coverWidth, height: coverHeight),
              const SizedBox(width: Style.md),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(width: double.infinity, height: 13),
                    SizedBox(height: 8),
                    SkeletonLine(width: 120, height: 11),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
