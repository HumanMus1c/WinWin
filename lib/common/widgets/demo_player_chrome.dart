import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'package:winwin/common/widgets/miuix_overlay_panel.dart';
import 'package:winwin/common/widgets/miuix_popup_menu.dart';
import 'package:winwin/core/demo/demo_player_presets.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_anchored_popup.dart';
import 'package:winwin/ui/components/app_tooltip.dart';
import 'package:winwin/ui/components/glass_contrast_widgets.dart';
import 'package:winwin/ui/components/hover_container.dart';
import 'package:winwin/utils/duration_utils.dart';

/// 演示模式音量滑条轨道粗细范围（越小越细、越大越粗），对齐正常模式口径。
const double _kDemoVolumeBarMinHeight = 14;
const double _kDemoVolumeBarMaxHeight = 28;

/// 演示模式：播放器区域（灰色静态画面 + 与正常模式 **1:1** 对齐的控制栏 + 二级弹层）。
///
/// 纯本地状态：**不加载任何媒体流**，也**不实例化** `WinWinPlayerController`
/// （其构造即拉起共享 mdk 播放器 / 轮询 / 弹幕初始化，属真实副作用），
/// 因此控制栏在此**逐元素复刻**正常模式 `PlayerPanel._buildControlBar`：
/// - 左：播放/暂停（20px 规格）→ 间隔 → 时间（当前白 / 总时长降饱和）→ 间隔 → 弹幕开关 chip；
/// - 右：音频编码标签 → 画质 → 倍速 → 章节 chip → 字幕 chip → 间隔 → 弹幕设置 /
///   音量 / 锁定 / 画中画 / 网页全屏 / 全屏；
/// - 图标按钮统一 `PlayerPanel._PlayerBarIconButton` 规格（18px + 30px 命中区 +
///   hover 白 0.12 背景 + 默认色 white@0.82 → hover 纯白 + tooltip）。
///
/// 二级弹层（对齐正常模式"就近对角展开"范式，互斥展开）：
/// - 画质 / 倍速 / 音频设置 → `MiuixPopupMenu` 毛玻璃菜单；
/// - 音量 → `MiuixAnchoredPopup` + `MiuixOverlayPanel` + `MiuixSlider`（本地音量，
///   轨道粗细随音量实时变化）；
/// - 弹幕设置 / 字幕设置 → `MiuixAnchoredPopup` + `MiuixOverlayPanel`（**本地态**：
///   仅改演示内存状态，**不写 `Pref`**，避免污染真实用户设置）；
/// - 章节 → 右侧滑出毛玻璃面板（点击章节本地跳转，点击面板外关闭）。
///
/// 交互：点击**画面区域**播放/暂停；控制栏内各按钮独立响应；其余按钮为本地
/// 无副作用占位（点击不再触发暂停）。
class DemoPlayerChrome extends StatefulWidget {
  const DemoPlayerChrome({super.key, this.seed = 0});

  /// 随机种子（不同页面可用不同种子生成不同时长）。
  final int seed;

  @override
  State<DemoPlayerChrome> createState() => _DemoPlayerChromeState();
}

class _DemoPlayerChromeState extends State<DemoPlayerChrome> {
  /// 倍速档位（对齐正常模式 speedList 常用档）。
  static const List<double> _speedSteps = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  /// 画质档位。
  static const List<String> _qualitySteps = [
    '自动',
    '1080P 高码率',
    '1080P',
    '720P',
    '480P',
    '360P',
  ];

  /// 演示音轨（本地占位）。
  static const List<String> _audioTrackSteps = ['默认音轨', '国语', '日语'];

  bool _playing = true;
  bool _danmakuOn = true;
  double _speed = 1.0;
  int _qualityIndex = 2; // 默认 1080P。
  static const String _audioCodec = 'AAC';
  int _audioTrackIndex = 0;
  String _audioNorm = '0';
  double _volume = 60;
  bool _locked = false;
  bool _inAppFullscreen = false;
  bool _subtitleOn = false;

  // 本地态设置（不写 Pref）。
  double _dmOpacity = 1.0;
  double _dmFontScale = 1.0;
  double _dmArea = 0.8;
  bool _dmMerge = true;
  double _subFontScale = 1.0;
  double _subBgOpacity = 0.6;
  double _subStroke = 1.0;

