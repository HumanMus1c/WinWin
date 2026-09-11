import 'package:flutter/material.dart';

import 'package:winwin/pages/setting/setting_type.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_components.dart';

/// 通用设置列表：按 [settingType] 渲染对应的设置项列表。
///
/// 移植自 PiliPlus 的 `CommonSetting`，去除 GetX 依赖。
/// [showAppBar] 为 false 时用于桌面端双栏右侧（无独立 AppBar）。
class CommonSetting extends StatefulWidget {
  const CommonSetting({
    super.key,
    required this.settingType,
    this.showAppBar = true,
  });

  final bool showAppBar;
  final SettingType settingType;

  @override
  State<CommonSetting> createState() => _CommonSettingState();
}

class _CommonSettingState extends State<CommonSetting> {
  @override
  Widget build(BuildContext context) {
    final style = InheritedUiStyle.of(context);
    final settings = widget.settingType.settings;
    final showAppBar = widget.showAppBar;
    final padding = MediaQuery.viewPaddingOf(context);
    return Scaffold(
      appBar: showAppBar ? AppBar(title: Text(widget.settingType.title)) : null,
      body: ListView(
        key: ValueKey('${widget.settingType.name}_${style.name}'),
        padding: EdgeInsets.only(
          left: showAppBar ? padding.left + Style.md : Style.md,
          right: showAppBar ? padding.right + Style.md : Style.md,
          top: Style.md,
          bottom: padding.bottom + 100,
        ),
        children: [
          AppGroup(
            children: settings.map((s) => s.widget).toList(),
          ),
        ],
      ),
    );
  }
}

