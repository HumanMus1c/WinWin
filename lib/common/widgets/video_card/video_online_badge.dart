import 'package:flutter/widgets.dart';

import 'package:winwin/common/widgets/p_badge.dart';
import 'package:winwin/core/demo/demo_overrides.dart';
import 'package:winwin/services/video_online_service.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/app_icons.dart';

/// 封面左上角「XX人正在看」角标。
///
/// 只有设置「显示在线人数」开启时才挂载；数据按 bvid+cid 懒加载并缓存，
/// 无数据时返回空组件，不占布局。
class VideoOnlineBadge extends StatefulWidget {
  const VideoOnlineBadge({
    super.key,
    required this.aid,
    required this.cid,
    this.bvid,
    this.demo = false,
    this.seed,
  });

  final int aid;
  final int? cid;
  final String? bvid;
  final bool demo;
  final String? seed;

  @override
  State<VideoOnlineBadge> createState() => _VideoOnlineBadgeState();
}

class _VideoOnlineBadgeState extends State<VideoOnlineBadge> {
  String? _text;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VideoOnlineBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aid != widget.aid ||
        oldWidget.cid != widget.cid ||
        oldWidget.bvid != widget.bvid) {
      _load();
    }
  }

  void _load() {
    if (widget.demo) {
      _text = '${DemoOverrides.count(
        'demo.online.${widget.seed ?? widget.bvid ?? widget.aid}',
        min: 100,
        max: 9999,
      )}';
      return;
    }
    final cached = VideoOnlineService.cached(
      aid: widget.aid,
      cid: widget.cid,
      bvid: widget.bvid,
    );
    if (cached != null) {
      _text = cached;
      return;
    }
    _text = null;
    VideoOnlineService.fetch(
      aid: widget.aid,
      cid: widget.cid,
      bvid: widget.bvid,
    ).then((text) {
      if (!mounted || text == null || text.isEmpty) return;
      setState(() => _text = text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return POverlayBadge(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(AppIcons.people(), size: 11, color: AppColors.white),
          const SizedBox(width: 3),
          Text(
            '$text人正在看',
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.white,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
