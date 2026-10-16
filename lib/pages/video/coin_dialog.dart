import 'package:flutter/widgets.dart';

import 'package:winwin/theme/style.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/common/widgets/app_dialog_shell.dart';

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
      builder: (context, setState) => AppAlertDialog(
        title: const Text('投币'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // B7-c6-4：Material RadioListTile/CheckboxListTile → Miuix 偏好行。
            MiuixRadioButtonPreference(
              title: '投 1 枚硬币',
              selected: coinCount == 1,
              onClick: () => setState(() => coinCount = 1),
            ),
            MiuixRadioButtonPreference(
              title: '投 2 枚硬币',
              selected: coinCount == 2,
              onClick: () => setState(() => coinCount = 2),
            ),
            const SizedBox(height: Style.xs),
            MiuixCheckboxPreference(
              title: '同时点赞',
              value: coinWithLike,
              onChanged: (v) => setState(() => coinWithLike = v),
            ),
          ],
        ),
        actions: [
          MiuixTextButton('取消', onPressed: () => Navigator.of(context).pop()),
          AppPrimaryButton(onPressed: () {
              Navigator.of(context).pop();
              onPay(coinCount, coinWithLike);
            }, child: const Text('确定')),
        ],
      ),
    ),
  );
}
