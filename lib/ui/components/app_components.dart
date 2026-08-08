import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:winwin/theme/app_chrome.dart';
import 'package:winwin/theme/app_shapes.dart';
import 'package:winwin/theme/app_typography.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// ─────────────────────────────────────────────────────────────────
/// 自适应基础控件集合（Phase 7.3）
///
/// 参照 BiliPai 的「同一 API、三种渲染」模式：每个控件入口读取
/// [InheritedUiStyle.of] 获取 [UiStyle]，再用 [resolvePrimitiveRenderer]
/// 分发到 `IOS / MATERIAL3 / MIUIX` 三条渲染路径。形状 / 阴影 / 字间距
/// 由 [AppShapes] / [AppChrome] / [AppTypography] Token 提供。
///
/// 切换 [UiStyleNotifier] 时整棵树重建，控件即时呈现对应风格。
/// ─────────────────────────────────────────────────────────────────

/// 从 context 读取三套 Token 的便捷封装。
class _Tokens {
  _Tokens.of(BuildContext context)
      : shapes = Theme.of(context).extension<AppShapes>() ?? AppShapes.ios,
        chrome = Theme.of(context).extension<AppChrome>() ?? AppChrome.ios,
        typo = Theme.of(context).extension<AppTypography>() ?? AppTypography.ios,
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
/// - iOS：surface + 扩散阴影 + 连续曲率圆角。
/// - MD3：surfaceContainer + M3 tonal elevation。
/// - Miuix：surfaceContainer + tonalElevation=0 扁平 + 大圆角。
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

    final (bgColor, elevation, shadow) = switch (renderer) {
      PrimitiveRenderer.ios => (
          color ?? cs.surface,
          0.0,
          <BoxShadow>[
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      PrimitiveRenderer.material3 => (
          color ?? cs.surfaceContainerHighest,
          t.chrome.elevation,
          const <BoxShadow>[],
        ),
      PrimitiveRenderer.miuix => (
          color ?? cs.surfaceContainer,
          0.0,
          const <BoxShadow>[],
        ),
    };

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(r),
        boxShadow: shadow,
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
/// - iOS：surface + 细分割线 + 中圆角。
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
      PrimitiveRenderer.ios => cs.surface,
      PrimitiveRenderer.material3 => cs.surfaceContainer,
      PrimitiveRenderer.miuix => cs.surface,
    };
    final r = switch (renderer) {
      PrimitiveRenderer.ios => t.shapes.medium.x,
      PrimitiveRenderer.material3 => t.chrome.containerRadius,
      PrimitiveRenderer.miuix => t.shapes.large.x,
    };

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: t.chrome.showDividers ? _withDividers(context, children) : children,
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

/// 自适应主按钮 — 统一渐变 primary→tertiary + 按压 0.96 弹簧。
///
/// 形状按 [AppShapes.buttonShape] 切换；iOS 用胶囊，MD3/Miuix 用圆角矩形。
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
    final shape = switch (resolvePrimitiveRenderer(t.style)) {
      PrimitiveRenderer.ios => t.shapes.pillShape,
      _ => t.shapes.buttonShape,
    };

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
            shape: shape,
            shadows: [
              if (enabled && resolvePrimitiveRenderer(t.style) == PrimitiveRenderer.ios)
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
            ],
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
/// - iOS：[CupertinoSwitch]（液态胶囊）。
/// - MD3：[Switch]（M3 默认 thumb）。
/// - Miuix：[Switch] + 缩放 0.85 扁平 thumb。
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final style = InheritedUiStyle.of(context);
    switch (resolvePrimitiveRenderer(style)) {
      case PrimitiveRenderer.ios:
        return CupertinoSwitch(value: value, onChanged: onChanged);
      case PrimitiveRenderer.material3:
        return Switch(value: value, onChanged: onChanged);
      case PrimitiveRenderer.miuix:
        return Transform.scale(
          scale: 0.85,
          child: Switch(value: value, onChanged: onChanged),
        );
    }
  }
}

// ════════════════════════════════════════════════════════════════
// AppListItem
// ════════════════════════════════════════════════════════════════

/// 自适应列表项 — 图标 + 标题 + 副标题 + 尾部。
///
/// - iOS：图标在圆角方块内 + chevron，54px 高。
/// - MD3：标准 [ListTile] + M3 ripple。
/// - Miuix：扁平 + 左侧色块条，无 chevron。
class AppListItem extends StatelessWidget {
  const AppListItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconTint,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconTint;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = _Tokens.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = iconTint ?? cs.primary;

    switch (resolvePrimitiveRenderer(t.style)) {
      case PrimitiveRenderer.ios:
        return InkWell(
          onTap: onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, color: tint, size: 18),
                ),
                const SizedBox(width: 12),
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
                trailing ??
                    Icon(Icons.keyboard_arrow_right_rounded,
                        color: cs.outline, size: 20),
              ],
            ),
          ),
        );
      case PrimitiveRenderer.material3:
        return ListTile(
          onTap: onTap,
          leading: Icon(icon, color: tint),
          title: Text(title),
          subtitle: subtitle != null ? Text(subtitle!) : null,
          trailing: trailing,
        );
      case PrimitiveRenderer.miuix:
        return InkWell(
          onTap: onTap,
          child: Container(
            height: 56,
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
                if (trailing != null) trailing!,
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
/// - iOS：[CupertinoSegmentedControl] 液态胶囊。
/// - MD3：[SegmentedButton] 带边框。
/// - Miuix：tonal 胶囊 TabRow。
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
      case PrimitiveRenderer.ios:
        final map = <T, Widget>{};
        for (final (v, label) in segments) {
          map[v] = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(label),
          );
        }
        return CupertinoSegmentedControl<T>(
          groupValue: value,
          children: map,
          onValueChanged: onChanged,
        );
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
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
        filled: renderer != PrimitiveRenderer.material3,
        fillColor: cs.surfaceContainerHighest,
        border: switch (renderer) {
          PrimitiveRenderer.ios => OutlineInputBorder(
              borderRadius: t.shapes.mediumBorder,
              borderSide: BorderSide.none,
            ),
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
          PrimitiveRenderer.ios => OutlineInputBorder(
              borderRadius: t.shapes.mediumBorder,
              borderSide: BorderSide.none,
            ),
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
          PrimitiveRenderer.ios => OutlineInputBorder(
              borderRadius: t.shapes.mediumBorder,
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
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
    final t = _Tokens.of(context);
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
