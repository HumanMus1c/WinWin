import 'package:material_ui/material_ui.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/models/common/audio_normalization.dart';
import 'package:winwin/models/common/cdn_type.dart';
import 'package:winwin/pages/setting/models/settings_model.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';
import 'package:winwin/pages/setting/widgets/slider_dialog.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_dialogs.dart';

/// 音视频设置项列表。
///
/// 移植自 PiliPlus 的 `videoSettings`，仅保留桌面端适用项。
/// 画质/音质选择使用 [SelectDialog]。
List<SettingsModel> get videoSettings => [
      const SwitchModel(
        title: '开启硬解',
        subtitle: '以较低功耗播放视频，若异常卡死请关闭',
        leading: AppIcon(Icons.flash_on_outlined),
        setKey: SettingBoxKey.enableHA,
        defaultVal: true,
      ),
      const SwitchModel(
        title: '免登录1080P',
        subtitle: '免登录查看1080P视频',
        leading: AppIcon(Icons.hd_outlined),
        setKey: SettingBoxKey.p1080,
        defaultVal: true,
      ),
      NormalModel(
        title: '默认画质',
        leading: AppIcon(Icons.video_settings_outlined),
        getSubtitle: () => '当前画质：${_videoQualityDesc(Pref.defaultVideoQa)}',
        onTap: (context, setState) async {
          final res = await showSelectDialog<int>(
            context,
            title: '默认画质',
            value: Pref.defaultVideoQa,
            values: _videoQualityValues,
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.defaultVideoQa, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '默认音质',
        leading: AppIcon(Icons.music_video_outlined),
        getSubtitle: () => '当前音质：${_audioQualityDesc(Pref.defaultAudioQa)}',
        onTap: (context, setState) async {
          final res = await showSelectDialog<int>(
            context,
            title: '默认音质',
            value: Pref.defaultAudioQa,
            values: _audioQualityValues,
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.defaultAudioQa, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '音频响度均衡',
        leading: AppIcon(Icons.equalizer_outlined),
        getSubtitle: () =>
            '当前配置：${AudioNormalization.getTitleFromConfig(Pref.audioNormalization)}',
        onTap: (context, setState) async {
          final res = await showSelectDialog<String>(
            context,
            title: '音频响度均衡',
            value: Pref.audioNormalization,
            values: const [
              ('0', '禁用'),
              ('2', '智能响度均衡 (loudnorm) - 推荐'),
              ('1', '动态压缩 (dynaudnorm)'),
            ],
          );
          if (res != null) {
            Pref.audioNormalization = res;
            setState();
          }
        },
      ),
      NormalModel(
        title: 'CDN 服务节点',
        leading: AppIcon(Icons.cloud_outlined),
        getSubtitle: () =>
            '当前使用：${Pref.defaultCDNService.desc}，如遇缓冲频繁请尝试切换',
        onTap: (context, setState) async {
          final res = await showSelectDialog<CDNService>(
            context,
            title: 'CDN 服务节点',
            value: Pref.defaultCDNService,
            values: CDNService.values.map((i) => (i, i.desc)).toList(),
          );
          if (res != null) {
            Pref.defaultCDNService = res;
            setState();
          }
        },
      ),
      NormalModel(
        title: '硬件解码模式',
        leading: AppIcon(Icons.memory),
        getSubtitle: () => '当前模式：${Pref.hardwareDecoding}',
        onTap: (context, setState) async {
          final res = await showSelectDialog<String>(
            context,
            title: '硬件解码模式',
            value: Pref.hardwareDecoding,
            values: const [
              ('auto', '自动选择'),
              ('auto-copy', '自动选择（复制）'),
              ('d3d11va', 'D3D11 (Windows)'),
              ('dxva2', 'DXVA2'),
              ('no', '软解'),
            ],
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.hardwareDecoding, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '视频同步模式',
        leading: AppIcon(AppIcons.refresh()),
        getSubtitle: () => '当前模式：${Pref.videoSync}',
        onTap: (context, setState) async {
          final res = await showSelectDialog<String>(
            context,
            title: '视频同步模式',
            value: Pref.videoSync,
            values: const [
              ('audio', '音频同步（默认）'),
              ('display-resample', '显示同步+重采样'),
              ('display-desync', '显示同步（不重采样）'),
              ('display-vdrop', '显示同步+丢帧'),
            ],
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.videoSync, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '缓冲大小',
        leading: AppIcon(Icons.storage),
        getSubtitle: () => '当前：${Pref.bufferSize.toStringAsFixed(1)} MB',
        onTap: (context, setState) async {
          final res = await showAppDialog<double>(
            context: context,
            builder: (context) => AppSliderDialog(
              title: '缓冲大小',
              value: Pref.bufferSize,
              min: 1,
              max: 64,
              divisions: 63,
              suffix: ' MB',
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.bufferSize, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '缓冲时长',
        leading: AppIcon(AppIcons.timer()),
        getSubtitle: () => '当前：${Pref.bufferSec.toStringAsFixed(0)} 秒',
        onTap: (context, setState) async {
          final res = await showAppDialog<double>(
            context: context,
            builder: (context) => AppSliderDialog(
              title: '缓冲时长',
              value: Pref.bufferSec,
              min: 4,
              max: 60,
              divisions: 56,
              suffix: ' 秒',
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.bufferSec, res);
            setState();
          }
        },
      ),
      SwitchModel(
        title: '显示在线人数',
        leading: AppIcon(AppIcons.people()),
        setKey: SettingBoxKey.enableOnlineTotal,
        defaultVal: false,
      ),
    ];

// ── 画质/音质常量 ──

const List<(int, String)> _videoQualityValues = [
  (127, '8K 超高清'),
  (126, '杜比视界'),
  (125, 'HDR 真彩'),
  (120, '4K 超清'),
  (116, '1080P 高帧率'),
  (112, '1080P+ 高码率'),
  (80, '1080P 高清'),
  (74, '720P 高帧率'),
  (64, '720P 高清'),
  (48, '480P 清晰'),
  (32, '360P 流畅'),
  (16, '360P 流畅（低码率）'),
];

String _videoQualityDesc(int code) {
  for (final (c, desc) in _videoQualityValues) {
    if (c == code) return desc;
  }
  return '未知 ($code)';
}

const List<(int, String)> _audioQualityValues = [
  (30251, 'Hi-Res 无损'),
  (30255, 'ATMOS 全景声'),
  (30250, '杜比环绕声'),
  (30280, '高品质'),
  (30232, '128K'),
  (30216, '64K（低流量）'),
];

String _audioQualityDesc(int code) {
  for (final (c, desc) in _audioQualityValues) {
    if (c == code) return desc;
  }
  return '未知 ($code)';
}
