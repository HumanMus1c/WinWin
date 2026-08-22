import 'package:flutter/material.dart';
import '../../theme/style.dart';

/// iOS-style grouped list container — 12dp corners, surface color.
class IOSGroup extends StatelessWidget {
  final List<Widget> children;

  const IOSGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(Style.radiusMd),
      ),
      child: Column(children: _withDividers(context)),
    );
  }

  List<Widget> _withDividers(BuildContext context) {
    final result = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(_IOSDivider());
      }
    }
    return result;
  }
}

/// iOS-style clickable row — icon in rounded square + title + chevron.
class IOSClickableItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconTint;
  final VoidCallback? onTap;

  const IOSClickableItem({
    super.key,
    required this.icon,
    required this.title,
    required this.iconTint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: Style.lg),
        child: Row(
          children: [
            // Icon container — 30px rounded square
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconTint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: iconTint, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyLarge,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_right_rounded,
              color: theme.colorScheme.outline,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _IOSDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 58),
      child: Container(
        height: 0.5,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
      ),
    );
  }
}
