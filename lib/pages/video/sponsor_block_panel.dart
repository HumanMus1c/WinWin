import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'package:winwin/common/widgets/app_chip.dart';
import 'package:winwin/common/widgets/miuix_dialog_shell.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/player/sponsorblock_usecase.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/pages/video/player_controller.dart';
import 'package:winwin/plugin/api/plugin_manager.dart';
import 'package:winwin/plugin/builtin/sponsor_block/sponsor_block_plugin.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 播放页「空降助手」面板。
///
/// 设计参考：
/// - PiliPlus：顶部控制栏的「提交片段 / 片段信息」图标 + 片段列表；
/// - BiliPai：控制栏「提交片段」入口、开始/结束边界标记、提交前确认、
///   片段列表投票与跳过，以及禁止在未开启社区上报时提交。
///
/// 返回一个“关闭面板才完成”的 Future，供 `PlayerPanel._openSuspending`
/// 挂起控制条自动隐藏。
Future<void> showSponsorBlockPanel(
  BuildContext context, {
  required WinWinPlayerController controller,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _SponsorBlockPanel(controller: controller),
  );
}

class _SponsorBlockPanel extends StatefulWidget {
  const _SponsorBlockPanel({required this.controller});

  final WinWinPlayerController controller;

  @override
  State<_SponsorBlockPanel> createState() => _SponsorBlockPanelState();
}

class _SponsorBlockPanelState extends State<_SponsorBlockPanel> {
  static const List<SponsorBlockCategory> _reportCategories = [
    SponsorBlockCategory.sponsor,
    SponsorBlockCategory.selfPromo,
    SponsorBlockCategory.interaction,
    SponsorBlockCategory.intro,
    SponsorBlockCategory.outro,
    SponsorBlockCategory.preview,
    SponsorBlockCategory.filler,
    SponsorBlockCategory.musicOfftopic,
  ];

  late final TextEditingController _startController;
  late final TextEditingController _endController;

  SponsorBlockPlugin? _plugin;
  bool _enabled = false;
  bool _consent = false;
  bool _loadingSegments = false;
  bool _submitting = false;
  String _category = SponsorBlockCategory.sponsor.wireName;
  String _actionType = 'skip';
  String? _message;
  List<SponsorBlockSegment> _segments = const [];

