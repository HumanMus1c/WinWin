import 'dart:io' show exit;

import 'package:flutter_miuix/miuix.dart' show MiuixPressFeedbackType, MiuixPressable, MiuixButton;
import 'package:material_ui/material_ui.dart';

import 'package:winwin/ui/components/app_components.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_scaffold.dart';

/// 用户协议门禁页（移植自 BiliPai v0.2.3-beta.3 `OnboardingScreen`）。
///
/// 交互对齐 BiliPai：列出若干强制条款，**全部勾选**后「我已知晓并同意」才可用；
/// 「我不同意」直接退出应用。确认状态由调用方通过 [onAgreed] 持久化。
///
/// 与 BiliPai 的差异：
/// - 条款文案按 WinWin「BiliPai 桌面移植版」定位改写（不含 Android 渠道宣传条款）。
/// - 主按钮承担「确认进入」的正向路径（BiliPai 将「不同意」设为主按钮，桌面端改为
///   更符合直觉的「确认=主按钮」，交互语义保持一致：未全勾选不可确认）。
class UserAgreementPage extends StatefulWidget {
  const UserAgreementPage({super.key, required this.onAgreed});

  /// 全部条款勾选并点击确认后回调（调用方负责持久化 + 切换到主界面）。
  final VoidCallback onAgreed;

  @override
  State<UserAgreementPage> createState() => _UserAgreementPageState();
}

class _UserAgreementPageState extends State<UserAgreementPage> {
  final Set<int> _checked = {};

  bool get _allChecked => _checked.length == _clauses.length;

  void _toggle(int index) {
    setState(() {
      if (_checked.contains(index)) {
        _checked.remove(index);
      } else {
        _checked.add(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

    return AppScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 顶部：品牌 + 标题 ──
                  AppIcon(AppIcons.play(active: true),
                    size: 56,
                    color: cs.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '欢迎使用 WinWin',
                    textAlign: TextAlign.center,
                    style: tokens.text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '开始之前，请阅读并确认以下条款',
                    textAlign: TextAlign.center,
                    style: tokens.text.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── 条款列表 ──
                  AppGroup(
                    children: [
                      for (var i = 0; i < _clauses.length; i++)
                        _ClauseTile(
                          clause: _clauses[i],
                          checked: _checked.contains(i),
                          onTap: () => _toggle(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // ── 底部双按钮 ──
                  Row(
                    children: [
                      Expanded(
                        child: MiuixButton(onPressed: () => exit(0), child: Text(
                            '我不同意',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: AppPrimaryButton(
                          expanded: true,
                          onPressed: _allChecked ? widget.onAgreed : null,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 3),
                            child: Text('我已知晓并同意'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '未勾选全部条款时无法继续；选择「我不同意」将退出应用。',
                    textAlign: TextAlign.center,
                    style: tokens.text.labelSmall?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单条条款数据。
class _Clause {
  const _Clause(this.icon, this.title, this.desc);
  final Widget icon;
  final String title;
  final String desc;
}

final List<_Clause> _clauses = [
  _Clause(
    AppIcon(AppIcons.clauseOpenSource()),
    '开源且免费',
    'WinWin 是基于 GPL-3.0 协议开源、完全免费的第三方哔哩哔哩桌面客户端，'
    '与哔哩哔哩官方无任何关联，仅供个人学习交流，不用于商业用途。',
  ),
  _Clause(
    AppIcon(AppIcons.clauseDisclaimer()),
    '免责与版权',
    '应用内所有内容数据均来自公开接口，版权归原作者及平台所有。'
    '本工具仅供学习与研究，请勿用于任何违反当地法律法规的用途。',
  ),
  _Clause(
    AppIcon(AppIcons.clauseFeedback()),
    '反馈与日志',
    '如遇崩溃或异常，本地会保存脱敏日志用于问题排查。'
    '欢迎通过项目仓库（GitHub）反馈问题以帮助改进。',
  ),
];

/// 只读条款列表（供「关于-开源协议」等入口查看；无勾选交互）。
class UserAgreementClauses extends StatelessWidget {
  const UserAgreementClauses({super.key});

  @override
  Widget build(BuildContext context) {
    return AppGroup(
      children: [
        for (final clause in _clauses)
          _ClauseTile(clause: clause, checked: false, showCheckbox: false),
      ],
    );
  }
}

/// 条款行：整行可点切换勾选 + 尾部 [Checkbox]。
class _ClauseTile extends StatelessWidget {
  const _ClauseTile({
    required this.clause,
    required this.checked,
    this.onTap,
    this.showCheckbox = true,
  });

  final _Clause clause;
  final bool checked;
  final VoidCallback? onTap;

  /// 只读查看（如「关于-开源协议」入口）时隐藏勾选框。
  final bool showCheckbox;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

    return MiuixPressable(
      feedbackType: MiuixPressFeedbackType.sink,
      sinkAmount: 0.98,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTheme(
              data: IconThemeData(size: 20, color: cs.primary),
              child: clause.icon,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clause.title,
                    style: tokens.text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    clause.desc,
                    style: tokens.text.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (showCheckbox)
              Checkbox(value: checked, onChanged: (_) => onTap?.call()),
          ],
        ),
      ),
    );
  }
}
