import 'package:flutter/material.dart';

import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/theme/ui_style.dart';
import 'package:winwin/theme/ui_style_notifier.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 三风格可视化预览页（Phase 7.8）。
///
/// 展示当前风格下的核心控件外观（按钮/开关/列表项/段控件/卡片），
/// 顶部提供 [AppSegmentedControl] 即时切换三风格，无需跳设置页。
/// 用于用户在选定风格前直观对比各风格差异。
class UiStylePreviewPage extends StatefulWidget {
  const UiStylePreviewPage({super.key});

  @override
  State<UiStylePreviewPage> createState() => _UiStylePreviewPageState();
}

class _UiStylePreviewPageState extends State<UiStylePreviewPage> {
  late UiStyle _current;
  bool _switchValue = true;

  @override
  void initState() {
    super.initState();
    _current = UiStyleNotifier.instance.value;
    UiStyleNotifier.instance.addListener(_onStyleChanged);
  }

  @override
  void dispose() {
    UiStyleNotifier.instance.removeListener(_onStyleChanged);
    super.dispose();
  }

  void _onStyleChanged() {
    if (mounted) setState(() => _current = UiStyleNotifier.instance.value);
  }

  Future<void> _switchStyle(UiStyle style) async {
    if (style == _current) return;
    await UiStyleNotifier.instance.setStyle(style);
    // _onStyleChanged 会触发 rebuild
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('风格预览'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Style.lg,
              vertical: Style.sm,
            ),
            child: AppSegmentedControl<UiStyle>(
              segments: UiStyle.values.map((e) => (e, e.label)).toList(),
              value: _current,
              onChanged: _switchStyle,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Style.lg,
          Style.md,
          Style.lg,
          Style.xxl * 2,
        ),
        children: [
          _SectionTitle(text: '当前风格：${_current.label}'),
          const SizedBox(height: Style.md),
          _buildButtonsGroup(theme),
          const SizedBox(height: Style.md),
          _buildSwitchGroup(theme),
          const SizedBox(height: Style.md),
          _buildListGroup(theme),
          const SizedBox(height: Style.md),
          _buildSegmentGroup(theme),
          const SizedBox(height: Style.md),
          _buildCardGroup(theme),
        ],
      ),
    );
  }

  Widget _buildButtonsGroup(ThemeData theme) {
    return AppGroup(
      children: [
        AppListItem(
          icon: Icons.touch_app_outlined,
          title: '主按钮（Primary）',
          subtitle: '渐变 primary→tertiary + 按压动画',
          iconTint: theme.colorScheme.primary,
          trailing: AppPrimaryButton(
            onPressed: () {},
            child: const Text('按钮'),
          ),
        ),
        AppListItem(
          icon: Icons.check_circle_outline,
          title: '填充按钮（Filled）',
          subtitle: 'M3 FilledButton 风格',
          iconTint: theme.colorScheme.primary,
          trailing: FilledButton(
            onPressed: () {},
            child: const Text('确定'),
          ),
        ),
        AppListItem(
          icon: Icons.logout,
          title: '文本按钮（Text）',
          subtitle: '低强调度操作',
          iconTint: theme.colorScheme.tertiary,
          trailing: TextButton(
            onPressed: () {},
            child: const Text('取消'),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchGroup(ThemeData theme) {
    return AppGroup(
      children: [
        AppListItem(
          icon: Icons.toggle_on_outlined,
          title: '开关（开启态）',
          subtitle: 'iOS Cupertino / M3 Switch / Miuix 缩放',
          iconTint: iosGreen,
          trailing: AppSwitch(
            value: _switchValue,
            onChanged: (v) => setState(() => _switchValue = v),
          ),
        ),
        AppListItem(
          icon: Icons.toggle_off_outlined,
          title: '开关（关闭态）',
          subtitle: '对比关闭态外观',
          iconTint: theme.colorScheme.outline,
          trailing: AppSwitch(
            value: !_switchValue,
            onChanged: (v) => setState(() => _switchValue = !v),
          ),
        ),
      ],
    );
  }

  Widget _buildListGroup(ThemeData theme) {
    return AppGroup(
      children: [
        AppListItem(
          icon: Icons.person_outline,
          title: '列表项 - 含图标',
          subtitle: '图标 + 标题 + 副标题 + chevron',
          iconTint: iosBlue,
          onTap: () {},
        ),
        AppListItem(
          icon: Icons.star_outline,
          title: '列表项 - 高亮',
          subtitle: '选中态强调色',
          iconTint: iosOrange,
          trailing: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildSegmentGroup(ThemeData theme) {
    return AppGroup(
      children: [
        AppListItem(
          icon: Icons.segment,
          title: '分段控件',
          subtitle: 'iOS Cupertino / M3 SegmentedButton / Miuix tonal',
          iconTint: theme.colorScheme.secondary,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Style.md,
            vertical: Style.sm,
          ),
          child: AppSegmentedControl<String>(
            segments: const [
              ('a', '选项 A'),
              ('b', '选项 B'),
              ('c', '选项 C'),
            ],
            value: 'a',
            onChanged: (_) {},
          ),
        ),
      ],
    );
  }

  Widget _buildCardGroup(ThemeData theme) {
    return AppCard(
      padding: const EdgeInsets.all(Style.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dashboard_customize_outlined,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                '卡片容器（AppCard）',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: Style.sm),
          Text(
            '卡片背景色、圆角、阴影均按当前 [UiStyle] 自动适配：'
            'iOS 连续曲率 + 扩散阴影；MD3 tonal elevation；Miuix 扁平 0 阴影。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 小节标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
  }
}
