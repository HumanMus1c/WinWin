import 'package:flutter/widgets.dart';

import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/pages/setting/widgets/normal_item.dart';
import 'package:winwin/pages/setting/widgets/set_switch_item.dart';

/// 设置项数据模型基类（sealed）。
///
/// 移植自 PiliPlus 的 `SettingsModel`，去除 GetX 依赖。
/// 每个子类通过 [widget] getter 构造对应 UI。
@immutable
sealed class SettingsModel {
  final String? subtitle;
  final Widget? leading;
  final EdgeInsetsGeometry? contentPadding;
  final TextStyle? titleStyle;

  String? get title;
  Widget get widget;
  String get effectiveTitle;
  String? get effectiveSubtitle;

  const SettingsModel({
    this.subtitle,
    this.leading,
    this.contentPadding,
    this.titleStyle,
  });
}

/// 普通可点击项（标题 + 副标题 + leading + trailing + onTap）。
class NormalModel extends SettingsModel {
  @override
  final String? title;
  final ValueGetter<String>? getTitle;
  final ValueGetter<String>? getSubtitle;
  final Widget Function(AppTokens tokens)? getTrailing;
  final void Function(BuildContext context, VoidCallback setState)? onTap;

  const NormalModel({
    super.subtitle,
    super.leading,
    super.contentPadding,
    super.titleStyle,
    this.title,
    this.getTitle,
    this.getSubtitle,
    this.getTrailing,
    this.onTap,
  }) : assert(title != null || getTitle != null);

  const NormalModel.split({
    super.subtitle,
    super.leading,
    super.contentPadding,
    super.titleStyle,
    this.title,
    this.getTitle,
    this.getSubtitle,
    this.getTrailing,
  }) : onTap = null,
       assert(title != null || getTitle != null);

  @override
  String get effectiveTitle => title ?? getTitle!();
  @override
  String? get effectiveSubtitle => subtitle ?? getSubtitle?.call();

  @override
  Widget get widget => NormalItem(
        title: title,
        getTitle: getTitle,
        subtitle: subtitle,
        getSubtitle: getSubtitle,
        leading: leading,
        getTrailing: getTrailing,
        onTap: onTap,
        contentPadding: contentPadding,
        titleStyle: titleStyle,
      );
}

/// 开关项（绑定 setKey + 默认值 + onChanged + needReboot）。
class SwitchModel extends SettingsModel {
  @override
  final String? title;
  final String setKey;
  final bool defaultVal;
  final ValueChanged<bool>? onChanged;
  final bool needReboot;
  final void Function(BuildContext context)? onTap;

  const SwitchModel({
    super.subtitle,
    super.leading,
    super.contentPadding,
    super.titleStyle,
    required String this.title,
    required this.setKey,
    this.defaultVal = false,
    this.onChanged,
    this.needReboot = false,
    this.onTap,
  });

  const SwitchModel.split({
    required this.setKey,
    this.defaultVal = false,
    this.needReboot = false,
    this.onChanged,
    this.onTap,
  }) : title = null;

  @override
  String get effectiveTitle => title!;
  @override
  String? get effectiveSubtitle => subtitle;

  @override
  Widget get widget => SetSwitchItem(
        title: title!,
        subtitle: subtitle,
        setKey: setKey,
        defaultVal: defaultVal,
        onChanged: onChanged,
        needReboot: needReboot,
        leading: leading,
        onTap: onTap,
        contentPadding: contentPadding,
        titleStyle: titleStyle,
      );
}

/// 复合项：左侧点击进入子设置 + 右侧独立开关。
class SplitModel extends SettingsModel {
  const SplitModel({
    super.contentPadding,
    super.titleStyle,
    required this.normalModel,
    required this.switchModel,
  });

  final NormalModel normalModel;
  final SwitchModel switchModel;

  @override
  String? get effectiveSubtitle => normalModel.effectiveSubtitle;
  @override
  String get effectiveTitle => normalModel.effectiveTitle;
  @override
  String? get title => normalModel.title;

  @override
  Widget get widget => SetSwitchItem(
        title: effectiveTitle,
        subtitle: effectiveSubtitle,
        setKey: switchModel.setKey,
        defaultVal: switchModel.defaultVal,
        onChanged: switchModel.onChanged,
        needReboot: switchModel.needReboot,
        leading: normalModel.leading,
        onTap: switchModel.onTap,
        contentPadding: contentPadding,
        titleStyle: titleStyle,
        isSplit: true,
      );
}
