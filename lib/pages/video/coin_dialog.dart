import 'package:material_ui/material_ui.dart';

import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_dialogs.dart';

/// 投币对话框（对标 PiliPlus `pages/video/pay_coins` / BiliPai CoinDialog）。
///
/// 选择投币数量（1 或 2 枚，上限 2）并可勾选「同时点赞」，
/// 确认后回调 [onPay]。
Future<void> showCoinDialog(
  BuildContext context, {
  required void Function(int count, bool withLike) onPay,
}) {
  int coinCount = 1;
  bool coinWithLike = false;
  return showAppDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('投币'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<int>(
              groupValue: coinCount,
              onChanged: (v) => setState(() => coinCount = v ?? 1),
              child: Column(
                children: [
                  RadioListTile<int>(
                    value: 1,
                    activeColor: biliPink,
                    title: const Text('投 1 枚硬币'),
                  ),
                  RadioListTile<int>(
                    value: 2,
                    activeColor: biliPink,
                    title: const Text('投 2 枚硬币'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Style.xs),
            CheckboxListTile(
              value: coinWithLike,
              activeColor: biliPink,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('同时点赞'),
              onChanged: (v) => setState(() => coinWithLike = v ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onPay(coinCount, coinWithLike);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}
