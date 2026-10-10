import 'package:flutter_miuix/miuix.dart' show MiuixIconButton, MiuixTextButton;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/common/widgets/miuix_overlay_panel.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/input/escape_layer_registry.dart';
import 'package:winwin/http/danmaku.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/ui/components/app_progress.dart';
import 'package:winwin/ui/components/app_tooltip.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 弹幕发送面板（移植自 BiliPai `DanmakuSendDialog` + `DanmakuComposerPolicy`）。
///
/// 控件美术对齐 BiliPai：圆形色块（8 色 + 会员渐变色）、位置 FilterChip
/// （滚动/顶部/底部）、字号 FilterChip（小/大/特大）、占位语
/// 「发个友善的弹幕见证当下」、计数 x/100（>90 变红）。
///
/// 弹出方式：[showSendDanmakuPanel]，由播放器控制条「发弹幕」按钮调用
/// （全屏态使用）；内联模式见 [SendDanmakuPanel.inline]，嵌入视频页
/// 播放器正下方。
void showSendDanmakuPanel(
  BuildContext context, {
  required WinWinPlayerController controller,
}) {
  showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.transparent,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SendDanmakuPanel(controller: controller),
    ),
  );
}

/// 会员渐变色哨兵值（对标 BiliPai DANMAKU_SEND_VIP_GRADUAL_COLOR = -1）。
/// 发送时转换为 colorful=true + color=60001（见 DanmakuHttp.shootDanmaku）。
const int _vipGradualColor = -1;

/// 会员渐变色的渲染渐变（对标 BiliPai VIP 色块 DD94DA→72B2EA）。
const LinearGradient _vipGradient = LinearGradient(
  colors: [Color(0xFFDD94DA), Color(0xFF72B2EA)],
);

/// 颜色选项（移植自 BiliPai danmakuSendColorOptions）。
const List<({int value, String label})> _colorOptions = [
  (value: 0xFFFFFF, label: '白色'),
  (value: 0xFE0302, label: '红色'),
  (value: 0xFF7204, label: '橙色'),
  (value: 0xFFAA02, label: '金色'),
  (value: 0x00CC00, label: '绿色'),
  (value: 0x00A1D6, label: '蓝色'),
  (value: 0xCC0273, label: '紫色'),
  (value: 0x222222, label: '黑色'),
  (value: _vipGradualColor, label: '会员渐变'),
];

/// 位置选项（移植自 BiliPai danmakuSendModeOptions）。
const List<({int value, String label})> _modeOptions = [
  (value: 1, label: '滚动'),
  (value: 5, label: '顶部'),
  (value: 4, label: '底部'),
];

/// 字号选项（移植自 BiliPai danmakuSendFontSizeOptions）。
const List<({int value, String label})> _fontSizeOptions = [
  (value: 18, label: '小'),
  (value: 25, label: '大'),
  (value: 36, label: '特大'),
];

/// 输入占位语（对标 BiliPai resolveDanmakuInputPlaceholder）。
String _danmakuPlaceholder(bool isLogin) =>
    isLogin ? '发个友善的弹幕见证当下' : '登录后发弹幕';

class SendDanmakuPanel extends StatefulWidget {
  const SendDanmakuPanel({
    super.key,
    required this.controller,
    this.inline = false,
  });

  final WinWinPlayerController controller;

  /// true：内联嵌入视频页播放器正下方（不自动聚焦、发送成功不关闭面板，
  /// 仅清空输入框）；false：底部弹窗模式（「发弹幕」按钮弹出）。
  final bool inline;

  @override
  State<SendDanmakuPanel> createState() => _SendDanmakuPanelState();
}

