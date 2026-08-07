// Ported from BiliPai (Kotlin) -> WinWin (Dart)
// Original: com/android/purebilibili/settings/core/PlaybackSpeedPolicy.kt
//
// 播放倍速策略：速度归一化、长按倍速选项、首选速度解析。
//
// 作用：
//   1. 将用户设置或外部输入的倍速值归一化到引擎可接受的范围内。
//   2. 解析首选倍速（持久化值 → 合法倍速）。
//   3. 提供长按倍速的候选档位（按设备类型区分）。
//   4. 计算弹幕时长联动基准（供 [WinWinPlayerController.setPlaybackSpeed] 用）。

/// 播放倍速策略。
class PlaybackSpeedPolicy {
  PlaybackSpeedPolicy._();

  /// 倍速下限（0.25x）：低于此值引擎会视为暂停或异常。
  static const double minSpeed = 0.25;

  /// 倍速上限（4.0x）：高于此值音轨会失真到不可用。
  static const double maxSpeed = 4.0;

  /// 默认倍速档位（与 PiliPlus/BiliPai 对齐）。
  static const List<double> defaultSpeedList = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    3.0,
  ];

  /// 长按倍速档位（桌面端：单击倍速档 + 极速档）。
  ///
  /// 桌面端无移动端「按住屏幕」的物理交互，长按映射为：
  /// - 鼠标右键按住 / 键盘空格长按 → 切换到 longPressSpeed。
  /// 默认候选档：2.0x / 2.5x / 3.0x。
  static const List<double> longPressSpeedOptions = [2.0, 2.5, 3.0];

  /// 默认长按倍速值。
  static const double defaultLongPressSpeed = 3.0;

  /// 将任意输入归一化为引擎可接受的倍速值。
  ///
  /// 规则：
  /// 1. null / NaN / <= 0 → 1.0（视为异常输入，回退原速）。
  /// 2. < minSpeed → minSpeed（钳位下限）。
  /// 3. > maxSpeed → maxSpeed（钳位上限）。
  /// 4. 其余按四舍五入到 2 位小数（避免浮点累积误差）。
  static double normalizeSpeed(double? raw) {
    if (raw == null) return 1.0;
    if (raw.isNaN || raw <= 0) return 1.0;
    if (raw < minSpeed) return minSpeed;
    if (raw > maxSpeed) return maxSpeed;
    // 四舍五入到 2 位小数。
    return (raw * 100).round() / 100;
  }

  /// 判断倍速值是否合法（在 [minSpeed, maxSpeed] 区间内）。
  static bool isValidSpeed(double speed) {
    return !speed.isNaN &&
        !speed.isInfinite &&
        speed >= minSpeed &&
        speed <= maxSpeed;
  }

  /// 解析首选倍速：优先用 [userSetting]，无效则回退到 [fallback]。
  ///
  /// [userSetting] 通常来自 Pref.playSpeedDefault（持久化的用户偏好）。
  static double resolvePreferredSpeed({
    double? userSetting,
    double fallback = 1.0,
  }) {
    if (userSetting != null && isValidSpeed(userSetting)) {
      return normalizeSpeed(userSetting);
    }
    return normalizeSpeed(fallback);
  }

  /// 解析长按倍速：优先用 [userSetting]，无效则回退到默认值。
  static double resolveLongPressSpeed({double? userSetting}) {
    if (userSetting != null && isValidSpeed(userSetting)) {
      return normalizeSpeed(userSetting);
    }
    return defaultLongPressSpeed;
  }

  /// 计算弹幕时长联动基准。
  ///
  /// 在倍速从 [oldSpeed] 切换到 [newSpeed] 时，弹幕引擎的 duration 需按比例
  /// 调整以保持视觉速度一致：
  ///   newDuration = baseDuration / newSpeed
  ///   baseDuration = oldDuration * oldSpeed  （还原 1x 基准）
  ///
  /// 返回新的 duration 值，已 clamp 到 [1.0, 50.0] 区间
  /// （canvas_danmaku 引擎的合法时长范围）。
  static double computeDanmakuDuration({
    required double oldDuration,
    required double oldSpeed,
    required double newSpeed,
  }) {
    final normalizedNew = normalizeSpeed(newSpeed);
    if (normalizedNew <= 0) return oldDuration;
    final baseDuration = oldDuration * normalizeSpeed(oldSpeed);
    final newDuration = baseDuration / normalizedNew;
    return newDuration.clamp(1.0, 50.0);
  }

  /// 计算弹幕静态时长（顶部/底部弹幕）联动基准。
  ///
  /// 语义同 [computeDanmakuDuration]，作用于 [DanmakuOption.staticDuration]。
  static double computeDanmakuStaticDuration({
    required double oldStaticDuration,
    required double oldSpeed,
    required double newSpeed,
  }) {
    final normalizedNew = normalizeSpeed(newSpeed);
    if (normalizedNew <= 0) return oldStaticDuration;
    final baseDuration = oldStaticDuration * normalizeSpeed(oldSpeed);
    final newDuration = baseDuration / normalizedNew;
    return newDuration.clamp(1.0, 50.0);
  }

  /// 判断两个倍速值是否等价（考虑浮点容差）。
  static bool isSameSpeed(double a, double b) {
    return (a - b).abs() < 0.005;
  }
}
