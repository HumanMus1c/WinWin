/// 护眼模式配置与计算（应用内叠色，不修改系统亮度）。
class EyeProtectionConfig {
  const EyeProtectionConfig({
    this.dim = 0.18,
    this.warmth = 0.12,
    this.nightModeEnabled = false,
    this.startHour = 22,
    this.endHour = 7,
  });

  /// 压暗强度 0-0.6。
  final double dim;

  /// 暖色强度 0-0.4。
  final double warmth;

  final bool nightModeEnabled;
  final int startHour;
  final int endHour;

  factory EyeProtectionConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EyeProtectionConfig();
    return EyeProtectionConfig(
      dim: _readDouble(json['dim'], 0.18, 0, 0.6),
      warmth: _readDouble(json['warmth'], 0.12, 0, 0.4),
      nightModeEnabled: json['nightModeEnabled'] == true,
      startHour: _readHour(json['startHour'], 22),
      endHour: _readHour(json['endHour'], 7),
    );
  }

  Map<String, dynamic> toJson() => {
        'dim': dim,
        'warmth': warmth,
        'nightModeEnabled': nightModeEnabled,
        'startHour': startHour,
        'endHour': endHour,
      };

  EyeProtectionConfig copyWith({
    double? dim,
    double? warmth,
    bool? nightModeEnabled,
    int? startHour,
    int? endHour,
  }) =>
      EyeProtectionConfig(
        dim: dim ?? this.dim,
        warmth: warmth ?? this.warmth,
        nightModeEnabled: nightModeEnabled ?? this.nightModeEnabled,
        startHour: startHour ?? this.startHour,
        endHour: endHour ?? this.endHour,
      );

  static double _readDouble(
    Object? value,
    double fallback,
    double min,
    double max,
  ) {
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || !parsed.isFinite) return fallback;
    return parsed.clamp(min, max);
  }

  static int _readHour(Object? value, int fallback) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    if (parsed == null) return fallback;
    return parsed.clamp(0, 23);
  }
}

/// 叠色参数（由 overlay 渲染为两层半透明色）。
class EyeProtectionVisual {
  const EyeProtectionVisual({required this.dim, required this.warmth});

  final double dim;
  final double warmth;

  bool get isTransparent => dim <= 0 && warmth <= 0;
}

abstract final class EyeProtectionPolicy {
  static bool isNightTime(
    DateTime now, {
    required int startHour,
    required int endHour,
  }) {
    if (startHour == endHour) return true;
    final hour = now.hour;
    if (startHour < endHour) {
      return hour >= startHour && hour < endHour;
    }
    return hour >= startHour || hour < endHour;
  }

  static EyeProtectionVisual? resolve(
    EyeProtectionConfig config,
    DateTime now,
  ) {
    if (config.nightModeEnabled &&
        !isNightTime(
          now,
          startHour: config.startHour,
          endHour: config.endHour,
        )) {
      return null;
    }
    if (config.dim <= 0 && config.warmth <= 0) return null;
    return EyeProtectionVisual(
      dim: config.dim.clamp(0.0, 0.6),
      warmth: config.warmth.clamp(0.0, 0.4),
    );
  }
}
