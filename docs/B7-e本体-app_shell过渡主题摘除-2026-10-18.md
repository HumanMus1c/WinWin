# B7-e 本体：`app_shell` 过渡期 Material 主题摘除复盘 — 2026-10-18

> 批次：MD3 库级退役 Part B · B7-e **本体**（闸门 **2 → 1**）
> 起点 HEAD：`291a0fb`（b7-e 前置回填后）｜ 快照：`refs/snapshots/latest = 291a0fb1db99c913c1b3a756ffb31dd7322e20ed`
> 前置：`6b3c6f7`（member_space_page 去 Material Sliver 族，解除硬耦合）

---

## 1. 现象（本批要解决什么）

- 应用壳 `lib/core/shell/app_shell.dart` 自 L0 起一直挂着一层**过渡期 Material 主题宿主**：
  - 构造参数 `ThemeData? theme`；
  - `build` 内 `AnimatedTheme(data: theme)` 包裹整棵子树；
  - `localizationsDelegates` 中夹带 `DefaultMaterialLocalizations.delegate`。
- `lib/main.dart` 每次构建都算 `AppTheme.darkFor/lightFor(fontFamily:)` 并传入。
- 这层宿主是 L0「双轨并存」期的**临时桥**：等主题读取面（B2）与控件面（B6/B7）迁移完毕后即为**死代码**，是库级退役收官（B7 封板）前的最后两个 material_ui 依赖文件之一（另一个 `lib/theme/app_theme.dart`）。

## 2. 定因（为什么可以直接摘，而不是改从 SDK material 取）

1. **过渡主题已无真实消费者**——
   - 项目主题读取通道 = `AppThemeHost.of(context)`，全库 **255 处**（B2 迁移已完成）；
   - 真·`Theme.of(context)` 在 `lib/` 内 **0 处**（4 处命中全部是文档注释）；
   - `AppTheme.*` 消费者只有 `main.dart` 两行。
   ⇒ `AnimatedTheme` 提供的那套 `ThemeData` **没有任何读取方**，是结构性死代码。
2. **本地化面不靠它**——`MaterialLocalizations` 的调用方全在 SDK-material 场景；SDK 侧由 `lib/core/shell/miuix_compat.dart`（`MiuixCompat`，SDK `Theme` + `Localizations.override` + 透明 `Material`，**零 material_ui**）局部提供。material_ui 的 `MaterialLocalizations` 与 SDK 的**不可互换**（历史故障「No MaterialLocalizations found → 灰块不可点」，即 B1 修复轮）。
3. **前置已解除硬耦合**——上一批 `6b3c6f7` 把 `member_space_page` 的 material_ui Sliver 族换成零-material `AppSliverHeader` 后，`app_shell` 宿主不再被任何活跃渲染路径依赖（b7-e 阻塞登记所记条件已消失）。
4. **传递依赖风险已排除**——`package:material_ui/material_ui.dart` 首部含 `export 'package:flutter/widgets.dart';`；摘 import 会切断 widgets 传递供给（历史教训：曾致全仓 1036 error）。本批两文件（`app_shell.dart` / `main.dart`）**均已直接具备 `flutter/widgets.dart` 供给**，摘除安全。

## 3. 方案（改动明细）

### 3.1 `lib/core/shell/app_shell.dart`（全量重写，去 material_ui）

- 删构造参数 `theme`、字段 `final ThemeData? theme;`；
- `build` 内去掉 `AnimatedTheme(...)` 与 `DefaultSelectionStyle` 分支，子树直返；
- `localizationsDelegates`：`[DefaultMaterialLocalizations.delegate, DefaultCupertinoLocalizations.delegate]` → 仅 `[DefaultCupertinoLocalizations.delegate]`；
- 类文档注释两条 bullet 改写（说明过渡宿主已退役）；
- **保留**：`AppScrollBehavior`（含 `AppScrollBar.attach` 收口）、builder 链 `MiuixThemeScope → MiuixToastHost → ImmersiveTitleBarShell → DefaultTextStyle → AppEscapeScope`、`pageRouteBuilder: appPageRouteBuilder`、外层 `AppThemeHost` + `ScrollConfiguration`；
- 新参数集：`{title, home, isDark, navigatorKey, escapeObserver, navigatorObservers, fontFamily}`。

### 3.2 `lib/main.dart`（两处编辑）

- 删 `import 'theme/app_theme.dart';`；
- 删 `theme: isDark ? AppTheme.darkFor(fontFamily: fontFamily) : AppTheme.lightFor(fontFamily: fontFamily),` 三行；
- 注释块改：「B7：过渡期 Material 主题通道已随 material_ui 库级退役一并摘除。」

### 3.3 测试面同步（3 个 shell test，硬耦合必须同批）

| 文件 | 处置 |
|---|---|
| `test/core/shell/app_shell_layer_test.dart` | 全量重写：删 `import material_ui as modern` 与 `app_theme`；`AppSheetRoute` 用例 `find.byType(modern.Material)` → `find.byWidgetPredicate((w) => w.runtimeType.toString() == 'Material')`；**整删**「过渡期 Material 主题/本地化齐备（MaterialApp 等价面）」用例；保留 `MiuixCompat`（用 SDK `legacy` material，合法）等其余用例 |
| `test/immersive_title_bar_test.dart` | 全量重写：宿主改零-material（`appTestHost` / `AppShell`）；删 `CupertinoPageTransitionsBuilder`/`material_ui`/`app_theme` 依赖；用例 1 宿主改 `appTestHost(ImmersiveTitleBarShell(...))`；用例 2 删双主题 `pageTransitionsTheme` 循环；兜底防线由 `ZoomPageTransitionsBuilder` 改**自建上溢缩放转场**（`ScaleTransition` 1.15→1.0、`alignment: bottomCenter`、`kMiuixTransitionDuration`、`easeOutCubic`）；`_runTransitionCoverageScenario` 宿主改生产同构 `AppShell(...)`；保留 `_stripHex`/`_stripRows`/颜色常量/`_bodyHex`/`_sample` |
| `test/core/shell/app_shell_material_parity_test.dart` | **前提作废**（其唯一职责＝验证「AppShell 与 MaterialApp 等价面」，宿主摘除后断言无对象）⇒ **软删除**至 `scratch/deleted-2026-10-18/`（同卷 `move`，未物理删除）；等价覆盖由 `MiuixCompat` 用例承接 |

