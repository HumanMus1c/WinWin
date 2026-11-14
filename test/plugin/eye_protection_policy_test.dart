import 'package:flutter_test/flutter_test.dart';

import 'package:winwin/plugin/builtin/eye_protection/eye_protection_policy.dart';

void main() {
  group('EyeProtectionPolicy 夜间时段', () {
    test('同日区间（结束时刻不含）', () {
      expect(
        EyeProtectionPolicy.isNightTime(
          DateTime(2026, 11, 14, 22),
          startHour: 22,
          endHour: 23,
        ),
        isTrue,
      );
      expect(
        EyeProtectionPolicy.isNightTime(
          DateTime(2026, 11, 14, 23),
          startHour: 22,
          endHour: 23,
        ),
        isFalse,
      );
      expect(
        EyeProtectionPolicy.isNightTime(
          DateTime(2026, 11, 14, 21),
          startHour: 22,
          endHour: 23,
        ),
        isFalse,
      );
    });

    test('跨午夜区间', () {
      expect(
        EyeProtectionPolicy.isNightTime(
          DateTime(2026, 11, 14, 23),
          startHour: 22,
          endHour: 7,
        ),
        isTrue,
      );
      expect(
        EyeProtectionPolicy.isNightTime(
          DateTime(2026, 11, 14, 3),
          startHour: 22,
          endHour: 7,
        ),
        isTrue,
      );
      expect(
        EyeProtectionPolicy.isNightTime(
          DateTime(2026, 11, 14, 12),
          startHour: 22,
          endHour: 7,
        ),
        isFalse,
      );
    });

    test('起止相同视为全天', () {
      expect(
        EyeProtectionPolicy.isNightTime(
          DateTime(2026, 11, 14, 12),
          startHour: 8,
          endHour: 8,
        ),
        isTrue,
      );
    });
  });

  group('EyeProtectionPolicy 叠色解析', () {
    test('夜间模式关闭时全天生效', () {
      final visual = EyeProtectionPolicy.resolve(
        const EyeProtectionConfig(dim: 0.2, warmth: 0.1),
        DateTime(2026, 11, 14, 12),
      );
      expect(visual, isNotNull);
      expect(visual!.dim, closeTo(0.2, 1e-9));
      expect(visual.warmth, closeTo(0.1, 1e-9));
    });

    test('夜间模式开启时仅时段内生效', () {
      const config = EyeProtectionConfig(
        dim: 0.2,
        warmth: 0.1,
        nightModeEnabled: true,
        startHour: 22,
        endHour: 7,
      );
      expect(
        EyeProtectionPolicy.resolve(config, DateTime(2026, 11, 14, 12)),
        isNull,
      );
      expect(
        EyeProtectionPolicy.resolve(config, DateTime(2026, 11, 14, 23)),
        isNotNull,
      );
    });

    test('强度为零时返回 null，越界值被夹紧', () {
      expect(
        EyeProtectionPolicy.resolve(
          const EyeProtectionConfig(dim: 0, warmth: 0),
          DateTime(2026, 11, 14, 12),
        ),
        isNull,
      );
      final visual = EyeProtectionPolicy.resolve(
        const EyeProtectionConfig(dim: 9, warmth: 9),
        DateTime(2026, 11, 14, 12),
      );
      expect(visual!.dim, 0.6);
      expect(visual.warmth, 0.4);
    });

    test('JSON 往返与非法值回落', () {
      const config = EyeProtectionConfig(
        dim: 0.3,
        warmth: 0.2,
        nightModeEnabled: true,
        startHour: 23,
        endHour: 6,
      );
      final again = EyeProtectionConfig.fromJson(config.toJson());
      expect(again.dim, 0.3);
      expect(again.warmth, 0.2);
      expect(again.nightModeEnabled, isTrue);
      expect(again.startHour, 23);
      expect(again.endHour, 6);
    });
  });
}
