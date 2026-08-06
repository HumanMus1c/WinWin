import 'package:winwin/pages/setting/models/settings_model.dart';
import 'package:winwin/pages/setting/models/style_settings.dart';
import 'package:winwin/pages/setting/models/play_settings.dart';
import 'package:winwin/pages/setting/models/video_settings.dart';
import 'package:winwin/pages/setting/models/extra_settings.dart';

/// 设置分类枚举。
///
/// 移植自 PiliPlus 的 `SettingType`，仅保留 WinWin 桌面端需要的分类。
enum SettingType {
  styleSetting('外观设置'),
  playSetting('播放器设置'),
  videoSetting('音视频设置'),
  extraSetting('其它设置'),
  about('关于'),
  ;

  final String title;
  const SettingType(this.title);

  List<SettingsModel> get settings => switch (this) {
        .styleSetting => styleSettings,
        .playSetting => playSettings,
        .videoSetting => videoSettings,
        .extraSetting => extraSettings,
        _ => const <SettingsModel>[],
      };
}
