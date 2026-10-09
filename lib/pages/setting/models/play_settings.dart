import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/pages/setting/models/settings_model.dart';
import 'package:winwin/theme/app_icons.dart';

/// 播放器设置项列表。
///
/// 移植自 PiliPlus 的 `playSettings`，仅保留桌面端适用项。
List<SettingsModel> get playSettings => [
      SwitchModel(
        title: '弹幕开关',
        subtitle: '是否展示弹幕',
        leading: AppIcon(AppIcons.danmakuCount()),
        setKey: SettingBoxKey.enableShowDanmaku,
        defaultVal: true,
      ),
      SwitchModel(
        title: '自动播放',
        subtitle: '进入详情页自动播放',
        leading: AppIcon(AppIcons.autoplay()),
        setKey: SettingBoxKey.autoPlayEnable,
        defaultVal: false,
      ),
      SwitchModel(
        title: '自动进入全屏',
        subtitle: '进入详情页自动全屏播放',
        leading: AppIcon(AppIcons.fullscreen(active: false)),
        setKey: SettingBoxKey.enableAutoEnter,
        defaultVal: false,
      ),
      SwitchModel(
        title: '自动退出全屏',
        subtitle: '视频结束自动退出全屏',
        leading: AppIcon(AppIcons.fullscreen(active: true)),
        setKey: SettingBoxKey.enableAutoExit,
        defaultVal: true,
      ),
      SwitchModel(
        title: '后台播放',
        subtitle: '窗口最小化时继续播放音频',
        leading: AppIcon(AppIcons.pip()),
        setKey: SettingBoxKey.enableBackgroundPlay,
        defaultVal: true,
      ),
      SwitchModel(
        title: '双击快退/快进',
        subtitle: '左侧双击快退/右侧双击快进，关闭则双击均为暂停/播放',
        leading: AppIcon(AppIcons.touchAction()),
        setKey: SettingBoxKey.enableQuickDouble,
        defaultVal: true,
      ),
      SwitchModel(
        title: '全屏显示锁定按钮',
        leading: AppIcon(AppIcons.lockOutline()),
        setKey: SettingBoxKey.showFsLockBtn,
        defaultVal: true,
      ),
      SwitchModel(
        title: '全屏显示截图按钮',
        leading: AppIcon(AppIcons.screenshotButton()),
        setKey: SettingBoxKey.showFsScreenshotBtn,
        defaultVal: true,
      ),
      SwitchModel(
        title: '键盘控制',
        subtitle: '空格暂停/方向键快进快退/全屏切换等',
        leading: AppIcon(AppIcons.keyboardControl()),
        setKey: SettingBoxKey.keyboardControl,
        defaultVal: true,
      ),
      SwitchModel(
        title: '暂停时最小化',
        subtitle: '窗口最小化时自动暂停播放',
        leading: AppIcon(AppIcons.pause(active: false)),
        setKey: SettingBoxKey.pauseOnMinimize,
        defaultVal: false,
      ),
      SwitchModel(
        title: '播放器折叠时自动暂停',
        subtitle: '详情页滚动使播放器收缩为小窗时自动暂停，展开后自动恢复',
        leading: AppIcon(AppIcons.pip()),
        setKey: SettingBoxKey.collapseAutoPause,
        defaultVal: true,
      ),
    ];
