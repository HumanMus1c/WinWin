import 'package:flutter/material.dart';

/// 统一空状态组件（移植自 BiliPai v0.2.3-beta.3 `AppEmptyState`）。
///
/// 对标要点：
/// - 空态默认用 [Icons.search_rounded]（BiliPai 本期把空态图标从信封改为搜索语义）。
/// - 居中列布局，最大宽 520，支持主/次操作按钮。
/// - 前景色用 onSurfaceVariant（低饱和），错误态可用 [iconColor] 覆盖为 error 色。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon = Icons.search_rounded,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tint = iconColor ?? cs.onSurfaceVariant;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.09),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: tint),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 统一错误态组件（对标 BiliPai `AppErrorState`）：error 色图标 + 可选重试按钮。
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = '重试',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppEmptyState(
      icon: Icons.error_outline_rounded,
      iconColor: cs.error,
      title: '加载失败',
      subtitle: message,
      action: onRetry == null
          ? null
          : FilledButton.tonal(
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
    );
  }
}
