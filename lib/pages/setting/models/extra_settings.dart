import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/pages/setting/models/settings_model.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';
import 'package:winwin/theme/app_icons.dart';

/// 其它设置项列表。
///
/// 移植自 PiliPlus 的 `extraSettings`，仅保留桌面端适用项。
List<SettingsModel> get extraSettings => [
      // 网络设置
      SwitchModel(
        title: '启用 HTTP/2',
        subtitle: '使用 HTTP/2 协议，可能提升连接速度',
        leading: Icon(Icons.http),
        setKey: SettingBoxKey.enableHttp2,
        defaultVal: false,
      ),
      NormalModel(
        title: '重试次数',
        leading: AppIcon(AppIcons.refresh()),
        getSubtitle: () => '当前：${Pref.retryCount} 次',
        onTap: (context, setState) async {
          final res = await showSelectDialog<int>(
            context,
            title: '重试次数',
            value: Pref.retryCount,
            values: const [
              (0, '不重试'),
              (1, '1 次'),
              (2, '2 次'),
              (3, '3 次'),
              (5, '5 次'),
            ],
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.retryCount, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '重试间隔',
        leading: AppIcon(AppIcons.timer()),
        getSubtitle: () => '当前：${Pref.retryDelay} ms',
        onTap: (context, setState) async {
          final res = await showSelectDialog<int>(
            context,
            title: '重试间隔',
            value: Pref.retryDelay,
            values: const [
              (200, '200 ms'),
              (500, '500 ms'),
              (1000, '1 秒'),
              (2000, '2 秒'),
              (3000, '3 秒'),
            ],
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.retryDelay, res);
            setState();
          }
        },
      ),
      const SwitchModel(
        title: '启用系统代理',
        subtitle: '使用系统代理设置',
        leading: Icon(Icons.vpn_key),
        setKey: SettingBoxKey.enableSystemProxy,
        defaultVal: false,
      ),
      SwitchModel(
        title: '禁用 SSL 证书验证',
        subtitle: '⚠️ 不安全，仅在调试时使用',
        leading: Icon(Icons.security),
        setKey: SettingBoxKey.badCertificateCallback,
        defaultVal: false,
      ),

      // 推荐设置
      const SwitchModel(
        title: '使用 APP 端推荐',
        subtitle: '获取 APP 端推荐流（含更多分类信息）',
        leading: Icon(Icons.explore_outlined),
        setKey: SettingBoxKey.appRcmd,
        defaultVal: true,
      ),

      // 弹幕设置
      SwitchModel(
        title: '显示会员彩色弹幕',
        leading: AppIcon(AppIcons.palette()),
        setKey: SettingBoxKey.showVipDanmaku,
        defaultVal: true,
      ),
      const SwitchModel(
        title: '合并相同弹幕',
        subtitle: '将内容相同的弹幕合并显示',
        leading: Icon(Icons.merge),
        setKey: SettingBoxKey.mergeDanmaku,
        defaultVal: false,
      ),

      // 日志
      const SwitchModel(
        title: '启用日志',
        subtitle: '记录应用运行日志，用于问题排查',
        leading: Icon(Icons.article_outlined),
        setKey: SettingBoxKey.enableLog,
        defaultVal: true,
      ),

      // 历史记录暂停
      const SwitchModel(
        title: '暂停观看历史',
        subtitle: '不再记录观看历史',
        leading: Icon(Icons.history_toggle_off),
        setKey: 'historyPause',
        defaultVal: false,
      ),
    ];
