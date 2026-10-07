import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_miuix/miuix.dart';

import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/app_typography.dart';
import 'package:winwin/theme/miuix_theme_bridge.dart';
import 'package:winwin/theme/app_icons.dart';

export 'app_desktop_interaction.dart';
export 'app_press_feedback.dart';
export 'official_verify_badge.dart';
export 'user_vip_badge.dart';

/// ─────────────────────────────────────────────────────────────────
/// 自适应基础控件集合（对齐 BiliPai 主题架构）
///
/// 参照 BiliPai 的「同一 API、双套渲染」模式：每个控件入口读取
/// [InheritedUiStyle.of] 获取 [UiStyle]，再用 [resolvePrimitiveRenderer]
/// 分发到 `MATERIAL3 / MIUIX` 两条渲染路径。形状 / 阴影 / 字间距
/// 由 [AppShapes] / [AppChrome] / [AppTypography] Token 提供。
///
/// 切换 [UiStyleNotifier] 时整棵树重建，控件即时呈现对应风格。
/// ─────────────────────────────────────────────────────────────────

/// 从 context 读取两套 Token 的便捷封装。
class _Tokens {
  _Tokens.of(BuildContext context)
      : shapes = Theme.of(context).extension<AppShapes>() ?? AppShapes.miuix,
        chrome = Theme.of(context).extension<AppChrome>() ?? AppChrome.miuix,
        typo = Theme.of(context).extension<AppTypography>() ?? AppTypography.miuix;

  final AppShapes shapes;
  final AppChrome chrome;
  final AppTypography typo;
}

// ════════════════════════════════════════════════════════════════
// AppCard
// ════════════════════════════════════════════════════════════════

