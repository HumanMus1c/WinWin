// B7 封板门槛测试（2026-10-18）
//   · Phase A 载体退役追加第三条不变量（2026-10-19）。
//   · Q4 门槛升级为「应用侧零 Material 消费」追加第四、五条不变量（2026-10-19）。
//
// 目标：锁定五条终态不变量，任何回退都会在此失败：
//   ① `lib/` 内零 `package:material_ui/material_ui.dart` 导入；
//   ② `pubspec.yaml` 不再声明 `material_ui` 依赖；
//   ③ `lib/` 内零 `app_glyphs.g.dart` 引用、且该载体文件不复存在
//      （MaterialIcons 字体消费面已随 Phase A 全量退役）；
//   ④ 【Q4】`lib/` 内 SDK `package:flutter/material.dart` 导入**仅限白名单**
//      （`lib/core/shell/miuix_compat.dart` —— 唯一许可的 SDK material 桥）。
//      其余任何 lib 文件出现该导入即为回退；
//   ⑤ 【Q4/Phase A】`pubspec.yaml` 不得回挂 `uses-material-design` 真值
//      （否则会重新把 SDK MaterialIcons 字体捆绑进产物）。
//
// 背景：MD3 库级退役 Part B 收官。唯一残留消费面 `lib/theme/app_theme.dart`
// 与 test 面生成器 `test/tools/icon_sheet_test.dart` 均在封板批处理（软删除
// 归档至 `scratch/deleted-2026-10-18/`）；`docs/icon-sheets/**` 产出物保留。
//
// Q4 语义（对齐路线图 §6 原文「lib 除 compat 桥外零 material 导入」）：
//   「应用侧零 Material 消费」= 应用代码（`lib/`）除唯一桥文件外，不再直接
//   消费 SDK Material 子系统。此语义**不**锁依赖树——允许 flutter_miuix 等
//   上游在过渡期内部依赖 `material_ui`，从而与官方弃用路线（2026-11）不冲突，
//   也不锁死 flutter_miuix 的升级能力（见路线图 §6，Q3 决策=不 fork）。
//
// 本测试为**源码级扫描**（参照 `test/ui/components/miuix_adoption_test.dart`
// 的 `File(path).readAsStringSync()` 断言范式），不经由编译器，故能捕获注释
// 之外的任何真实 import 残留。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 目标导入路径（material_ui 主库入口）。
const _needle = 'package:material_ui/material_ui.dart';

/// SDK Material 主入口（Q4 应用侧零消费的唯一许可桥）。
const _sdkMaterial = 'package:flutter/material.dart';

/// 唯一白名单：允许导入 SDK `package:flutter/material.dart` 的 lib 文件。
/// 该文件为 Miuix⟷SDK 的兼容桥（flutter_miuix 内部 SDK TextField 需
/// MaterialLocalizations），是「应用侧零 Material 消费」中**显式豁免**的单点。
const _sdkMaterialWhitelist = <String>{'lib/core/shell/miuix_compat.dart'};

String _rel(FileSystemEntity e) => e.path.replaceAll('\\', '/');

void main() {
  test('lib 内不得残留 package:material_ui 导入（B7 封板门槛 ①）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '未在包根目录运行测试？');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains(_needle)) {
        offenders.add(_rel(entity));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'lib 内仍残留 material_ui 导入（B7 目标为零）：$offenders',
    );
  });

  test('pubspec 不得再声明 material_ui 依赖（B7 封板门槛 ②）', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    // 只匹配 YAML 键行（`material_ui:`），注释行以 `#` 开头不受影响。
    final declared = RegExp(r'^\s*material_ui\s*:', multiLine: true);

    expect(
      declared.hasMatch(pubspec),
      isFalse,
      reason: 'pubspec.yaml 仍声明 material_ui 依赖（B7 目标为零）。',
    );
  });

  test('lib 内不得再引用 app_glyphs.g.dart（Phase A 载体退役门槛 ③）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '未在包根目录运行测试？');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.readAsStringSync().contains('app_glyphs.g.dart')) {
        offenders.add(_rel(entity));
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'lib 内仍引用 app_glyphs.g.dart（Phase A 目标为零）：$offenders',
    );
    expect(
      File('lib/theme/app_glyphs.g.dart').existsSync(),
      isFalse,
      reason: 'app_glyphs.g.dart 应已退役（软删除至 scratch/deleted-2026-10-19/）。',
    );
  });

  test('lib 内 SDK material 导入仅限白名单桥（Q4 应用侧零消费门槛 ④）', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '未在包根目录运行测试？');

    // 白名单文件必须真实存在，避免失效白名单长期空放。
    for (final allowed in _sdkMaterialWhitelist) {
      expect(
        File(allowed).existsSync(),
        isTrue,
        reason: '白名单文件 $allowed 不存在——白名单已失效，应同步收敛。',
      );
    }

    final offenders = <String>[];
    final hitWhitelist = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (!entity.readAsStringSync().contains(_sdkMaterial)) continue;
      final path = _rel(entity);
      if (_sdkMaterialWhitelist.contains(path)) {
        hitWhitelist.add(path);
      } else {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'lib 内出现白名单外的 SDK material 导入（Q4「应用侧零 Material 消费」'
          '目标：仅 ${_sdkMaterialWhitelist.join(', ')} 可导入）：$offenders',
    );
    // 白名单必须被真实命中，否则说明桥已拆——应把该文件从白名单移除。
    expect(
      hitWhitelist.toSet(),
      _sdkMaterialWhitelist,
      reason: '白名单桥文件未命中 SDK material 导入，白名单应同步收敛：$hitWhitelist',
    );
  });

  test('pubspec 不得回挂 uses-material-design（Q4/Phase A 门槛 ⑤）', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    // 匹配 `uses-material-design: true`（忽略大小写与行尾空白）。
    final enabled = RegExp(
      r'^\s*uses-material-design\s*:\s*true\s*$',
      multiLine: true,
      caseSensitive: false,
    );

    expect(
      enabled.hasMatch(pubspec),
      isFalse,
      reason: 'pubspec.yaml 回挂了 uses-material-design: true——'
          '会重新捆绑 SDK MaterialIcons 字体进产物（Phase A 已摘除）。',
    );
  });
}