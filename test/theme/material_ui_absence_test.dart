// B7 封板门槛测试（2026-10-18）
//
// 目标：锁定两条终态不变量，任何回退（重新引入 material_ui）都会在此失败：
//   ① `lib/` 内零 `package:material_ui/material_ui.dart` 导入；
//   ② `pubspec.yaml` 不再声明 `material_ui` 依赖。
//
// 背景：MD3 库级退役 Part B 收官。唯一残留消费面 `lib/theme/app_theme.dart`
// 与 test 面生成器 `test/tools/icon_sheet_test.dart` 均在封板批处理（软删除
// 归档至 `scratch/deleted-2026-10-18/`）；`docs/icon-sheets/**` 产出物保留。
//
// 本测试为**源码级扫描**（参照 `test/ui/components/miuix_adoption_test.dart`
// 的 `File(path).readAsStringSync()` 断言范式），不经由编译器，故能捕获注释
// 之外的任何真实 import 残留。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 目标导入路径（material_ui 主库入口）。
const _needle = 'package:material_ui/material_ui.dart';

void main() {
  test('lib 内不得残留 package:material_ui 导入（B7 封板门槛）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '未在包根目录运行测试？');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains(_needle)) {
        offenders.add(entity.path.replaceAll('\\', '/'));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'lib 内仍残留 material_ui 导入（B7 目标为零）：$offenders',
    );
  });

  test('pubspec 不得再声明 material_ui 依赖（B7 封板门槛）', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    // 只匹配 YAML 键行（`material_ui:`），注释行以 `#` 开头不受影响。
    final declared = RegExp(r'^\s*material_ui\s*:', multiLine: true);

    expect(
      declared.hasMatch(pubspec),
      isFalse,
      reason: 'pubspec.yaml 仍声明 material_ui 依赖（B7 目标为零）。',
    );
  });
}