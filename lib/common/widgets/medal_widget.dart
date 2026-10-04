import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/ui_style.dart';

/// 粉丝勋章徽章组件（对齐 B 站官方与自适应设计系统）。
///
/// 遵循 [UiStyle] 自适应规范：
/// - **Material 3**：[AppShapes.tinyBorder] 微倒角，0 扩散阴影，双色块自然拼合；
/// - **Miuix**：全圆角胶囊形态，0 阴影纯扁平，药丸级紧凑布局。
class MedalWidget extends StatelessWidget {
  const MedalWidget({
    super.key,
    required this.medalName,
    required this.level,
    required this.backgroundColor,
    this.nameColor = Colors.white,
    this.fontSize = 10.0,
    this.onTap,
  });

  final String medalName;
  final int level;
  final Color backgroundColor;
  final Color nameColor;
  final double fontSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shapes = theme.extension<AppShapes>() ?? AppShapes.material3;

    // 阶段5d-L1：M3 分支已移除，恒为全圆角胶囊。
    final outerRadius = shapes.pillBorder;
    final innerRadius = shapes.pillBorder;

    Widget child = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 1.5,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: outerRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            medalName,
            strutStyle: StrutStyle(
              height: 1,
              leading: 0,
              fontSize: fontSize,
            ),
            style: TextStyle(
              fontSize: fontSize,
              height: 1,
              color: nameColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: innerRadius,
            ),
            child: Text(
              '$level',
              strutStyle: StrutStyle(
                height: 1,
                leading: 0,
                fontSize: fontSize - 1,
                fontWeight: FontWeight.bold,
              ),
              style: TextStyle(
                fontSize: fontSize - 1,
                height: 1,
                color: backgroundColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      // 阶段5d-L1：M3 分支已移除；点按反馈为原生 MiuixPressable（扁平按压）。
      return MiuixPressable(onPressed: onTap, child: child);
    }
    return child;
  }
}

