import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/app_typography.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

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
      : shapes = Theme.of(context).extension<AppShapes>() ?? AppShapes.material3,
        chrome = Theme.of(context).extension<AppChrome>() ?? AppChrome.material3,
        typo = Theme.of(context).extension<AppTypography>() ?? AppTypography.material3,
        style = InheritedUiStyle.of(context);

  final AppShapes shapes;
  final AppChrome chrome;
  final AppTypography typo;
  final UiStyle style;
}

// ════════════════════════════════════════════════════════════════
// AppCard
// ════════════════════════════════════════════════════════════════

/// 自适应卡片容器。
///
/// - MD3：surfaceContainerHighest + M3 tonal elevation。
/// - Miuix：surfaceContainer + tonalElevation=0 扁平 + 1.15× 大圆角。
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
    final renderer = resolvePrimitiveRenderer(t.style);

    final (bgColor, elevation) = switch (renderer) {
      PrimitiveRenderer.material3 => (
          color ?? cs.surfaceContainerHighest,
          t.chrome.elevation,
        ),
      PrimitiveRenderer.miuix => (
          color ?? cs.surfaceContainer,
          0.0,
        ),
    };

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(r),
      ),
      child: Material(
        color: Colors.transparent,
        elevation: elevation,
        borderRadius: BorderRadius.circular(r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(r),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(12),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// AppGroup
// ════════════════════════════════════════════════════════════════

/// 自适应分组容器（设置页 / 表单用）。
///
/// - MD3：surfaceContainer + 24dp 圆角，无分割线（靠间距分隔）。
/// - Miuix：surface + 20dp + 0 elevation，无分割线。
class AppGroup extends StatelessWidget {
  const AppGroup({super.key, required this.children, this.margin});

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final cs = Theme.of(context).colorScheme;
    final renderer = resolvePrimitiveRenderer(t.style);

    final bgColor = switch (renderer) {
      PrimitiveRenderer.material3 => cs.surfaceContainer,
      PrimitiveRenderer.miuix => cs.surface,
    };
    final r = switch (renderer) {
      PrimitiveRenderer.material3 => t.chrome.containerRadius,
      PrimitiveRenderer.miuix => t.shapes.large.x,
    };

    return Container(
      margin: margin,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(r),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: t.chrome.showDividers ? _withDividers(context, children) : children,
        ),
      ),
    );
  }

  List<Widget> _withDividers(BuildContext context, List<Widget> items) {
    final cs = Theme.of(context).colorScheme;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);
      if (i < items.length - 1) {
        result.add(
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Container(
              height: 0.5,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        );
      }
    }
    return result;
  }
}

// ════════════════════════════════════════════════════════════════
// AppPrimaryButton
// ════════════════════════════════════════════════════════════════