class _SendDanmakuPanelState extends State<SendDanmakuPanel>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _textController;

  /// 内联样式浮层的对角线展开动画（对齐表情面板）。
  late final AnimationController _settingsAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final ValueNotifier<int> _mode;
  late final ValueNotifier<int> _color;
  late final ValueNotifier<int> _fontSize;
  final ValueNotifier<bool> _sending = ValueNotifier(false);
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _settingsOverlay;

  /// 内联样式浮层的 Esc 登记注销回调。
  VoidCallback? _settingsEscUnregister;

  /// 弹窗模式的设置区折叠态（对标 BiliPai showSettings，默认收起）。
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _mode = ValueNotifier(1);
    _color = ValueNotifier(0xFFFFFF);
    _fontSize = ValueNotifier(25);
  }

  @override
  void dispose() {
    _closeInlineSettings();
    _settingsAnim.dispose();
    _textController.dispose();
    _mode.dispose();
    _color.dispose();
    _fontSize.dispose();
    _sending.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 关闭内联弹幕样式浮层（唯一出口）：移除 Overlay 并注销 Esc 登记。
  void _closeInlineSettings() {
    _settingsOverlay?.remove();
    _settingsOverlay = null;
    _settingsEscUnregister?.call();
    _settingsEscUnregister = null;
  }

  bool get _canSend =>
      _textController.text.trim().isNotEmpty && !_sending.value;

  Future<void> _onSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending.value) return;

    if (!Accounts.main.isLogin) {
      _toast('请先登录');
      return;
    }
    if (widget.controller.danmaku?.danmakuClosed == true) {
      _toast('UP 主已关闭弹幕');
      return;
    }

    _sending.value = true;
    final mode = _mode.value;
    final vip = _color.value == _vipGradualColor;
    final color = vip ? 0xFFFFFF : _color.value;
    final res = await DanmakuHttp.shootDanmaku(
      oid: widget.controller.cid,
      bvid: widget.controller.bvid,
      msg: text,
      mode: mode,
      progress: widget.controller.position.value.inMilliseconds,
      color: color,
      fontSize: _fontSize.value,
      colorful: vip,
    );
    if (!mounted) {
      _sending.value = false;
      return;
    }
    switch (res) {
      case Success():
        // 本地回显：立即上屏，无需等待服务端重新拉取。
        // VIP 渐变本地回显降级为渐变起始色。
        widget.controller.danmaku?.addLocal(
          text: text,
          mode: mode,
          color: vip ? 0xDD94DA : color,
        );
        _toast('发送成功');
        if (widget.inline) {
          // 内联模式：不关闭面板，仅清空输入框。
          _textController.clear();
          setState(() {});
        } else {
          Navigator.of(context).pop();
        }
      case Error(:final errMsg):
        _toast(errMsg ?? '发送失败');
      case Loading():
        break;
    }
    _sending.value = false;
  }

  void _toast(String msg) {
    if (!mounted) return;
    showToast(context, msg, duration: const Duration(seconds: 2));
  }

  @override
  Widget build(BuildContext context) {
    final inline = widget.inline;
    return inline ? _buildInline() : _buildSheet();
  }

  // ─────────────────────────── 弹窗模式 ───────────────────────────

  /// 弹窗模式（对标 BiliPai DanmakuSendDialog）：标题栏 + 输入卡片 +
  /// 计数 + 「颜色、位置、大小」折叠设置区 + 全宽发送按钮。
  Widget _buildSheet() {
    final tokens = AppThemeHost.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 560),
      decoration: BoxDecoration(
        color: tokens.colors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Style.radiusMd),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Style.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                Text(
                  '发送弹幕',
                  style: tokens.text.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                MiuixIconButton(

                  onPressed: () => Navigator.of(context).pop(),

                  child: AppTooltip(message: '关闭', child: AppIcon(AppIcons.clear(), size: 20)),
                ),
              ],
            ),
            const SizedBox(height: Style.sm),
            // 输入卡片（surfaceContainerHighest α0.5，对标 BiliPai 输入框容器）
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: Style.md),
              decoration: BoxDecoration(
                color: tokens.colors.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(Style.radiusSm),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                autofocus: true,
                maxLength: 100,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _onSend(),
                onChanged: (_) => setState(() {}),
                style: tokens.text.bodyLarge,
                decoration: InputDecoration(
                  isCollapsed: true,
                  hintText: _danmakuPlaceholder(Accounts.main.isLogin),
                  hintStyle: TextStyle(
                    color: tokens.colors.onSurfaceVariant,
                    fontSize: 15,
                  ),
                  counterText: '',
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: Style.xs),
            // 字数统计（>90 变红，对标 BiliPai）
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${_textController.text.length}/100',
                style: TextStyle(
                  fontSize: 12,
                  color: _textController.text.length > 90
                      ? tokens.colors.error
                      : tokens.colors.onSurfaceVariant,
                ),
              ),
            ),
            // 设置区折叠开关（对标 BiliPai 「颜色、位置、大小」按钮）
            Align(
              alignment: Alignment.centerRight,
              child: MiuixTextButton(
                _showSettings ? '收起弹幕设置' : '颜色、位置、大小',
                onPressed: () =>
                    setState(() => _showSettings = !_showSettings),
              ),
            ),
            if (_showSettings) ...[
              _buildColorSection(tokens),
              const SizedBox(height: Style.md),
              _buildChipSection(tokens, '位置', _modeOptions, _mode),
              const SizedBox(height: Style.md),
              _buildChipSection(tokens, '大小', _fontSizeOptions, _fontSize),
              const SizedBox(height: Style.md),
            ],
            // 全宽发送按钮（对标 BiliPai 48dp filled button）
            ValueListenableBuilder<bool>(
              valueListenable: _sending,
              builder: (context, sending, _) {
                return SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: AppPrimaryButton(
                    onPressed: _canSend ? _onSend : null,
                    insideMargin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: AppProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.white,
                            ),
                          )
                        : const Text(
                            '发送',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          )),
                );
              },
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── 内联模式 ───────────────────────────

  /// 内联模式：单行输入框 + 设置按钮 + 发送按钮（样式对齐评论发送栏）。
  /// 设置面板（颜色/位置/大小）通过点击设置按钮展开。
  Widget _buildInline() {
    final tokens = AppThemeHost.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Style.safeSpace,
        Style.xs,
        Style.cardSpace,
        Style.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.colors.surface,
        border: Border(
          top: BorderSide(
            color: tokens.colors.outlineVariant.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                maxLength: 100,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _onSend(),
                onChanged: (_) => setState(() {}),
                style: tokens.text.bodyLarge,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: Style.md,
                    vertical: Style.sm,
                  ),
                  hintText: _danmakuPlaceholder(Accounts.main.isLogin),
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: tokens.colors.onSurfaceVariant,
                  ),
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(100),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: tokens.colors.surfaceContainer
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: Style.sm),
            _buildInlineSettingsButton(tokens),
            const SizedBox(width: Style.xs),
            _buildInlineSendButton(tokens),
          ],
        ),
      ),
    );
  }

  /// 内联模式设置按钮：点击展开弹幕样式设置面板。
  Widget _buildInlineSettingsButton(AppTokens tokens) {
    return Builder(
      builder: (ctx) => MiuixIconButton(

        onPressed: () => _showInlineSettings(ctx),

        child: AppTooltip(message: '弹幕样式', child: AppIcon(AppIcons.palette(), size: 20)),
      ),
    );
  }

  /// 内联模式发送按钮（紧凑口径：与内联输入条等高）。
  Widget _buildInlineSendButton(AppTokens tokens) {
    return AppPrimaryButton(
        onPressed: _canSend ? _onSend : null,
        minWidth: 60,
        minHeight: 36,
        insideMargin: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        cornerRadius: 10,
        child: ValueListenableBuilder<bool>(
        valueListenable: _sending,
        builder: (context, sending, _) {
          return sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: AppProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : const Text('发送');
        },
      ));
  }

  /// 内联模式：点击设置按钮时弹出弹幕样式设置面板（Overlay）。
  void _showInlineSettings(BuildContext buttonContext) {
    // 如果已有 overlay，先移除并返回（点击切换开/关）
    if (_settingsOverlay != null) {
      _closeInlineSettings();
      return;
    }
    
    final renderBox = buttonContext.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;

    // 对角线展开（对齐表情面板）：面板位于按钮上方、右缘对齐按钮右缘，
    // 以贴近按钮的右下角为原点缩放展开。
    _settingsAnim.forward(from: 0);

    _settingsOverlay = OverlayEntry(
      builder: (context) {
    final tokens = AppThemeHost.of(context);
        // 面板在按钮正上方，右对齐按钮右边缘
        final panelWidth = 340.0;
        final panelLeft = (buttonPosition.dx + buttonSize.width - panelWidth)
            .clamp(8.0, double.infinity);
        // 共用浮层面板（MiuixOverlayPanel）：与"表情"面板统一样式，
        // 半透明底统一走 kMiuixSurfaceAlpha。
        final panel = FadeTransition(
          opacity: _settingsAnim,
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: _settingsAnim,
              curve: Curves.easeOutCubic,
            ),
            alignment: Alignment.bottomRight,
            child: MiuixOverlayPanel(
              title: '弹幕样式',
              icon: AppIcon(AppIcons.palette(),
                size: 16,
                color: tokens.colors.primary,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildColorSection(tokens),
                  const SizedBox(height: 20),
                  _buildChipSection(tokens, '位置', _modeOptions, _mode),
                  const SizedBox(height: 20),
                  _buildChipSection(tokens, '字号', _fontSizeOptions, _fontSize),
                ],
              ),
            ),
          ),
        );
        return Stack(
          children: [
            // 透明遮罩，点击外部关闭
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _closeInlineSettings,
              child: Container(color: AppColors.transparent),
            ),
            Positioned(
              left: panelLeft,
              bottom: MediaQuery.of(context).size.height -
                  buttonPosition.dy +
                  8,
              width: panelWidth,
              child: panel,
            ),
          ],
        );
      },
    );
    Overlay.of(buttonContext).insert(_settingsOverlay!);
    _settingsEscUnregister = EscapeLayerRegistry.instance.register(() {
      if (_settingsOverlay == null) return false;
      _closeInlineSettings();
      return true;
    });
  }



  // ─────────────────────────── 选项区 ───────────────────────────

  /// 颜色区：圆形色块 32px，选中 2px primary 描边；VIP 渐变色块带
  /// 「VIP」白字（对标 BiliPai 颜色选择器）。
  Widget _buildColorSection(AppTokens tokens) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '颜色',
          style: tokens.text.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: Style.sm),
        ValueListenableBuilder<int>(
          valueListenable: _color,
          builder: (context, selected, _) {
            return Wrap(
              spacing: Style.sm,
              runSpacing: Style.sm,
              children: [
                for (final option in _colorOptions)
                  _buildColorSwatch(option, selected),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildColorSwatch((
    {
      int value,
      String label,
    }) option, int selected) {
    final isSelected = option.value == selected;
    final isVip = option.value == _vipGradualColor;
    return GestureDetector(
      onTap: () => _color.value = option.value,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: isVip ? _vipGradient : null,
          color: isVip ? null : Color(0xFF000000 | option.value),
          border: isSelected
              ? Border.all(width: 2, color: biliPink)
              : null,
        ),
        child: isVip
            ? const Center(
                child: Text(
                  'VIP',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  /// 位置/字号 FilterChip 区（对标 BiliPai：选中 primaryContainer）。
  Widget _buildChipSection(
    AppTokens tokens,
    String title,
    List<({int value, String label})> options,
    ValueNotifier<int> notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: tokens.text.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: Style.sm),
        ValueListenableBuilder<int>(
          valueListenable: notifier,
          builder: (context, selected, _) {
            return Wrap(
              spacing: Style.sm,
              runSpacing: Style.sm,
              children: [
                for (final option in options)
                  _buildOptionChip(
                      AppThemeHost.of(context), option, selected == option.value,
                      () => notifier.value = option.value),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildOptionChip(
    AppTokens tokens,
    ({int value, String label}) option,
    bool selected,
    VoidCallback onTap,
  ) {
    final cs = tokens.colors;
    final isDark = tokens.isDark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer
              : (isDark
                  ? AppColors.white.withValues(alpha: 0.08)
                  : AppColors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected
                ? cs.primary.withValues(alpha: 0.4)
                : (isDark
                    ? AppColors.white.withValues(alpha: 0.12)
                    : AppColors.black.withValues(alpha: 0.08)),
            width: 0.5,
          ),
        ),
        child: Text(
          option.label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
