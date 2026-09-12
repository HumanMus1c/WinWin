import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/models/video/play_url.dart' show Volume;

/// 音频归一化/响度均衡模式（对标 PiliPlus AudioNormalization）。
enum AudioNormalization {
  disable('禁用'),
  dynaudnorm('动态压缩 (dynaudnorm)', 'dynaudnorm=g=5:f=250:r=0.9:p=0.5'),
  loudnorm('智能响度均衡 (loudnorm)', 'loudnorm=I=-14:LRA=11:TP=-1.5'),
  custom('自定义参数'),
  ;

  final String title;
  final String param;
  const AudioNormalization(this.title, [this.param = '']);

  static String getTitleFromConfig(String config) => switch (config) {
    '0' => disable.title,
    '1' => dynaudnorm.title,
    '2' => loudnorm.title,
    _ => config,
  };

  static String getParamFromConfig(String config) => switch (config) {
    '0' => disable.param,
    '1' => dynaudnorm.param,
    '2' => loudnorm.param,
    _ => config,
  };

  static final loudnormRegExp = RegExp(r'loudnorm=([^,]+)');

  /// 解析并生成 FFmpeg avfilter 滤镜字符串。
  ///
  /// 若有 B 站实测 [volume] 数据，基于其测算值应用单动线性 loudnorm；
  /// 否则使用回退方案（Pref.fallbackNormalization 或标准 -14 LUFS）。
  static String parse(Volume? volume, String param) {
    if (param.isEmpty || param == '0') return '';
    if (param == '1' || param.startsWith('dynaudnorm')) {
      return param.length == 1 ? dynaudnorm.param : param;
    }
    if (volume != null && volume.isNotEmpty) {
      if (loudnormRegExp.hasMatch(param)) {
        return param.replaceFirstMapped(
          loudnormRegExp,
          (i) =>
              'loudnorm=${volume.format(
                Map.fromEntries(
                  i.group(1)!.split(':').map((item) {
                    final parts = item.split('=');
                    return MapEntry(parts[0].toLowerCase(), num.tryParse(parts[1]) ?? 0);
                  }),
                ),
              )}',
        );
      }
      return 'loudnorm=${volume.format(const {'i': -14, 'lra': 11, 'tp': -1.5})}';
    } else {
      if (loudnormRegExp.hasMatch(param)) {
        return param;
      }
      final fallback = AudioNormalization.getParamFromConfig(Pref.fallbackNormalization);
      return fallback.isNotEmpty ? fallback : loudnorm.param;
    }
  }
}
