import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'package:winwin/common/widgets/miuix_overlay_panel.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/theme/app_colors.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_anchored_popup.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 投币浮层（对标 B 站官方网页投币弹层）。
///
/// B7-c6-4 反馈轮：由**居中对话框 + 文本单选行**改为
/// **锚定触发按钮的浮层 + 金币图形双选**：
/// - 位置：以 [anchorContext]（"投币"按钮）为锚点置于按钮正上方，空间不足翻转；
/// - 美术：数量选择为两枚金币磁贴（选中＝实心金币 + 强调色描边/底色，
///   未选＝线框金币 + 灰底）；
/// - 氛围：透明 barrier 不压暗页面（官方网页为轻浮层）。
///
/// 投币上限（2 枚）与登录校验仍由调用方把关，本层只管选择。
Future<void> showCoinDialog(
  BuildContext context, {
  required BuildContext anchorContext,
  required void Function(int count, bool withLike) onPay,
}) {
  final anchor = anchorRectInRootOverlay(anchorContext);
  int coinCount = 1;
  bool coinWithLike = false;
  return showAppDialog<void>(
    context: context,
    barrierColor: AppColors.transparent,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => _CoinPopup(
        anchor: anchor,
        coinCount: coinCount,
        coinWithLike: coinWithLike,
        onPick: (v) => setState(() => coinCount = v),
        onLikeChanged: (v) => setState(() => coinWithLike = v),
        onCancel: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          onPay(coinCount, coinWithLike);
        },
      ),
    ),
  );
}

class _CoinPopup extends StatelessWidget {
  const _CoinPopup({
    required this.anchor,
    required this.coinCount,
    required this.coinWithLike,
    required this.onPick,
    required this.onLikeChanged,
    required this.onCancel,
    required this.onConfirm,
  });

  /// "投币"按钮在根 Overlay 坐标系中的矩形（null＝锚点不可得）。
  final Rect? anchor;

  final int coinCount;
  final bool coinWithLike;
  final ValueChanged<int> onPick;
  final ValueChanged<bool> onLikeChanged;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final panel = MiuixOverlayPanel(
      title: '投币',
      icon: AppIcon(AppIcons.coin(active: true), size: 16, color: biliPink),
      child: SizedBox(
        width: 232,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _coinTile(context, 1)),
                const SizedBox(width: Style.md),
                Expanded(child: _coinTile(context, 2)),
              ],
            ),
            const SizedBox(height: Style.sm),
            MiuixCheckboxPreference(
              title: '同时点赞',
              value: coinWithLike,
              onChanged: onLikeChanged,
            ),
            const SizedBox(height: Style.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MiuixTextButton('取消', onPressed: onCancel),
                const SizedBox(width: Style.sm),
                AppPrimaryButton(onPressed: onConfirm, child: const Text('确定')),
              ],
            ),
          ],
        ),
      ),
    );
    final a = anchor;
    return Stack(
      children: [
        if (a != null)
          AppAnchoredPopup(anchor: a, child: panel)
        else
          // 锚点不可得（极端情况）退化为居中浮层，不阻塞投币流程。
          Positioned.fill(child: Center(child: panel)),
      ],
    );
  }

  /// 单个金币磁贴：金币图形 + 枚数（选中态用强调色描边与底色）。
  Widget _coinTile(BuildContext context, int count) {
    final cs = AppThemeHost.of(context).colors;
    final selected = coinCount == count;
    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.96,
      borderRadius: BorderRadius.circular(Style.radiusMd),
      onPressed: () => onPick(count),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Style.md),
        decoration: BoxDecoration(
          color: selected
              ? biliPink.withValues(alpha: 0.12)
              : AppColors.transparent,
          borderRadius: BorderRadius.circular(Style.radiusMd),
          border: Border.all(
            color: selected ? biliPink : cs.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.coin(active: selected),
              size: 26,
              color: selected ? biliPink : cs.onSurfaceVariant,
            ),
            const SizedBox(height: Style.xs),
            Text(
              '$count 枚',
              style: TextStyle(
                fontSize: 12,
                color: selected ? biliPink : cs.onSurface,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