  // 弹层互斥展开状态。
  bool _volumePopupOpen = false;
  bool _danmakuPanelOpen = false;
  bool _subtitlePanelOpen = false;
  bool _chapterPanelOpen = false;

  final GlobalKey _volumeKey = GlobalKey();
  final GlobalKey _danmakuKey = GlobalKey();
  final GlobalKey _subtitleKey = GlobalKey();

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

  /// 进度条点按/拖动跳转（纯本地：改演示进度，不影响任何真实播放状态）。
  void _seekTo(double dx, double width) {
    if (width <= 0 || _total.inSeconds == 0) return;
    final f = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _pos = Duration(seconds: (_total.inSeconds * f).round());
    });
  }

  void _closeAnchored() {
    setState(() {
      _volumePopupOpen = false;
      _danmakuPanelOpen = false;
      _subtitlePanelOpen = false;
    });
  }

  /// 弹出某个贴触发器浮层（互斥：自动收起其余浮层）。
  void _openExclusive({bool volume = false, bool danmaku = false, bool subtitle = false, bool chapter = false}) {
    setState(() {
      _volumePopupOpen = volume;
      _danmakuPanelOpen = danmaku;
      _subtitlePanelOpen = subtitle;
      _chapterPanelOpen = chapter;
    });
  }

  /// 取触发器在**本 Stack 坐标系**中的矩形（供贴触发器浮层定位）。
  Rect? _anchorOf(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return null;
    return anchorRectOf(ctx, ancestorContext: context);
  }

  /// 演示章节：按总时长均分生成（本地占位，不请求真实看点数据）。
  List<_DemoChapter> _demoChapters() {
    final total = _total.inSeconds;
    if (total <= 0) return const [];
    const titles = ['开场 OP', '正片 A 段', '正片 B 段', '片尾 ED'];
    const fractions = [0.0, 0.25, 0.55, 0.85];
    return [
      for (int i = 0; i < titles.length; i++)
        _DemoChapter(
          title: titles[i],
          start: Duration(seconds: (total * fractions[i]).round()),
        ),
    ];
  }

  int _currentChapterIndex(List<_DemoChapter> chapters) {
    var idx = 0;
    for (int i = 0; i < chapters.length; i++) {
      if (_pos >= chapters[i].start) idx = i;
    }
    return idx;
  }

  String get _volumeLabel {
    final rounded = _volume.round();
    return rounded > 100 ? '$rounded% (增益)' : '$rounded%';
  }

  @override
  Widget build(BuildContext context) {
    final cs = AppThemeHost.of(context).colors;
    final fraction = _total.inSeconds == 0
        ? 0.0
        : (_pos.inSeconds / _total.inSeconds).clamp(0.0, 1.0);
    final chapters = _demoChapters();
    final anchoredOpen =
        _volumePopupOpen || _danmakuPanelOpen || _subtitlePanelOpen;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 灰色静态画面占位（点击画面播放/暂停）。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          child: ColoredBox(color: cs.surfaceContainerHighest),
        ),
        // 暂停时中央大播放按钮（与正常模式一致：仅暂停时显示）。
        if (!_playing)
          IgnorePointer(
            child: Center(
              child: AppIcon(
                AppIcons.play(active: true),
                size: 56,
                color: AppColors.white,
                shadows: ContrastStyle.glyphShadows,
              ),
            ),
          ),
        // 控制栏（元素集与顺序对齐正常模式 PlayerPanel._buildControlBar）。
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildControlBar(fraction, chapters),
        ),
        // 贴触发器浮层的"点击外部收起"透明遮罩（仅浮层展开时挂载）。
        if (anchoredOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeAnchored,
              child: const SizedBox.expand(),
            ),
          ),
        // 音量浮层（锚定音量按钮）。
        _buildVolumePopup(),
        // 弹幕设置浮层（锚定弹幕设置按钮）。
        _buildDanmakuSettingsPopup(),
        // 字幕设置浮层（锚定字幕 chip）。
        _buildSubtitleSettingsPopup(),
        // 章节滑出面板（最高层，自带遮罩）。
        _buildChapterPanel(chapters),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 控制栏
  // ---------------------------------------------------------------------------

  Widget _buildControlBar(double fraction, List<_DemoChapter> chapters) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // 吸收点击（点击栏内空白不再触发暂停）。
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
              // 第二行：控制按钮行（左右分区，对齐正常模式）。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Style.sm),
                child: Row(
                  children: [
                    // 左：播放/暂停 + 时间 + 弹幕开关
                    _buildPlayPauseButton(),
                    const SizedBox(width: Style.sm),
                    _buildTimeText(),
                    const SizedBox(width: Style.md),
                    _buildDanmakuChip(),
                    const Spacer(),
                    // 右：音频编码 + 画质 + 倍速 + 章节 + 字幕 + 功能按钮
                    _buildAudioCodecLabel(),
                    _buildQualityLabel(),
                    _buildSpeedLabel(),
                    _buildChapterButton(chapters),
                    _buildSubtitleChip(),
                    const SizedBox(width: Style.sm),
                    _barIconButton(
                      key: _danmakuKey,
                      icon: AppIcons.danmakuTune(),
                      tooltip: '弹幕设置',
                      onPressed: () => _openExclusive(danmaku: !_danmakuPanelOpen),
                    ),
                    _barIconButton(
                      key: _volumeKey,
                      icon: _volume <= 0
                          ? AppIcons.volumeOff()
                          : (_volume > 100
                                ? AppIcons.volumeUp()
                                : AppIcons.volumeDown()),
                      tooltip: '音量',
                      color: _volumePopupOpen ? biliBlue : null,
                      onPressed: () => _openExclusive(volume: !_volumePopupOpen),
                    ),
                    _barIconButton(
                      icon: AppIcons.lockOutline(),
                      tooltip: _locked ? '解锁控制条' : '锁定控制条',
                      color: _locked ? biliBlue : null,
                      onPressed: () => setState(() => _locked = !_locked),
                    ),
                    _barIconButton(
                      icon: AppIcons.pip(),
                      tooltip: '画中画',
                      onPressed: () {},
                    ),
                    _barIconButton(
                      icon: AppIcons.inAppFullscreen(active: _inAppFullscreen),
                      tooltip: _inAppFullscreen ? '退出网页全屏' : '网页全屏',
                      color: _inAppFullscreen ? biliBlue : null,
                      onPressed: () =>
                          setState(() => _inAppFullscreen = !_inAppFullscreen),
                    ),
                    _barIconButton(
                      icon: AppIcons.fullscreen(),
                      tooltip: '全屏',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放/暂停按钮：20px 规格（对齐正常模式 `_buildPlayPauseButton`）。
  Widget _buildPlayPauseButton() {
    return _barIconButton(
      icon: _playing
          ? AppIcons.pause(active: true)
          : AppIcons.play(active: true),
      tooltip: _playing ? '暂停' : '播放',
      size: 20.0,
      onPressed: _togglePlay,
    );
  }

  /// 时间文本（当前纯白 / 总时长降饱和，配合高对比度多向阴影）。
  Widget _buildTimeText() {
    final posText = DurationUtils.formatDuration(_pos.inSeconds);
    final durText = DurationUtils.formatDuration(_total.inSeconds);
    return Text.rich(
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
    );
  }

  /// 弹幕开关 chip（对齐正常模式 `_buildDanmakuChip`）。
  Widget _buildDanmakuChip() {
    final enabled = _danmakuOn;
    return _capsule(
      background: enabled
          ? biliBlue.withValues(alpha: 0.28)
          : AppColors.black.withValues(alpha: 0.35),
      borderColor: enabled
          ? biliBlue.withValues(alpha: 0.45)
          : AppColors.white.withValues(alpha: 0.15),
      onTap: _toggleDanmaku,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ContrastIcon(
            AppIcons.danmaku(active: enabled),
            size: 16.5,
            color: enabled
                ? const Color(0xFF00AEEC)
                : AppColors.white.withValues(alpha: 0.85),
            shadows: ContrastStyle.glyphShadows,
          ),
          const SizedBox(width: Style.xs),
          ContrastText(
            enabled ? '开' : '关',
            style: TextStyle(
              color: enabled
                  ? const Color(0xFF00AEEC)
                  : AppColors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            shadows: ContrastStyle.glyphShadows,
          ),
        ],
      ),
    );
  }

  /// 音频编码标签（对齐正常模式 `_buildAudioCodecLabel`：`MiuixPopupMenu`）。
  Widget _buildAudioCodecLabel() {
    return MiuixPopupMenu(
      entries: [
        MiuixDropdownEntry(
          items: [
            for (int i = 0; i < _audioTrackSteps.length; i++)
              MiuixDropdownItem(
                text: _audioTrackSteps[i],
                selected: i == _audioTrackIndex,
                onClick: () => setState(() => _audioTrackIndex = i),
              ),
          ],
        ),
        MiuixDropdownEntry(
          items: [
            MiuixDropdownItem(
              text: '智能响度均衡 (loudnorm)',
              selected: _audioNorm == '2',
              onClick: () => setState(() => _audioNorm = '2'),
            ),
            MiuixDropdownItem(
              text: '动态压缩 (dynaudnorm)',
              selected: _audioNorm == '1',
              onClick: () => setState(() => _audioNorm = '1'),
            ),
            MiuixDropdownItem(
              text: '禁用',
              selected: _audioNorm == '0',
              onClick: () => setState(() => _audioNorm = '0'),
            ),
          ],
        ),
      ],
      title: '音频设置',
      itemTextStyle: const TextStyle(fontSize: 12),
      child: AppTooltip(
        message: '音频设置',
        child: HoverContainer(
          borderRadius: 6.0,
          padding: const EdgeInsets.symmetric(horizontal: Style.sm, vertical: 6),
          hoverColor: AppColors.white.withValues(alpha: 0.12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ContrastText(
                _audioCodec,
                style: TextStyle(
                  color: AppColors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
                shadows: ContrastStyle.glyphShadows,
              ),
              if (_audioNorm != '0') ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: biliBlue.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(Style.radiusXs),
                  ),
                  child: const ContrastText(
                    '增强',
                    style: TextStyle(
                      color: Color(0xFF00AEEC),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                    shadows: ContrastStyle.glyphShadows,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 画质标签（对齐正常模式 `_buildQualityLabel`：`MiuixPopupMenu`）。
  Widget _buildQualityLabel() {
    return MiuixPopupMenu(
      entries: [
        MiuixDropdownEntry(
          items: [
            for (int i = 0; i < _qualitySteps.length; i++)
              MiuixDropdownItem(
                text: _qualitySteps[i],
                selected: i == _qualityIndex,
                onClick: () => setState(() => _qualityIndex = i),
              ),
          ],
        ),
      ],
      title: '画质',
      itemTextStyle: const TextStyle(fontSize: 12),
      child: AppTooltip(
        message: '画质',
        child: HoverContainer(
          borderRadius: 6.0,
          padding: const EdgeInsets.symmetric(horizontal: Style.sm, vertical: 6),
          hoverColor: AppColors.white.withValues(alpha: 0.12),
          child: ContrastText(
            _qualitySteps[_qualityIndex],
            style: TextStyle(
              color: AppColors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
            shadows: ContrastStyle.glyphShadows,
          ),
        ),
      ),
    );
  }

  /// 倍速标签（对齐正常模式 `_buildSpeedLabel`：`MiuixPopupMenu`）。
  Widget _buildSpeedLabel() {
    return MiuixPopupMenu(
      entries: [
        MiuixDropdownEntry(
          items: [
            for (final s in _speedSteps)
              MiuixDropdownItem(
                text: s == 1.0 ? '倍速' : '${s.toStringAsFixed(1)}x',
                selected: s == _speed,
                onClick: () => setState(() => _speed = s),
              ),
          ],
        ),
      ],
      title: '倍速',
      itemTextStyle: const TextStyle(fontSize: 12),
      child: AppTooltip(
        message: '倍速',
        child: HoverContainer(
          borderRadius: 6.0,
          padding: const EdgeInsets.symmetric(horizontal: Style.sm, vertical: 6),
          hoverColor: AppColors.white.withValues(alpha: 0.12),
          child: ContrastText(
            _speed == 1.0 ? '倍速' : '${_speed.toStringAsFixed(1)}x',
            style: TextStyle(
              color: _speed == 1.0
                  ? AppColors.white.withValues(alpha: 0.85)
                  : const Color(0xFF00AEEC),
              fontSize: 12,
              fontWeight: _speed == 1.0 ? FontWeight.normal : FontWeight.bold,
            ),
            shadows: ContrastStyle.glyphShadows,
          ),
        ),
      ),
    );
  }

  /// 章节 chip（对齐正常模式 `_buildChapterButton`：`GlassCapsule`）。
  Widget _buildChapterButton(List<_DemoChapter> chapters) {
    final isOpen = _chapterPanelOpen;
    return _capsule(
      background: isOpen
          ? biliBlue.withValues(alpha: 0.28)
          : AppColors.black.withValues(alpha: 0.35),
      borderColor: isOpen
          ? biliBlue.withValues(alpha: 0.45)
          : AppColors.white.withValues(alpha: 0.15),
      onTap: () => _openExclusive(chapter: !_chapterPanelOpen),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ContrastIcon(
            AppIcons.chapter(active: isOpen),
            size: 16.5,
            color: isOpen
                ? const Color(0xFF00AEEC)
                : AppColors.white.withValues(alpha: 0.85),
            shadows: ContrastStyle.glyphShadows,
          ),
          const SizedBox(width: Style.xs),
          ContrastText(
            '章节 (${chapters.length})',
            style: TextStyle(
              color: isOpen
                  ? const Color(0xFF00AEEC)
                  : AppColors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            shadows: ContrastStyle.glyphShadows,
          ),
        ],
      ),
    );
  }

  /// 字幕 chip（对齐正常模式 `_buildSubtitleChip`：`GlassCapsule`）。
  Widget _buildSubtitleChip() {
    final isActive = _subtitleOn;
    return _capsule(
      key: _subtitleKey,
      background: isActive
          ? biliBlue.withValues(alpha: 0.28)
          : AppColors.black.withValues(alpha: 0.35),
      borderColor: isActive
          ? biliBlue.withValues(alpha: 0.45)
          : AppColors.white.withValues(alpha: 0.15),
      onTap: () => _openExclusive(subtitle: !_subtitlePanelOpen),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ContrastIcon(
            AppIcons.subtitle(active: isActive),
            size: 16.5,
            color: isActive
                ? const Color(0xFF00AEEC)
                : AppColors.white.withValues(alpha: 0.85),
            shadows: ContrastStyle.glyphShadows,
          ),
          const SizedBox(width: Style.xs),
          ContrastText(
            '字幕',
            style: TextStyle(
              color: isActive
                  ? const Color(0xFF00AEEC)
                  : AppColors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            shadows: ContrastStyle.glyphShadows,
          ),
        ],
      ),
    );
  }

  /// 控制栏图标按钮（`_PlayerBarIconButton` 规格：默认 18px + 30px 命中区 +
  /// hover 白 0.12 背景 + 默认色 white@0.82 → hover 纯白 + tooltip）。
  Widget _barIconButton({
    Key? key,
    required IconData icon,
    required VoidCallback? onPressed,
    String? tooltip,
    Color? color,
    double size = 18.0,
  }) {
    return _DemoBarIconButton(
      key: key,
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      size: size,
    );
  }

  // ---------------------------------------------------------------------------
  // 进度条
  // ---------------------------------------------------------------------------

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

  // ---------------------------------------------------------------------------
  // 二级弹层
  // ---------------------------------------------------------------------------

  /// 音量浮层：`MiuixAnchoredPopup` + `MiuixOverlayPanel` + `MiuixSlider`，
  /// 轨道粗细随音量实时动态变化（对齐正常模式 `_buildVolumePopup`）。
  Widget _buildVolumePopup() {
    final anchor = _anchorOf(_volumeKey);
    if (anchor == null) return const SizedBox.shrink();
    final tokens = AppThemeHost.of(context);
    const gainColor = AppColors.orange700;
    final gain = _volume > 100;
    final activeColor = gain ? gainColor : tokens.colors.primary;
    final base = MiuixSliderDefaults.sliderColors(context);
    final t = (_volume / 100).clamp(0.0, 1.0).toDouble();
    final barHeight =
        _kDemoVolumeBarMinHeight +
        (_kDemoVolumeBarMaxHeight - _kDemoVolumeBarMinHeight) * t;
    return MiuixAnchoredPopup(
      visible: _volumePopupOpen,
      anchor: anchor,
      alignment: Alignment.bottomRight,
      child: SizedBox(
        width: 264,
        child: MiuixOverlayPanel(
          title: '音量',
          trailing: Text(
            _volumeLabel,
            maxLines: 1,
            style: TextStyle(
              color: gain ? gainColor : tokens.colors.onSurface,
              fontWeight: gain ? FontWeight.bold : FontWeight.normal,
              fontSize: 12,
            ),
          ),
          icon: AppIcon(
            _volume <= 0
                ? AppIcons.volumeOff()
                : (gain ? AppIcons.volumeUp() : AppIcons.volumeDown()),
            size: 16,
            color: gain ? gainColor : tokens.colors.primary,
          ),
          child: SizedBox(
            width: 232,
            child: MiuixSlider(
              value: _volume.clamp(0.0, 100.0).toDouble(),
              min: 0,
              max: 100,
              height: barHeight,
              colors: MiuixSliderColors(
                foregroundColor: activeColor,
                disabledForegroundColor: activeColor,
                backgroundColor: base.backgroundColor,
                disabledBackgroundColor: base.disabledBackgroundColor,
                thumbColor: activeColor,
                disabledThumbColor: activeColor,
                keyPointColor: activeColor,
                keyPointForegroundColor: activeColor,
              ),
              onValueChanged: (v) => setState(() => _volume = v),
            ),
          ),
        ),
      ),
    );
  }

  /// 弹幕设置浮层（锚定弹幕设置按钮）：**本地态**面板，不写 `Pref`。
  Widget _buildDanmakuSettingsPopup() {
    final anchor = _anchorOf(_danmakuKey);
    if (anchor == null) return const SizedBox.shrink();
    final tokens = AppThemeHost.of(context);
    return MiuixAnchoredPopup(
      visible: _danmakuPanelOpen,
      anchor: anchor,
      alignment: Alignment.bottomRight,
      child: SizedBox(
        width: 264,
        child: MiuixOverlayPanel(
          title: '弹幕设置',
          icon: AppIcon(
            AppIcons.danmakuTune(),
            size: 16,
            color: tokens.colors.primary,
          ),
          child: SizedBox(
            width: 232,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DemoSliderRow(
                  label: '不透明度',
                  value: _dmOpacity,
                  min: 0.1,
                  max: 1.0,
                  steps: 9,
                  valueLabel: '${(_dmOpacity * 100).round()}%',
                  onChanged: (v) => setState(() => _dmOpacity = v),
                ),
                _DemoSliderRow(
                  label: '字号',
                  value: _dmFontScale,
                  min: 0.5,
                  max: 2.0,
                  steps: 15,
                  valueLabel: '${_dmFontScale.toStringAsFixed(1)}x',
                  onChanged: (v) => setState(() => _dmFontScale = v),
                ),
                _DemoSliderRow(
                  label: '显示区域',
                  value: _dmArea,
                  min: 0.2,
                  max: 1.0,
                  steps: 8,
                  valueLabel: '${(_dmArea * 100).round()}%',
                  onChanged: (v) => setState(() => _dmArea = v),
                ),
                _DemoSwitchRow(
                  label: '合并相同弹幕',
                  value: _dmMerge,
                  onChanged: (v) => setState(() => _dmMerge = v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 字幕设置浮层（锚定字幕 chip）：**本地态**面板，不写 `Pref`。
  Widget _buildSubtitleSettingsPopup() {
    final anchor = _anchorOf(_subtitleKey);
    if (anchor == null) return const SizedBox.shrink();
    final tokens = AppThemeHost.of(context);
    return MiuixAnchoredPopup(
      visible: _subtitlePanelOpen,
      anchor: anchor,
      alignment: Alignment.bottomRight,
      child: SizedBox(
        width: 264,
        child: MiuixOverlayPanel(
          title: '字幕设置',
          icon: AppIcon(
            AppIcons.subtitle(active: _subtitleOn),
            size: 16,
            color: tokens.colors.primary,
          ),
          child: SizedBox(
            width: 232,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DemoSwitchRow(
                  label: '启用字幕',
                  value: _subtitleOn,
                  onChanged: (v) => setState(() => _subtitleOn = v),
                ),
                _DemoSliderRow(
                  label: '字号',
                  value: _subFontScale,
                  min: 0.5,
                  max: 2.0,
                  steps: 15,
                  valueLabel: '${_subFontScale.toStringAsFixed(1)}x',
                  onChanged: (v) => setState(() => _subFontScale = v),
                ),
                _DemoSliderRow(
                  label: '背景不透明度',
                  value: _subBgOpacity,
                  min: 0.0,
                  max: 1.0,
                  steps: 10,
                  valueLabel: '${(_subBgOpacity * 100).round()}%',
                  onChanged: (v) => setState(() => _subBgOpacity = v),
                ),
                _DemoSliderRow(
                  label: '描边粗细',
                  value: _subStroke,
                  min: 0.0,
                  max: 3.0,
                  steps: 6,
                  valueLabel: _subStroke.toStringAsFixed(1),
                  onChanged: (v) => setState(() => _subStroke = v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 章节滑出面板（对齐正常模式 `_buildChapterPanel`：右侧 1/3 区域毛玻璃面板，
  /// 点击面板外 dismiss 关闭，点击章节本地跳转）。
  Widget _buildChapterPanel(List<_DemoChapter> chapters) {
    if (chapters.isEmpty) return const SizedBox.shrink();
    const panelWidth = 280.0;
    final currentIndex = _currentChapterIndex(chapters);
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 面板外区域 dismiss 遮罩。
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_chapterPanelOpen,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _chapterPanelOpen = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  color: _chapterPanelOpen
                      ? AppColors.black.withValues(alpha: 0.25)
                      : AppColors.transparent,
                ),
              ),
            ),
          ),
          // 2. 右侧滑出的章节面板本体。
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            right: _chapterPanelOpen ? 0 : -panelWidth - 10,
            top: 0,
            bottom: 0,
            width: panelWidth,
            child: IgnorePointer(
              ignoring: !_chapterPanelOpen,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {}, // 吸收点击，防止触发外部遮罩 dismiss。
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(Style.radiusMd),
                    bottomLeft: Radius.circular(Style.radiusMd),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xF2141414),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(Style.radiusMd),
                          bottomLeft: Radius.circular(Style.radiusMd),
                        ),
                        border: Border(
                          left: BorderSide(
                            color: AppColors.white.withValues(alpha: 0.15),
                            width: 0.8,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.black.withValues(alpha: 0.5),
                            blurRadius: 20,
                            offset: const Offset(-4, 0),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 标题栏
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Style.md,
                              vertical: Style.md,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: AppColors.white.withValues(alpha: 0.08),
                                  width: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                AppIcon(
                                  AppIcons.chapter(),
                                  color: AppColors.white,
                                  size: appRowIconSize(context, 15),
                                ),
                                const SizedBox(width: Style.sm),
                                Text(
                                  '章节 (${chapters.length})',
                                  style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                HoverContainer(
                                  onTap: () =>
                                      setState(() => _chapterPanelOpen = false),
                                  borderRadius: 6.0,
                                  padding: const EdgeInsets.all(4),
                                  hoverColor: AppColors.white.withValues(
                                    alpha: 0.12,
                                  ),
                                  child: AppIcon(
                                    AppIcons.clear(),
                                    color: AppColors.white70,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // 章节列表
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                vertical: Style.xs,
                                horizontal: Style.xs,
                              ),
                              itemCount: chapters.length,
                              itemBuilder: (context, index) {
                                final chapter = chapters[index];
                                final isCurrent = index == currentIndex;
                                final fromStr = DurationUtils.formatDuration(
                                  chapter.start.inSeconds,
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: HoverContainer(
                                    onTap: () => setState(() {
                                      _pos = chapter.start;
                                      _chapterPanelOpen = false;
                                    }),
                                    borderRadius: Style.radiusSm,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Style.sm,
                                      vertical: Style.sm,
                                    ),
                                    color: isCurrent
                                        ? biliBlue.withValues(alpha: 0.16)
                                        : AppColors.transparent,
                                    hoverColor: isCurrent
                                        ? biliBlue.withValues(alpha: 0.24)
                                        : AppColors.white.withValues(
                                            alpha: 0.08,
                                          ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 22,
                                          child: isCurrent
                                              ? AppIcon(
                                                  AppIcons.play(active: true),
                                                  color: biliBlue,
                                                  size: 18,
                                                )
                                              : Text(
                                                  '${index + 1}'.padLeft(2, '0'),
                                                  style: TextStyle(
                                                    color: AppColors.white
                                                        .withValues(alpha: 0.6),
                                                    fontSize: 13,
                                                  ),
                                                ),
                                        ),
                                        const SizedBox(width: Style.sm),
                                        Expanded(
                                          child: Text(
                                            chapter.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isCurrent
                                                  ? biliBlue
                                                  : AppColors.white,
                                              fontSize: 13,
                                              fontWeight: isCurrent
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: Style.sm),
                                        Text(
                                          fromStr,
                                          style: TextStyle(
                                            color: AppColors.white.withValues(
                                              alpha: 0.5,
                                            ),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 复用外壳
  // ---------------------------------------------------------------------------

  /// 毛玻璃胶囊 chip（弹幕开关 / 章节 / 字幕，风格对齐正常模式 `GlassCapsule`）。
  Widget _capsule({
    Key? key,
    required Color background,
    required Color borderColor,
    required Widget child,
    VoidCallback? onTap,
  }) {
    return GlassCapsule(
      key: key,
      borderRadius: Style.radiusFull,
      blur: 8,
      padding: EdgeInsets.zero,
      backgroundColor: background,
      borderColor: borderColor,
      child: HoverContainer(
        onTap: onTap ?? () {},
        borderRadius: Style.radiusFull,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        hoverColor: AppColors.white.withValues(alpha: 0.12),
        child: child,
      ),
    );
  }
}

/// 演示章节条目。
class _DemoChapter {
  const _DemoChapter({required this.title, required this.start});

  final String title;
  final Duration start;
}

/// 控制栏图标按钮 —— 逐像素对齐正常模式 `PlayerPanel._PlayerBarIconButton`：
/// 默认温和白 (~82% alpha)、hover 提亮至纯白、30px 命中区（padding 6）、
/// hover 白 0.12 圆角背景、150ms 平滑过渡、带 `AppTooltip`。
class _DemoBarIconButton extends StatefulWidget {
  const _DemoBarIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 18.0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double size;

  @override
  State<_DemoBarIconButton> createState() => _DemoBarIconButtonState();
}

class _DemoBarIconButtonState extends State<_DemoBarIconButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        widget.color ??
        (_isHovering ? AppColors.white : AppColors.white.withValues(alpha: 0.82));
    final child = MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: widget.onPressed != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: _isHovering
                ? AppColors.white.withValues(alpha: 0.12)
                : AppColors.transparent,
            borderRadius: BorderRadius.circular(6.0),
          ),
          child: IconTheme(
            data: IconThemeData(size: widget.size, color: effectiveColor),
            child: AppIcon(
              widget.icon,
              size: widget.size,
              color: effectiveColor,
              shadows: ContrastStyle.glyphShadows,
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      return AppTooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

/// 通用滑块行（label + 数值 + MiuixSlider），样式对齐弹幕设置面板。
class _DemoSliderRow extends StatelessWidget {
  const _DemoSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.steps,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int steps;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: AppThemeHost.of(context).text.bodyMedium),
              const Spacer(),
              Text(
                valueLabel,
                style: const TextStyle(
                  color: biliPink,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: MiuixSlider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              steps: steps > 1 ? steps - 1 : 0,
              onValueChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 通用开关行（label + MiuixSwitch）。
class _DemoSwitchRow extends StatelessWidget {
  const _DemoSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Row(
        children: [
          Text(label, style: AppThemeHost.of(context).text.bodyMedium),
          const Spacer(),
          MiuixSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}