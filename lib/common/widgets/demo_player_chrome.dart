import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/core/demo/demo_player_presets.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/glass_contrast_widgets.dart';
import 'package:winwin/ui/components/hover_container.dart';
import 'package:winwin/utils/duration_utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';

/// 演示模式：播放器区域（灰色静态画面 + 与正常模式一致的控制栏）。
///
/// 纯本地交互：默认进入“播放中”状态，时间轴按正常模式观看历史的最小时长 /
/// 最大时长随机生成并本地走动（1 秒/步）。
/// - 点击**画面区域** → 播放/暂停；
/// - 控制栏**各自按钮独立响应**（播放/暂停、弹幕开关、倍速、进度条拖动/点按跳转），
///   其余按钮为本地无副作用占位（点击不再触发暂停）。
/// **不加载任何媒体流、不播放真实视频**。
class DemoPlayerChrome extends StatefulWidget {
  const DemoPlayerChrome({super.key, this.seed = 0});

  /// 随机种子（不同页面可用不同种子生成不同时长）。
  final int seed;

  @override
  State<DemoPlayerChrome> createState() => _DemoPlayerChromeState();
}

class _DemoPlayerChromeState extends State<DemoPlayerChrome> {
  /// 倍速循环档位（对齐正常模式 speedList 常用档）。
  static const List<double> _speedSteps = [1.0, 0.75, 1.25, 1.5, 2.0];

