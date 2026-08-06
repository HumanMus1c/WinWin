import 'package:flutter/material.dart';

import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/pages/setting/models/settings_model.dart';
import 'package:winwin/pages/setting/widgets/select_dialog.dart';

/// 音视频设置项列表。
///
/// 移植自 PiliPlus 的 `videoSettings`，仅保留桌面端适用项。
/// 画质/音质选择使用 [SelectDialog]。
List<SettingsModel> get videoSettings => [
      const SwitchModel(
        title: '开启硬解',
        subtitle: '以较低功耗播放视频，若异常卡死请关闭',
        leading: Icon(Icons.flash_on_outlined),
        setKey: SettingBoxKey.enableHA,
        defaultVal: true,
      ),
      const SwitchModel(
        title: '免登录1080P',
        subtitle: '免登录查看1080P视频',
        leading: Icon(Icons.hd_outlined),
        setKey: SettingBoxKey.p1080,
        defaultVal: true,
      ),
      NormalModel(
        title: '默认画质',
        leading: const Icon(Icons.video_settings_outlined),
        getSubtitle: () => '当前画质：${_videoQualityDesc(Pref.defaultVideoQa)}',
        onTap: (context, setState) async {
          final res = await showDialog<int>(
            context: context,
            builder: (context) => SelectDialog<int>(
              title: '默认画质',
              value: Pref.defaultVideoQa,
              values: _videoQualityValues,
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.defaultVideoQa, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '默认音质',
        leading: const Icon(Icons.music_video_outlined),
        getSubtitle: () => '当前音质：${_audioQualityDesc(Pref.defaultAudioQa)}',
        onTap: (context, setState) async {
          final res = await showDialog<int>(
            context: context,
            builder: (context) => SelectDialog<int>(
              title: '默认音质',
              value: Pref.defaultAudioQa,
              values: _audioQualityValues,
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.defaultAudioQa, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '硬件解码模式',
        leading: const Icon(Icons.memory),
        getSubtitle: () => '当前模式：${Pref.hardwareDecoding}',
        onTap: (context, setState) async {
          final res = await showDialog<String>(
            context: context,
            builder: (context) => SelectDialog<String>(
              title: '硬件解码模式',
              value: Pref.hardwareDecoding,
              values: const [
                ('auto', '自动选择'),
                ('auto-copy', '自动选择（复制）'),
                ('d3d11va', 'D3D11 (Windows)'),
                ('dxva2', 'DXVA2'),
                ('no', '软解'),
              ],
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.hardwareDecoding, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '视频同步模式',
        leading: const Icon(Icons.sync),
        getSubtitle: () => '当前模式：${Pref.videoSync}',
        onTap: (context, setState) async {
          final res = await showDialog<String>(
            context: context,
            builder: (context) => SelectDialog<String>(
              title: '视频同步模式',
              value: Pref.videoSync,
              values: const [
                ('audio', '音频同步（默认）'),
                ('display-resample', '显示同步+重采样'),
                ('display-desync', '显示同步（不重采样）'),
                ('display-vdrop', '显示同步+丢帧'),
              ],
            ),
          );
          if (res != null) {
            await GStorage.setting.put(SettingBoxKey.videoSync, res);
            setState();
          }
        },
      ),
      NormalModel(
        title: '缓冲大小',
        leading: const Icon(Icons.storage),
        getSubtitle: () => '当前：${Pref.bufferSize.toStringAsFixed(1)} MB',
        onTap: (context, setState) async {
          final res = await showDialog<double>(
            context: context,
            builder: (context) => _BufferSliderDialog(
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
        leading: const Icon(Icons.timer),
        getSubtitle: () => '当前：${Pref.bufferSec.toStringAsFixed(0)} 秒',
        onTap: (context, setState) async {
          final res = await showDialog<double>(
            context: context,
            builder: (context) => _BufferSliderDialog(
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
      const SwitchModel(
        title: '显示在线人数',
        leading: Icon(Icons.people_outline),
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

/// 缓冲滑块对话框。
class _BufferSliderDialog extends StatefulWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;

  const _BufferSliderDialog({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    this.suffix = '',
  });

  @override
  State<_BufferSliderDialog> createState() => _BufferSliderDialogState();
}

class _BufferSliderDialogState extends State<_BufferSliderDialog> {
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_value.toStringAsFixed(_value == _value.roundToDouble() ? 0 : 1)}${widget.suffix}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _value,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            onChanged: (v) => setState(() => _value = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _value),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