> 三文件与本批**硬耦合**：`AppShell` 签名变更后不同批即编译失败，故一并处置。

## 4. 验证（四关全绿）

| 关卡 | 结果 |
|---|---|
| `dart analyze` | **No issues found!**（首轮 3 条 `unnecessary_underscores`，改通配 `_` 后归零） |
| `flutter test` | **All tests passed! (+182)**（基线 +186 − 3 个 parity 用例 − 1 个过渡主题用例 = 182，吻合） |
| `flutter build windows --debug` | **√ Built `build\windows\x64\runner\Debug\winwin.exe`** |
| `flutter build windows --release` | **√ Built `build\windows\x64\runner\Release\winwin.exe`** |

- 闸门：`lib/` 内 `import 'package:material_ui/material_ui.dart'` 文件数 **2 → 1**（`git grep` 复核，余 `lib/theme/app_theme.dart`）。
- test 面 material_ui import：**4 → 1**（余 `test/tools/icon_sheet_test.dart`，已判豁免）。
- diff：`5 files changed, 78 insertions(+), 204 deletions(-)`（4 改 + 1 删除）。
- 实机：⏳ 待用户复验（见 §6）。

## 5. 提交与回滚

- 快照：`git update-ref refs/snapshots/latest HEAD`（= `291a0fb…`）。
- 提交：`<hash>`（代码 + 测试 + 本复盘 + 进度表回填，同批）。回滚：`git reset --hard 291a0fb`。

## 6. 遗留与踩坑

### 6.1 遗留

- **闸门余 1**：`lib/theme/app_theme.dart`（`ThemeData` 族），归 **B7 封板**（软删除）。
- **test 面余 1**：`test/tools/icon_sheet_test.dart`——真 import material_ui `Icons.*` 约 130 处 + 生成 `docs/icon-sheets/*`；**已判豁免**，但 `pubspec.yaml` 删 `material_ui` 会使其编译失败 ⇒ **B7 封板前必须先处置该文件**（决策待定：迁移到 `lib/theme/app_glyphs.g.dart`（仅 82 枚 `const IconData`，覆盖存疑）或整体退役）。
- **B7 封板**余项：`lib/theme/app_theme.dart` 软删除 + `pubspec.yaml` 删 `material_ui` + 新增门槛测试「lib 内 material_ui 残留 = 0」（范本 `test/ui/components/miuix_adoption_test.dart` 源码级断言 `File(path).readAsStringSync()` + `src.contains(...)`）。

### 6.2 踩坑

1. **release 编译被运行中实例锁 DLL（环境级，第 N 次同源）**——首次 `--release` 失败于 MSBuild 拷贝阶段：`WebView2Loader.dll` 被运行中 `winwin.exe`（PID 612，用户实测实例，`build\windows\x64\runner\Release\`）独占 ⇒ `MSB3026`×10 → `MSB3027` + `MSB3021`。**非 Dart 编译错误**（AOT 阶段已过）。按项目**硬约束不按进程名/不按 PID 杀进程**，如实登记阻塞并请用户关闭实例；用户关闭后复跑 **√ Built**，确认首跑告警纯属实例占用。
2. **`MaterialLocalizations` 双体系不可互换**——SDK 版与 material_ui 版混用会回归「灰块不可点」；本批只摘 material_ui 侧 `DefaultMaterialLocalizations.delegate`，SDK 侧仍由 `MiuixCompat` 提供，未触碰。
3. **作废测试处置口径**——「前提作废的测试」用**软删除**（同卷移入 `scratch/`，`scratch/` 已 gitignore + analyzer 排除），不静默物理删除、不留下会误判的悬空断言。
4. **兜底防线去 material 化**——`immersive_title_bar_test` 原靠 material_ui `ZoomPageTransitionsBuilder` 造溢出转场；改自建 `ScaleTransition`（1.15→1.0，`bottomCenter`）保住「溢出型转场下标题条零覆盖」的回归语义，不因去库而丢失防线。

## 7. 总结

本批按前置轮登记的条件（`member_space_page` 硬耦合已由 `6b3c6f7` 解除）摘除应用壳最后一层过渡期 Material 主题宿主，`lib/` 内 material_ui 依赖收敛到**唯一 1 文件**（`app_theme.dart`，归 B7 封板）。摘除口径是**直接删除**而非改从 SDK 取——因为该 `ThemeData` 已确证**零真实消费者**，保留只会把死代码带入封板。四关全绿（analyze 0 / test +182 / debug+release 双 √ Built），闸门 **2 → 1**，test 面 **4 → 1**。剩余**唯一实质阻塞**是 `test/tools/icon_sheet_test.dart`：它卡在「pubspec 删依赖」这一步之前，须先决策其迁移或退役，才可执行 B7 封板。