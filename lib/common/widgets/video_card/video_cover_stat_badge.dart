import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/utils/num_utils.dart';

/// 视频封面左下角统计角标（播放量 + 弹幕数）。
///
/// 样式对齐封面右下角时长角标（[PBadge] duration）：黑底半透明 + 白字；
/// 供 [VideoCardV] / [VideoCardH] 复用。
class VideoCoverStatBadge extends StatelessWidget {
  const VideoCoverStatBadge({
    super.key,
    required this.playCount,
    required this.danmakuCount,
  });

  final int? playCount;
  final int? danmakuCount;

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      fontSize: 10,
      color: AppColors.white,
      height: 1.2,
    );
    return POverlayBadge(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.viewCount(), size: 11, color: AppColors.white),
          const SizedBox(width: 3),
          Text(NumUtils.formatNum(playCount), style: style),
          const SizedBox(width: 6),
          AppIcon(AppIcons.danmakuCount(), size: 11, color: AppColors.white),
          const SizedBox(width: 3),
          Text(NumUtils.formatNum(danmakuCount), style: style),
        ],
      ),
    );
  }
}