  bool _playing = true;
  bool _danmakuOn = true;
  double _speed = 1.0;
  late Duration _total;
  late Duration _pos;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _total = Duration(seconds: DemoPlayerPresets.durationSeconds(widget.seed));
    _pos = Duration(seconds: (_total.inSeconds * 0.2).round());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // 历史时长范围就绪后，按新范围重建时间轴（best-effort）。
    unawaited(DemoPlayerPresets.ensureFetched().then((_) {
      if (!mounted) return;
      setState(() {
        _total =
            Duration(seconds: DemoPlayerPresets.durationSeconds(widget.seed));
        if (_pos >= _total) {
          _pos = Duration(seconds: (_total.inSeconds * 0.2).round());
        }
      });
    }));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted || !_playing) return;
    setState(() {
      _pos += const Duration(seconds: 1);
      if (_pos >= _total) _pos = Duration.zero;
    });
  }

  void _togglePlay() => setState(() => _playing = !_playing);

  void _toggleDanmaku() => setState(() => _danmakuOn = !_danmakuOn);

  void _cycleSpeed() {
    final i = _speedSteps.indexOf(_speed);
    setState(() => _speed = _speedSteps[(i + 1) % _speedSteps.length]);
  }

  /// 进度条点按/拖动跳转（纯本地：改演示进度，不影响任何真实播放状态）。
  void _seekTo(double dx, double width) {
    if (width <= 0 || _total.inSeconds == 0) return;
    final f = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _pos = Duration(seconds: (_total.inSeconds * f).round());
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    final fraction = _total.inSeconds == 0
        ? 0.0
        : (_pos.inSeconds / _total.inSeconds).clamp(0.0, 1.0);
    final posText = DurationUtils.formatDuration(_pos.inSeconds);
    final durText = DurationUtils.formatDuration(_total.inSeconds);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlay,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 灰色静态画面占位。
          ColoredBox(color: cs.surfaceContainerHighest),
          // 暂停时中央大播放按钮（与正常模式一致：仅暂停时显示）。
          if (!_playing)
            Center(
              child: AppIcon(
                AppIcons.play(active: true),
                size: 56,
                color: AppColors.white,
                shadows: ContrastStyle.glyphShadows,
              ),
            ),
          // 控制栏（元素集与顺序对齐正常模式 PlayerPanel._buildControlBar）。
          // 整条栏吸收点击（点击栏内空白不再触发暂停），各按钮独立响应。
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    stops: [0.0, 0.55, 1.0],
                    colors: [
                      Color(0x73000000),
                      Color(0x28000000),
                      AppColors.transparent,
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 14.0, bottom: Style.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 第一行：进度条（点按/拖动可本地跳转）。
                      _buildProgressBar(fraction),
                      // 第二行：控制按钮行（左：播放/时间/弹幕；右：画质/倍速/字幕/功能按钮）。
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Style.sm,
                        ),
                        child: Row(
                          children: [
                            _barIcon(
                              _playing
                                  ? AppIcons.pause(active: true)
                                  : AppIcons.play(active: true),
                              first: true,
                              onTap: _togglePlay,
                            ),
                            const SizedBox(width: Style.sm),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: posText,
                                    style: const TextStyle(
                                      color: AppColors.white,
                                      fontSize: 12,
                                      shadows: ContrastStyle.glyphShadows,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' / $durText',
                                    style: const TextStyle(
                                      color: AppColors.white70,
                                      fontSize: 12,
                                      shadows: ContrastStyle.glyphShadows,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Style.md),
                            _capsule(
                              background: _danmakuOn
                                  ? biliBlue.withValues(alpha: 0.28)
                                  : AppColors.black.withValues(alpha: 0.35),
                              borderColor: _danmakuOn
                                  ? biliBlue.withValues(alpha: 0.45)
                                  : AppColors.white.withValues(alpha: 0.15),
                              onTap: _toggleDanmaku,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ContrastIcon(
                                    AppIcons.danmaku(active: _danmakuOn),
                                    size: 16.5,
                                    color: _danmakuOn
                                        ? const Color(0xFF00AEEC)
                                        : AppColors.white.withValues(alpha: 0.85),
                                    shadows: ContrastStyle.glyphShadows,
                                  ),
                                  const SizedBox(width: Style.xs),
                                  ContrastText(
                                    _danmakuOn ? '开' : '关',
                                    style: TextStyle(
                                      color: _danmakuOn
                                          ? const Color(0xFF00AEEC)
                                          : AppColors.white.withValues(
                                              alpha: 0.85,
                                            ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    shadows: ContrastStyle.glyphShadows,
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            _plainLabel('1080P'),
                            _plainLabel(
                              _speed == 1.0
                                  ? '倍速'
                                  : '${_speed.toStringAsFixed(1)}x',
                              onTap: _cycleSpeed,
                              active: _speed != 1.0,
                            ),
                            _capsule(
                              background: AppColors.black.withValues(alpha: 0.35),
                              borderColor: AppColors.white.withValues(alpha: 0.15),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ContrastIcon(
                                    AppIcons.subtitle(active: false),
                                    size: 16.5,
                                    color:
                                        AppColors.white.withValues(alpha: 0.85),
                                    shadows: ContrastStyle.glyphShadows,
                                  ),
                                  const SizedBox(width: Style.xs),
                                  ContrastText(
                                    '字幕',
                                    style: TextStyle(
                                      color:
                                          AppColors.white.withValues(alpha: 0.85),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    shadows: ContrastStyle.glyphShadows,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Style.sm),
                            _barIcon(AppIcons.danmakuTune()),
                            _barIcon(AppIcons.volumeDown()),
                            _barIcon(AppIcons.lockOutline()),
                            _barIcon(AppIcons.pip()),
                            _barIcon(AppIcons.inAppFullscreen(active: false)),
                            _barIcon(AppIcons.fullscreen()),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 进度条（底线 + 已播进度 + 圆点；点按/水平拖动本地跳转）。
  Widget _buildProgressBar(double fraction) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Style.sm),
      child: SizedBox(
        height: 18,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _seekTo(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) =>
                  _seekTo(d.localPosition.dx, width),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(-1 + 2 * fraction, 0),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
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

  /// 控制栏图标按钮（白色 + 高对比阴影，尺寸对齐正常模式 18px；
  /// 首个播放/暂停按钮为 20px 规格，与正常模式一致）。
  Widget _barIcon(IconData icon, {bool first = false, VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap ?? () {},
      child: Padding(
        padding: EdgeInsets.only(left: first ? 0 : Style.md),
        child: AppIcon(
          icon,
          size: first ? 20 : 18,
          color: AppColors.white,
          shadows: ContrastStyle.glyphShadows,
        ),
      ),
    );
  }

  /// 画质 / 倍速 文本标签（对齐正常模式 HoverContainer + ContrastText）。
  Widget _plainLabel(String text, {VoidCallback? onTap, bool active = false}) {
    return HoverContainer(
      onTap: onTap ?? () {},
      borderRadius: 6.0,
      padding: const EdgeInsets.symmetric(
        horizontal: Style.sm,
        vertical: 6,
      ),
      hoverColor: AppColors.white.withValues(alpha: 0.12),
      child: ContrastText(
        text,
        style: TextStyle(
          color: active
              ? const Color(0xFF00AEEC)
              : AppColors.white.withValues(alpha: 0.85),
          fontSize: 12,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
        shadows: ContrastStyle.glyphShadows,
      ),
    );
  }

  /// 毛玻璃胶囊 chip（弹幕开关 / 字幕，风格对齐正常模式 GlassCapsule）。
  Widget _capsule({
    required Color background,
    required Color borderColor,
    required Widget child,
    VoidCallback? onTap,
  }) {
    return GlassCapsule(
      borderRadius: Style.radiusFull,
      blur: 8,
      padding: EdgeInsets.zero,
      backgroundColor: background,
      borderColor: borderColor,
      child: HoverContainer(
        onTap: onTap ?? () {},
        borderRadius: Style.radiusFull,
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 5,
        ),
        hoverColor: AppColors.white.withValues(alpha: 0.12),
        child: child,
      ),
    );
  }
}
