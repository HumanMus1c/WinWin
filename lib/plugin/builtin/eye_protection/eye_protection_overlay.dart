import 'package:flutter/widgets.dart';

import 'eye_protection_plugin.dart';
import 'eye_protection_policy.dart';

/// 护眼叠色层：覆盖整个 Flutter 内容区（含 Navigator 与弹层），
/// 通过 [IgnorePointer] 保证不拦截任何鼠标/键盘事件。
class EyeProtectionOverlay extends StatelessWidget {
  const EyeProtectionOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EyeProtectionVisual?>(
      valueListenable: EyeProtectionPlugin.visualNotifier,
      builder: (context, visual, child) {
        if (visual == null || visual.isTransparent) return child!;
        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0xFFFFB266)
                      .withValues(alpha: visual.warmth),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0xFF000000)
                      .withValues(alpha: visual.dim),
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
