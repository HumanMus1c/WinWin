import 'package:flutter/material.dart';

import 'package:winwin/theme/style.dart';

/// 粉丝勋章徽章组件（对齐 B 站官方与 PiliPlus 视觉样式）。
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
    Widget child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(Style.radiusXs),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
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
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0.5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(Style.radiusXs - 1),
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
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Style.radiusXs),
        child: child,
      );
    }
    return child;
  }
}