/// 自适应卡片容器。
///
/// - MD3：surfaceContainerHighest + M3 tonal elevation。
/// - Miuix：[MiuixCard]（surfaceContainer + 无阴影扁平 + squircle 圆角，
///   flutter_miuix 阶段1 起替换原手绘圆角近似实现）。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.color,
    this.radius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final r = radius ?? t.shapes.medium.x;

    // 阶段5d-L1：M3 分支已移除；原生 MiuixCard（squircle 圆角 + 无阴影扁平）。
    // 颜色显式取自 WinWin colorScheme（含 miuix 调色板），与替换前保持一致。
    final card = MiuixCard(
      cornerRadius: r,
      insideMargin: padding ?? const EdgeInsets.all(12),
      colors: MiuixCardColors(
        color: color ?? cs.surfaceContainer,
        contentColor: cs.onSurface,
      ),
      onPressed: onTap,
      child: child,
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

// ════════════════════════════════════════════════════════════════
// AppGroup
// ════════════════════════════════════════════════════════════════

/// 自适应分组容器（设置页 / 表单用）。
///
/// - MD3：surfaceContainer + 24dp 圆角，无分割线（靠间距分隔）。
/// - Miuix：[MiuixCard]（surface + squircle 圆角 + 0 elevation；外层
///   ClipPath 裁四角，保证行内按压反馈不溢出；flutter_miuix 阶段2 起替换）。
class AppGroup extends StatelessWidget {
  const AppGroup({super.key, required this.children, this.margin});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final cs = Theme.of(context).colorScheme;
    // 阶段5d-L1：M3 分支已移除；MiuixCard + squircle 裁角（防按压溢出）。
    final r = t.shapes.large.x;
    return Container(
      margin: margin,
      child: ClipPath(
        clipper: ShapeBorderClipper(
          shape: MiuixSquircleBorder(cornerRadius: r),
        ),
        child: MiuixCard(
          cornerRadius: r,
          insideMargin: EdgeInsets.zero,
          colors: MiuixCardColors(
            color: cs.surface,
            contentColor: cs.onSurface,
          ),
          child: Column(children: children),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// AppPrimaryButton
// ════════════════════════════════════════════════════════════════

/// 自适应主按钮。
///
/// - MD3：渐变 primary→tertiary + 按压 0.96 弹簧（[AppPressFeedback] 触感）。
/// - Miuix：[MiuixButton]（主色纯色 + squircle 圆角 + folme 按压反馈，
///   flutter_miuix 阶段1 起替换原"渐变近似"实现，视觉变化已列入实机验收）。
class AppPrimaryButton extends StatefulWidget {
  const AppPrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.expanded = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool expanded;

  @override
  State<AppPrimaryButton> createState() => _AppPrimaryButtonState();
}

class _AppPrimaryButtonState extends State<AppPrimaryButton> {
  @override
  Widget build(BuildContext context) {

    // 阶段5d-L1：M3 分支已移除；原生 MiuixButton（纯色 + squircle + folme 按压）。
    final button = MiuixButton(
      onPressed: widget.onPressed,
      colors: MiuixButtonDefaults.buttonColorsPrimary(context),
      child: widget.child,
    );
    return widget.expanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

// ════════════════════════════════════════════════════════════════
// AppSwitch
// ════════════════════════════════════════════════════════════════

/// 自适应开关。
///
/// - MD3：[Switch]（M3 标准 thumb 与轨道）。
/// - Miuix：[MiuixSwitch]（49×28 胶囊轨道 + 20dp thumb，点击/拖拽切换 +
///   folme 弹簧，flutter_miuix 阶段1 起替换原 0.85 缩放近似实现）。
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    // 阶段5d-L1：M3 分支已移除；原生 MiuixSwitch 恒用。
    return MiuixSwitch(value: value, onChanged: onChanged);
  }
}

// ════════════════════════════════════════════════════════════════
// AppListItem
// ════════════════════════════════════════════════════════════════

/// 自适应列表项 — 图标 + 标题 + 副标题 + 尾部。
///
/// - MD3：标准 [ListTile] + M3 ripple。
/// - Miuix：[MiuixBasicComponent]（标题/摘要 + 起始图标 + 尾部自定义，
///   整行按压反馈；flutter_miuix 阶段2 起替换原手绘行）。
class AppListItem extends StatelessWidget {
  const AppListItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconTint,
    this.trailing,
    this.onTap,
    this.borderRadius,
  });

  final Widget icon;
  final String title;
  final String? subtitle;
  final Color? iconTint;
  final Widget? trailing;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = iconTint ?? cs.primary;

    // 阶段5d-L1：M3 分支已移除；MiuixBasicComponent 恒用。
    return MiuixBasicComponent(
      title: title,
      summary: subtitle,
      startAction: IconTheme(
        data: IconThemeData(color: tint, size: 22),
        child: icon,
      ),
      endActions: trailing == null ? null : [trailing!],
      insideMargin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onClick: onTap,
    );
  }
}

// ════════════════════════════════════════════════════════════════
// AppSegmentedControl
// ════════════════════════════════════════════════════════════════

/// 自适应分段控件。
///
/// - MD3：[SegmentedButton] 标准 M3 带边框容器。
/// - Miuix：[MiuixTabRow]（原生胶囊选中指示 + squircle 揭示；
///   flutter_miuix 阶段2 起替换原自绘胶囊实现）。
class AppSegmentedControl<T extends Object> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    // 阶段5d-L1：M3 分支已移除；MiuixTabRow 恒用。
    final index = segments.indexWhere((e) => e.$1 == value);
    return MiuixTabRow(
      tabs: segments.map((e) => e.$2).toList(),
      selectedTabIndex: index < 0 ? 0 : index,
      onTabSelected: (i) => onChanged(segments[i].$1),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// AppTextField / AppSearchField
// ════════════════════════════════════════════════════════════════

/// 自适应文本输入框。
///
/// - MD3：outlined + M3 label（原生 [TextField]，格式化器直传）。
/// - Miuix：[MiuixTextField]（浮动标签 + 聚焦 squircle 边框；
///   flutter_miuix 阶段2 起替换原"扁平填充 + 底部细线"近似实现）。
///
/// 桥接说明：flutter_miuix 1.3.0 的 `MiuixTextField` 暂无 `inputFormatters`
/// 参数，而调用侧需要过滤输入；此处以 [_FormatterProxyController] 在控制器
/// 层应用格式化器——复用 Flutter 官方 [TextInputFormatter.formatEditUpdate]
/// （与 EditableText 内部同一机制），上游补齐该参数后可整体移除。
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefix,
    this.suffix,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.keyboardType,
    this.inputFormatters,
    this.minLines,
    this.maxLines = 1,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final Widget? prefix;
  final Widget? suffix;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int? maxLines;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  /// 内部自建的基础控制器（外部未传入 controller 且需要格式化桥接时）。
  TextEditingController? _ownedController;

  /// 格式化桥接控制器（仅 miuix 分支、且有格式化器时启用）。
  _FormatterProxyController? _proxy;

  @override
  void didUpdateWidget(AppTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldHasFormatters = oldWidget.inputFormatters?.isNotEmpty ?? false;
    final newHasFormatters = widget.inputFormatters?.isNotEmpty ?? false;
    if (oldWidget.controller != widget.controller ||
        oldHasFormatters != newHasFormatters) {
      _disposeProxy();
      return;
    }
    _proxy?.formatters = widget.inputFormatters ?? const [];
  }

  @override
  void dispose() {
    _disposeProxy();
    super.dispose();
  }

  void _disposeProxy() {
    _proxy?.dispose();
    _proxy = null;
    _ownedController?.dispose();
    _ownedController = null;
  }

  /// 取得启用格式化桥接的控制器（惰性创建）。
  TextEditingController _ensureProxy() {
    final existing = _proxy;
    if (existing != null) return existing;
    final base =
        widget.controller ?? (_ownedController ??= TextEditingController());
    final proxy = _FormatterProxyController(base, widget.inputFormatters!);
    _proxy = proxy;
    return proxy;
  }

  @override
  Widget build(BuildContext context) {
    // 阶段5d-L1：M3 分支已移除；原生 MiuixTextField + 控制器层格式化桥接。
    final hasFormatters = widget.inputFormatters?.isNotEmpty ?? false;
    final field = MiuixTextField(
      controller: hasFormatters ? _ensureProxy() : widget.controller,
      focusNode: widget.focusNode,
      onChanged: widget.onChanged,
      label: widget.label ?? widget.hint ?? '',
      useLabelAsPlaceholder: widget.label == null && widget.hint != null,
      leadingIcon: widget.prefix,
      trailingIcon: widget.suffix,
      singleLine: (widget.maxLines ?? 1) == 1,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      onSubmitted: widget.onSubmitted,
      obscureText: widget.obscureText,
    );
    // MiuixTextField 内部使用 SDK flutter/material 的 TextField：经
    // MiuixCompat 提供 SDK Material 祖先与 ThemeData/MaterialLocalizations
    // 桥接（缺失后者在 release 下会空断言崩溃，见阶段3复盘）。
    return MiuixCompat(child: field);
  }
}

/// 控制器层格式化桥接（flutter_miuix 1.3.0 缺 `inputFormatters` 参数的临时
/// 补偿）：在写入前经官方 formatter 链过滤，行为与 EditableText 内部一致。
class _FormatterProxyController extends TextEditingController {
  _FormatterProxyController(this._inner, List<TextInputFormatter> formatters)
      : formatters = List.of(formatters);

  final TextEditingController _inner;
  List<TextInputFormatter> formatters;

  @override
  TextEditingValue get value => _inner.value;

  @override
  set value(TextEditingValue newValue) {
    var formatted = newValue;
    for (final formatter in formatters) {
      formatted = formatter.formatEditUpdate(_inner.value, formatted);
    }
    _inner.value = formatted;
    // 同步通知本代理的监听者（EditableText 依赖 read-back 取过滤结果）。
    notifyListeners();
  }
}

/// 自适应搜索框 — 圆角填充 + 搜索图标 + 清除按钮。
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hint = '搜索',
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppTextField(
      controller: controller,
      focusNode: focusNode,
      hint: hint,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      prefix: AppIcon(AppIcons.search(), color: cs.onSurfaceVariant, size: 20),
      suffix: controller == null
          ? null
          : ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller!,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: AppIcon(AppIcons.clear(), size: 18),
                  onPressed: () {
                    controller!.clear();
                    onChanged?.call('');
                  },
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// AppActionTile
// ════════════════════════════════════════════════════════════════

/// 自适应方格动作项 — 个人页/动态页等"图标(或数值)+文字"网格用。
///
/// 通过 [icon] 或 [count] 二选一指定顶部内容：
/// - 传入 [icon]：渲染图标（动作入口，如离线缓存/历史记录）。
/// - 传入 [count]：渲染数值（统计项，如动态/关注/粉丝）。
///
/// 两套风格差异：
/// - MD3：图标/数值用 primary 色，InkWell 圆角 ripple，标准 spacing。
/// - Miuix：图标/数值用 onSurfaceVariant 色，扁平无 ripple，宽 spacing。
class AppActionTile extends StatelessWidget {
  const AppActionTile({
    super.key,
    this.icon,
    this.count,
    required this.label,
    this.onTap,
    this.iconTint,
    this.flexible = true,
  }) : assert(
          icon != null || count != null,
          'AppActionTile 需传入 icon 或 count 之一',
        );

  final IconData? icon;
  final String? count;
  final String label;
  final VoidCallback? onTap;
  final Color? iconTint;

  /// 是否自带 [Flexible] 外壳（默认 true，直接作为 Row 子项使用）。
  ///
  /// 演示模式的外壳会把组件包进多层 Widget，此时须置 false 并由调用方
  /// 自行在最外层提供 [Flexible]，否则会触发 ParentDataWidget 断言。
  final bool flexible;

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 阶段5d-L1：M3 分支已移除。
    final contentColor = iconTint ?? cs.onSurfaceVariant;
    const spacing = 8.0;

    final tile = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 80),
      child: AspectRatio(
        aspectRatio: 1,
        child: Column(
          spacing: spacing,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, color: contentColor, size: 22)
            else
              Text(
                count ?? '-',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: t.typo.titleWeight,
                  color: contentColor,
                ),
              ),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    // 阶段5d-L1：M3 分支已移除；按压反馈恒为原生 MiuixPressable。
    final pressed = MiuixPressable(
      onPressed: onTap,
      enabled: onTap != null,
      child: tile,
    );
    return flexible ? Flexible(child: pressed) : pressed;
  }
}

// ════════════════════════════════════════════════════════════════
// AppProgressBar
// ════════════════════════════════════════════════════════════════

/// 自适应线性进度条 — 个人页经验进度等细条场景。
///
/// 风格差异：
/// - MD3：primary 色，4px 标准 M3 高度，圆角 2。
/// - Miuix：[MiuixLinearProgressIndicator]（tertiary 色，3px 中等高度，
///   全圆角；flutter_miuix 阶段1 起替换原 LinearProgressIndicator 近似实现）。
class AppProgressBar extends StatelessWidget {
  const AppProgressBar({
    super.key,
    required this.value,
    this.height,
  });

  /// 进度值 0.0–1.0。null 或非有限值视为 0。
  final double? value;

  /// 覆盖默认高度；不传则按风格解析。
  final double? height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = (value == null || !value!.isFinite) ? 0.0 : value!.clamp(0.0, 1.0);

    // 阶段5d-L1：M3 分支已移除；原生 Miuix 线性进度条（自带全圆角轨道），
    // 保留替换前的 tertiary 配色与 3px 高度。
    return MiuixLinearProgressIndicator(
      progress: v,
      height: height ?? 3.0,
      colors: MiuixProgressIndicatorColors(
        foregroundColor: cs.tertiary,
        disabledForegroundColor: cs.tertiary,
        backgroundColor: cs.surfaceContainerHighest,
      ),
    );
  }
}