  @override
  void initState() {
    super.initState();
    final manager = PluginManager.maybeInstance;
    _plugin = manager?.find<SponsorBlockPlugin>();
    _enabled = manager?.isEnabled(SponsorBlockPlugin.pluginId) ?? false;
    _consent = _plugin?.communityContributionEnabled ?? false;
    final currentSeconds =
        widget.controller.position.value.inMilliseconds / 1000.0;
    _startController = TextEditingController(
      text: _formatTime(currentSeconds),
    );
    _endController = TextEditingController(
      text: _formatTime(currentSeconds),
    );
    _segments = widget.controller.sponsorBlockSegments;
    if (_enabled && _segments.isEmpty) {
      unawaited(_loadSegments());
    }
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  Future<void> _loadSegments() async {
    if (!mounted) return;
    setState(() => _loadingSegments = true);
    try {
      final segments = await widget.controller.refreshSponsorBlockSegments();
      if (!mounted) return;
      setState(() {
        _segments = segments;
        _loadingSegments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSegments = false);
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    final manager = PluginManager.maybeInstance;
    if (manager == null) return;
    final ok = await manager.setEnabled(SponsorBlockPlugin.pluginId, value);
    if (!mounted) return;
    setState(() => _enabled = ok ? value : !value);
    if (!ok) {
      showToast(context, '空降助手状态切换失败，请查看运行日志');
    } else if (value) {
      unawaited(_loadSegments());
    } else {
      setState(() => _segments = const []);
    }
  }

  Future<void> _toggleConsent(bool value) async {
    final plugin = _plugin;
    if (plugin == null) return;
    await plugin.setCommunityContributionEnabled(value);
    if (!mounted) return;
    setState(() => _consent = value);
  }

  void _useCurrent(bool start) {
    final seconds = widget.controller.position.value.inMilliseconds / 1000.0;
    final text = _formatTime(seconds);
    if (start) {
      _startController.text = text;
    } else {
      _endController.text = text;
    }
    setState(() {
      _message = null;
    });
  }

  Future<void> _submit() async {
    final start = _parseTime(_startController.text);
    final end = _parseTime(_endController.text);
    if (start == null || end == null) {
      setState(() => _message = '时间格式无效，请使用 mm:ss 或 hh:mm:ss');
      return;
    }
    if (end <= start) {
      setState(() => _message = '结束时间必须晚于开始时间');
      return;
    }
    final durationSeconds =
        widget.controller.duration.value.inMilliseconds / 1000.0;
    if (durationSeconds > 0 && end > durationSeconds + 1.0) {
      setState(() => _message = '结束时间超出视频时长');
      return;
    }
    if (!_enabled) {
      setState(() => _message = '请先开启空降助手');
      return;
    }
    if (!_consent) {
      setState(() => _message = '请先允许上报社区片段');
      return;
    }

    setState(() {
      _submitting = true;
      _message = null;
    });
    final result = await widget.controller.submitSponsorSegment(
      startSeconds: start,
      endSeconds: end,
      category: _category,
      actionType: _actionType,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _message = result.isSuccess
          ? '已提交，等待社区审核'
          : (result.error ?? '上报失败');
      if (result.isSuccess) {
        _segments = widget.controller.sponsorBlockSegments;
      }
    });
  }

  Future<void> _vote(SponsorBlockSegment segment, bool useful) async {
    final error = await widget.controller.voteSponsorSegment(
      segment: segment,
      useful: useful,
    );
    if (!mounted) return;
    showToast(context, error ?? '投票成功');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return MiuixDialogShell(
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Style.lg,
          vertical: Style.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('空降助手', style: tokens.text.titleMedium),
                const Spacer(),
                MiuixIconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: AppIcon(AppIcons.clear()),
                ),
              ],
            ),
            const MiuixHorizontalDivider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: Style.sm),
                children: [
                  _SwitchRow(
                    title: '空降助手',
                    subtitle: _enabled
                        ? '已开启：自动跳过社区标注片段'
                        : '开启后自动跳过社区标注片段',
                    value: _enabled,
                    onChanged: _toggleEnabled,
                  ),
                  const SizedBox(height: Style.sm),
                  const MiuixHorizontalDivider(),
                  _sectionTitle(tokens, '上报片段'),
                  _TimeRow(
                    label: '开始',
                    controller: _startController,
                    onUseCurrent: () => _useCurrent(true),
                  ),
                  _TimeRow(
                    label: '结束',
                    controller: _endController,
                    onUseCurrent: () => _useCurrent(false),
                  ),
                  const SizedBox(height: Style.sm),
                  Text('片段类别', style: tokens.text.labelLarge),
                  const SizedBox(height: Style.xs),
                  Wrap(
                    spacing: Style.sm,
                    runSpacing: Style.sm,
                    children: [
                      for (final category in _reportCategories)
                        AppFilterChip(
                          label: Text(category.label),
                          selected: _category == category.wireName,
                          onSelected: (selected) {
                            if (!selected) return;
                            setState(() {
                              _category = category.wireName;
                              if (!_allowedActions(category)
                                  .contains(_actionType)) {
                                _actionType =
                                    _allowedActions(category).first;
                              }
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: Style.md),
                  Text('动作类型', style: tokens.text.labelLarge),
                  const SizedBox(height: Style.xs),
                  Wrap(
                    spacing: Style.sm,
                    runSpacing: Style.sm,
                    children: [
                      for (final action in _allowedActions(
                        SponsorBlockCategory.fromString(_category),
                      ))
                        AppFilterChip(
                          label: Text(_actionLabel(action)),
                          selected: _actionType == action,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _actionType = action);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: Style.md),
                  _SwitchRow(
                    title: '允许上报社区片段',
                    subtitle: '提交会发送类别、时间段、视频标识和匿名用户 ID 至 '
                        '${_plugin?.communityServerUrl ?? 'bsbsb.top'}',
                    value: _consent,
                    onChanged: _toggleConsent,
                  ),
                  const SizedBox(height: Style.md),
                  SizedBox(
                    width: double.infinity,
                    child: MiuixButton(
                      onPressed: (!_enabled || !_consent || _submitting)
                          ? null
                          : _submit,
                      colors: MiuixButtonDefaults.buttonColorsPrimary(context),
                      child: Text(_submitting ? '提交中…' : '确认提交片段'),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: Style.sm),
                    Text(
                      _message!,
                      style: tokens.text.bodySmall?.copyWith(
                        color: _message!.contains('成功') ||
                                _message!.contains('已提交')
                            ? tokens.colors.primary
                            : tokens.colors.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: Style.lg),
                  const MiuixHorizontalDivider(),
                  _sectionTitle(
                    tokens,
                    '社区片段（${_segments.length}）',
                    trailing: MiuixTextButton(
                      '刷新',
                      onPressed: _loadingSegments ? null : _loadSegments,
                    ),
                  ),
                  if (_loadingSegments)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: Style.md),
                      child: Center(child: Text('加载中…')),
                    )
                  else if (_segments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Style.md),
                      child: Text(
                        _enabled ? '当前视频暂无社区片段' : '开启空降助手后加载社区片段',
                        style: tokens.text.bodySmall?.copyWith(
                          color: tokens.colors.outline,
                        ),
                      ),
                    )
                  else
                    for (final segment in _segments)
                      _SegmentRow(
                        segment: segment,
                        onSkip: () {
                          Navigator.of(context).pop();
                          widget.controller.seek(
                            Duration(
                              milliseconds: (segment.end * 1000).toInt(),
                            ),
                          );
                        },
                        onVote: (useful) => _vote(segment, useful),
                      ),
                  const SizedBox(height: Style.md),
                  Text(
                    '片段数据来自 bsbsb.top。上报默认关闭，且每次提交都需要在此面板确认。',
                    style: tokens.text.bodySmall?.copyWith(
                      color: tokens.colors.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(AppTokens tokens, String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Style.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: tokens.text.labelMedium?.copyWith(
                color: tokens.colors.outline,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  static List<String> _allowedActions(SponsorBlockCategory category) {
    switch (category) {
      case SponsorBlockCategory.sponsor:
      case SponsorBlockCategory.selfPromo:
        return const ['skip', 'mute', 'full'];
      case SponsorBlockCategory.interaction:
      case SponsorBlockCategory.intro:
      case SponsorBlockCategory.outro:
      case SponsorBlockCategory.preview:
      case SponsorBlockCategory.filler:
        return const ['skip', 'mute'];
      case SponsorBlockCategory.musicOfftopic:
      case SponsorBlockCategory.unknown:
        return const ['skip'];
    }
  }

  static String _actionLabel(String action) => switch (action) {
        'skip' => '跳过',
        'mute' => '静音',
        'full' => '整段标记',
        _ => action,
      };

  static String _formatTime(double seconds) {
    final total = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final secs = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = secs.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  static double? _parseTime(String raw) {
    final parts = raw.trim().split(':');
    if (parts.isEmpty || parts.length > 3) return null;
    var total = 0.0;
    for (final part in parts) {
      final value = double.tryParse(part.trim());
      if (value == null || value < 0) return null;
      total = total * 60 + value;
    }
    return total;
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.controller,
    required this.onUseCurrent,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onUseCurrent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Style.sm),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(label)),
          Expanded(
            child: AppTextField(
              controller: controller,
              hint: 'mm:ss 或 hh:mm:ss',
            ),
          ),
          const SizedBox(width: Style.sm),
          MiuixTextButton('取当前进度', onPressed: onUseCurrent),
        ],
      ),
    );
  }
}

class _SegmentRow extends StatelessWidget {
  const _SegmentRow({
    required this.segment,
    required this.onSkip,
    required this.onVote,
  });

  final SponsorBlockSegment segment;
  final VoidCallback onSkip;
  final ValueChanged<bool> onVote;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Style.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${segment.category.label} · '
                  '${_SponsorBlockPanelState._formatTime(segment.start)} – '
                  '${_SponsorBlockPanelState._formatTime(segment.end)}',
                  style: tokens.text.bodyMedium,
                ),
              ),
              MiuixTextButton('跳过', onPressed: onSkip),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  segment.uuid.isEmpty || segment.uuid.length < 8
                      ? '社区片段'
                      : 'ID ${segment.uuid.substring(0, 8)}…',
                  style: tokens.text.labelSmall?.copyWith(
                    color: tokens.colors.outline,
                  ),
                ),
              ),
              MiuixTextButton('有用', onPressed: () => onVote(true)),
              MiuixTextButton('不准确', onPressed: () => onVote(false)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: tokens.text.bodyLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: tokens.text.bodySmall?.copyWith(
                  color: tokens.colors.outline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: Style.md),
        MiuixSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
