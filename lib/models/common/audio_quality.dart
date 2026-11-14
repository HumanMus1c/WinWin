/// 音质档位（移植自 PiliPlus `models/common/video/audio_quality.dart`）。
///
/// `code` 对应 B 站 DASH 音轨 id：
/// - 30251 Hi-Res 无损（`dash.flac.audio`）
/// - 30255 / 30250 杜比全景声（`dash.dolby.audio`）
/// - 30280 / 30232 / 30216 普通 AAC 音轨（`dash.audio`）
///
/// `rank` 越大音质越高。「按偏好档位选择」的语义与 PiliPlus
/// `VideoUtils.findTargetAudio` 一致：取不超过偏好档位的最高可用档；
/// 若全部可用档都高于偏好（如偏好 64K 但只有 192K+），回退最低可用档。
class AudioQuality {
  final int code;
  final String desc;
  final int rank;

  const AudioQuality(this.code, this.desc, {this.rank = 0});

  static const AudioQuality hiRes = AudioQuality(30251, 'Hi-Res 无损', rank: 60);
  static const AudioQuality dolby_30255 = AudioQuality(
    30255,
    '杜比全景声',
    rank: 50,
  );
  static const AudioQuality dolby_30250 = AudioQuality(
    30250,
    '杜比全景声',
    rank: 50,
  );
  static const AudioQuality k192 = AudioQuality(30280, '192K', rank: 40);
  static const AudioQuality k132 = AudioQuality(30232, '132K', rank: 30);
  static const AudioQuality k64 = AudioQuality(30216, '64K', rank: 20);

  static const List<AudioQuality> values = [
    hiRes,
    dolby_30255,
    dolby_30250,
    k192,
    k132,
    k64,
  ];

  static final Map<int, AudioQuality> _byCode = {
    for (final q in values) q.code: q,
  };

  /// 未知音质代码返回 rank=0 的占位对象（仅用于比较/展示兜底）。
  factory AudioQuality.fromCode(int code) =>
      _byCode[code] ?? AudioQuality(code, '音质 $code');

  /// 是否为高清/环绕特殊音轨（杜比全景声、Hi-Res 无损）。
  bool get isSpecial => rank >= 50;

  /// 控制条徽标短名；普通 AAC 音轨返回 null（不显示徽标）。
  String? get badgeLabel {
    if (code == 30251) return 'Hi-Res';
    if (code == 30255 || code == 30250) return '杜比';
    return null;
  }
}
