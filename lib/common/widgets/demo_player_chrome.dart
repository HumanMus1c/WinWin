import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/demo/demo_player_presets.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/glass_contrast_widgets.dart';
import 'package:winwin/ui/components/hover_container.dart';
import 'package:winwin/utils/duration_utils.dart';

/// 演示模式：播放器区域（灰色静态画面 + 与正常模式一致的控制栏）。
///
/// 纯本地交互：默认进入“播放中”状态，时间轴按正常模式观看历史的最小时长 /
/// 最大时长随机生成并本地走动（1 秒/步）；点击画面可切换播放/暂停。
/// **不加载任何媒体流、不播放真实视频**。
class DemoPlayerChrome extends StatefulWidget {
  const DemoPlayerChrome({super.key, this.seed = 0});

  /// 随机种子（不同页面可用不同种子生成不同时长）。
  final int seed;

  @override
  State<DemoPlayerChrome> createState() => _DemoPlayerChromeState();
}

class _DemoPlayerChromeState extends State<DemoPlayerChrome> {
  bool _playing = true;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              child: Icon(
                AppIcons.play(active: true),
                size: 56,
                color: Colors.white,
                shadows: ContrastStyle.glyphShadows,
              ),
            ),
          // 控制栏（元素集与顺序对齐正常模式 PlayerPanel._buildControlBar）。
          Align(
            alignment: Alignment.bottomCenter,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  stops: [0.0, 0.55, 1.0],
                  colors: [
                    Color(0x73000000),
                    Color(0x28000000),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 14.0, bottom: Style.xs),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 第一行：进度条（底线 + 已播进度 + 圆点，随播放走动）。
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Style.sm),
                      child: SizedBox(
                        height: 18,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: fraction,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
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
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 第二行：控制按钮行（左：播放/时间/弹幕；右：画质/倍速/字幕/功能按钮）。
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Style.sm),
                      child: Row(
                        children: [
                          _barIcon(
                            _playing
                                ? AppIcons.pause(active: true)
                                : AppIcons.play(active: true),
                            first: true,
                          ),
                          const SizedBox(width: Style.sm),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: posText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    shadows: ContrastStyle.glyphShadows,
                                  ),
                                ),
                                TextSpan(
                                  text: ' / $durText',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    shadows: ContrastStyle.glyphShadows,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: Style.md),
                          _capsule(
                            background: biliBlue.withValues(alpha: 0.28),
                            borderColor: biliBlue.withValues(alpha: 0.45),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ContrastIcon(
                                  AppIcons.danmaku(active: true),
                                  size: 16.5,
                                  color: const Color(0xFF00AEEC),
                                  shadows: ContrastStyle.glyphShadows,
                                ),
                                const SizedBox(width: Style.xs),
                                ContrastText(
                                  '开',
                                  style: const TextStyle(
                                    color: Color(0xFF00AEEC),
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
                          _plainLabel('倍速'),
                          _capsule(
                            background: Colors.black.withValues(alpha: 0.35),
                            borderColor:
                                Colors.white.withValues(alpha: 0.15),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ContrastIcon(
                                  AppIcons.subtitle(active: false),
                                  size: 16.5,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  shadows: ContrastStyle.glyphShadows,
                                ),
                                const SizedBox(width: Style.xs),
                                ContrastText(
                                  '字幕',
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  shadows: ContrastStyle.glyphShadows,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: Style.sm),
                          _barIcon(AppIcons.sendDanmaku()),
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
        ],
      ),
    );
  }

  /// 控制栏图标按钮（白色 + 高对比阴影，尺寸对齐正常模式 18px；
  /// 首个播放/暂停按钮为 20px 规格，与正常模式一致）。
  Widget _barIcon(IconData icon, {bool first = false}) {
    return Padding(
      padding: EdgeInsets.only(left: first ? 0 : Style.md),
      child: Icon(
        icon,
        size: first ? 20 : 18,
        color: Colors.white,
        shadows: ContrastStyle.glyphShadows,
      ),
    );
  }

  /// 画质 / 倍速 文本标签（对齐正常模式 HoverContainer + ContrastText）。
  Widget _plainLabel(String text) {
    return HoverContainer(
      borderRadius: 6.0,
      padding: const EdgeInsets.symmetric(
        horizontal: Style.sm,
        vertical: 6,
      ),
      hoverColor: Colors.white.withValues(alpha: 0.12),
      child: ContrastText(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontSize: 12,
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
  }) {
    return GlassCapsule(
      borderRadius: Style.radiusFull,
      blur: 8,
      padding: EdgeInsets.zero,
      backgroundColor: background,
      borderColor: borderColor,
      child: HoverContainer(
        onTap: () {},
        borderRadius: Style.radiusFull,
        padding: const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 5,
        ),
        hoverColor: Colors.white.withValues(alpha: 0.12),
        child: child,
      ),
    );
  }
}