/// 自适应主按钮 — 统一渐变 primary→tertiary + 按压 0.96 弹簧（[AppPressFeedback] 触感）。
///
/// 形状按 [AppShapes.buttonShape] 切换（MD3 9dp 圆角 / Miuix 12dp 圆角）。
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
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          constraints: widget.expanded
              ? const BoxConstraints(minWidth: double.infinity)
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: ShapeDecoration(
            gradient: LinearGradient(
              colors: [
                cs.primary.withValues(alpha: enabled ? 1 : 0.4),
                cs.tertiary.withValues(alpha: enabled ? 1 : 0.4),
              ],
            ),
            shape: t.shapes.buttonShape,
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(
              color: cs.onPrimary,
              fontWeight: t.typo.titleWeight,
              fontSize: 15,
            ),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// AppSwitch
// ════════════════════════════════════════════════════════════════

/// 自适应开关。
///
/// - MD3：[Switch]（M3 标准 thumb 与轨道）。
/// - Miuix：[Switch] + 缩放 0.85 紧凑扁平化 thumb，贴合 Miuix 控件密度。
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final style = InheritedUiStyle.of(context);
    switch (resolvePrimitiveRenderer(style)) {
      case PrimitiveRenderer.material3:
        return Switch(value: value, onChanged: onChanged);
      case PrimitiveRenderer.miuix:
        return Transform.scale(
          scale: 0.85,
          child: Switch(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════
// AppListItem
// ════════════════════════════════════════════════════════════════

/// 自适应列表项 — 图标 + 标题 + 副标题 + 尾部。
///
/// - MD3：标准 [ListTile] + M3 ripple。
/// - Miuix：扁平 + 左侧色块条，无右箭头，中性灰背景。
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

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconTint;
  final Widget? trailing;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = iconTint ?? cs.primary;

    switch (resolvePrimitiveRenderer(t.style)) {
      case PrimitiveRenderer.material3:
        return ListTile(
          shape: borderRadius != null
              ? RoundedRectangleBorder(borderRadius: borderRadius!)
              : null,
          onTap: onTap,
          leading: Icon(icon, color: tint),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle!) : null,
          trailing: trailing,
        );
      case PrimitiveRenderer.miuix:
        return InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 24,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                Icon(icon, color: tint, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.outline,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════
// AppSegmentedControl
// ════════════════════════════════════════════════════════════════

/// 自适应分段控件。
///
/// - MD3：[SegmentedButton] 标准 M3 带边框容器。
/// - Miuix：tonal 胶囊滑动 Row，药丸高亮指示块。
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
    final t = _Tokens.of(context);
    final cs = Theme.of(context).colorScheme;

    switch (resolvePrimitiveRenderer(t.style)) {
      case PrimitiveRenderer.material3:
        return SegmentedButton<T>(
          segments: segments
              .map((e) => ButtonSegment<T>(
                    value: e.$1,
                    label: Text(e.$2),
                  ))
              .toList(),
          selected: {value},
          onSelectionChanged: (s) {
            if (s.isNotEmpty) onChanged(s.first);
          },
        );
      case PrimitiveRenderer.miuix:
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            borderRadius: t.shapes.pillBorder,
          ),
          padding: const EdgeInsets.all(3),
          child: Row(
            children: segments.map((e) {
              final selected = e.$1 == value;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(e.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? cs.primary : Colors.transparent,
                      borderRadius: t.shapes.pillBorder,
                    ),
                    child: Text(
                      e.$2,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                        fontWeight: t.typo.titleWeight,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════
// AppTextField / AppSearchField
// ════════════════════════════════════════════════════════════════

/// 自适应文本输入框。
///
/// - iOS：圆角填充 + 无边框。
/// - MD3：outlined + M3 label。
/// - Miuix：扁平填充 + 底部细线。
class AppTextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final cs = Theme.of(context).colorScheme;
    final renderer = resolvePrimitiveRenderer(t.style);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: renderer != PrimitiveRenderer.material3,
        fillColor: cs.surfaceContainerHighest,
        border: switch (renderer) {
          PrimitiveRenderer.material3 => OutlineInputBorder(
              borderRadius: t.shapes.smallBorder,
              borderSide: BorderSide(color: cs.outline),
            ),
          PrimitiveRenderer.miuix => UnderlineInputBorder(
              borderRadius: t.shapes.smallBorder,
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
        },
        enabledBorder: switch (renderer) {
          PrimitiveRenderer.material3 => OutlineInputBorder(
              borderRadius: t.shapes.smallBorder,
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
          PrimitiveRenderer.miuix => UnderlineInputBorder(
              borderRadius: t.shapes.smallBorder,
              borderSide: BorderSide(color: cs.outlineVariant),
            ),
        },
        focusedBorder: switch (renderer) {
          PrimitiveRenderer.material3 => OutlineInputBorder(
              borderRadius: t.shapes.smallBorder,
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          PrimitiveRenderer.miuix => UnderlineInputBorder(
              borderRadius: t.shapes.smallBorder,
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
        },
      ),
    );
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
      prefix: Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
      suffix: controller == null
          ? null
          : ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller!,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(Icons.close, size: 18),
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
  }) : assert(
          icon != null || count != null,
          'AppActionTile 需传入 icon 或 count 之一',
        );

  final IconData? icon;
  final String? count;
  final String label;
  final VoidCallback? onTap;
  final Color? iconTint;

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final renderer = resolvePrimitiveRenderer(t.style);

    final (contentColor, spacing, radius) = switch (renderer) {
      PrimitiveRenderer.material3 =>
        (iconTint ?? cs.primary, 6.0, t.shapes.small),
      PrimitiveRenderer.miuix => (iconTint ?? cs.onSurfaceVariant, 8.0, t.shapes.medium),
    };

    return Flexible(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.all(radius),
        child: ConstrainedBox(
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
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// AppProgressBar
// ════════════════════════════════════════════════════════════════

/// 自适应线性进度条 — 个人页经验进度等细条场景。
///
/// 风格差异：
/// - MD3：primary 色，4px 标准 M3 高度，圆角 2。
/// - Miuix：tertiary 色，3px 中等高度，全圆角。
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
    final t = _Tokens.of(context);
    final cs = Theme.of(context).colorScheme;
    final renderer = resolvePrimitiveRenderer(t.style);

    final v = (value == null || !value!.isFinite) ? 0.0 : value!.clamp(0.0, 1.0);
    final (trackColor, barColor, h, radius) = switch (renderer) {
      PrimitiveRenderer.material3 => (
          cs.surfaceContainerHighest,
          cs.primary,
          4.0,
          2.0,
        ),
      PrimitiveRenderer.miuix => (
          cs.surfaceContainerHighest,
          cs.tertiary,
          3.0,
          1.5,
        ),
    };

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height ?? h,
        backgroundColor: trackColor,
        valueColor: AlwaysStoppedAnimation<Color>(barColor),
        stopIndicatorColor: Colors.transparent,
      ),
    );
  }
}

