# B7 封板复盘 — material_ui 库级退役收官（闸门 1 → 0）

- 日期：2026-10-18
- 起点 HEAD：`e5fd39c`（b7-e 本体 hash 回填后）
- 快照：`git update-ref refs/snapshots/latest HEAD` = `e5fd39c1396f8b949a17e31bb54643ca9f46d613`
- 提交：`84c040f`（代码批，本文件为回填批）
- 回滚点：`git reset --hard e5fd39c`
- 关联：`docs/MD3库级退役进度追踪-2026-10-07.md`、`docs/B7-e本体-app_shell过渡主题摘除-2026-10-18.md`、`docs/B7-e前置-member_space页Sliver专项-2026-10-18.md`

## 1. 现象 / 背景

MD3（`material_ui`）库级退役 Part B 的**最后一步**。b7-e 本体后，`lib/` 内仅剩 **1** 个文件仍导入 `package:material_ui/material_ui.dart`；test 面亦仅剩 **1** 个：

- `lib/theme/app_theme.dart`（202 行，`AppTheme.lightFor/darkFor` 返回 `ThemeData`）
- `test/tools/icon_sheet_test.dart`（983 行，图标视觉对照生成器）

这两者是 `pubspec.yaml` 摘除 `material_ui: 1.5.0` 依赖的**唯一阻塞**（此前 b7-e 前置 / 本体的遗留登记均为「B7 封板处置」）。

## 2. 根因 / 目标

1. **`app_theme` 已是死码**：b7-e 本体已摘除 `main.dart` 的 `theme:` 三行与 `app_theme` import。全仓实证：`AppTheme.` 真实引用 **0**（`git grep -n "AppTheme[^H]"` 仅命中其自身定义 + 一处文档注释）；`app_theme` 路径串命中的全部是**同名的另一个文件** `core/shell/app_theme_host.dart`（不含 `import 'theme/app_theme.dart'`）。真·`Theme.of(context)` 在 lib 内 **0 处**（主题经 `AppThemeHost.of(context)` **255 处**供给，B2 已完成）。
2. **`icon_sheet_test` 为一次性对照生成器**：产出 `docs/icon-sheets/**`（9 组 PNG/SVG + `icons/` ~90 单图标 + `tables/`）。其渲染宿主硬依赖 material_ui（`MaterialApp` + `Scaffold`）+ 218 行 `Icons.` 引用 + `material_glyph_paths.g.dart`（曾用 Material 字形轮廓）。迁移到零-material harness 会使**全部 PNG 重生成**（根因＝宿主文本度量差异，**非图标变化**，见 B1b 余批复盘结论），故 b7-e 前判豁免、登记「随 B7 处置」。
3. **目标终态**：`lib/` 与 `test/` **双面** `material_ui` 导入归零 + `pubspec.yaml` 零声明，并以**门槛测试**锁定该不变量（防回退）。

## 3. 变更内容

| 文件 | 变更 |
| --- | --- |
| `lib/theme/app_theme.dart` | **软删除** → `scratch/deleted-2026-10-18/app_theme.dart`（同卷 move） |
| `test/tools/icon_sheet_test.dart` | **软删除** → `scratch/deleted-2026-10-18/icon_sheet_test.dart`（同卷 move） |
| `pubspec.yaml` | 摘除 `material_ui: 1.5.0` 依赖块（4 行），注释改写为退役说明 |
| `test/theme/material_ui_absence_test.dart` | **新增**门槛测试（2 条）：① `lib/**` 无 `package:material_ui/material_ui.dart` 导入；② `pubspec.yaml` 无 `material_ui:` 键行声明 |
| `pubspec.lock` | 依赖解算刷新（详见 §5 踩坑 1） |

**保留项**（均无 `material_ui` 依赖，本批不动）：`docs/icon-sheets/**` 产出物；`test/tools/material_glyph_paths.g.dart`、`test/tools/cupertino_glyph_paths.g.dart` 与生成器 `tools/glyph_outline_export.py`。

## 4. 验证与提交 / 回滚

- `flutter pub get` → `material_ui` 脱离依赖树（`These packages are no longer being depended on: material_ui 1.5.0`）
- `dart analyze` → **No issues found!**
- `flutter test` → **All tests passed! (+183)**（基线 182 − 生成器 1 例 + 门槛 2 例 = 183，吻合）
- `flutter build windows --debug` → **√ Built 229.7s**（0 错 0 警告）
- `flutter build windows --release` → **√ Built 101.5s**（0 错 0 警告）
- 闸门复核：`git grep -l "package:material_ui/material_ui.dart" -- lib test` → **空**（lib 1 → **0**，test 面 1 → **0**）
- 提交：`84c040f`（5 文件，+257/−1397）。回滚：`git reset --hard e5fd39c`。

## 5. 遗留与踩坑

1. **`pubspec.lock` 变更（199/207 行）非本批引入**：为归因，先 `git checkout -- pubspec.lock` 还原、**不改 pubspec 仅重跑 `flutter pub get`** → 结果**同为 199/207 行** ⇒ 该 churn 属**既有陈旧锁在当前 SDK 下的解算刷新**，与本次摘除 `material_ui` 无关。如实记录（含传递依赖升级：`sentry` 9.27→10.1、`cached_network_image_ce` 4.10→4.13、`hive_ce` 2.19→2.22、`file_picker` 12.2→12.3 等）。四关（analyze/test/debug/release）已覆盖其编译与运行面。
2. **`icon_sheet_test` 迁移否决理由复述**：即便迁移，218 处 `Icons.` 需等价 Material 字形常量表，且产物 PNG 会因文本度量差异**全量重生成**（噪声 diff），收益小于成本 ⇒ 选退役；能力可随时自 git 历史 / 归档恢复。
3. **`winwin.exe` 曾占用 release 产物**（上一批遗留）：本批开工时该实例已由用户关闭，双构建无冲突（开工实测 `tasklist` 无 `winwin.exe`）。
4. **环境坑**：本机 PowerShell 工具无 git（PATH 缺）→ git 走 `bash` tool `shell_type=cmd`；`flutter test` / `build` 必须注入 `APPDATA` / `LOCALAPPDATA` / `USERPROFILE` / `HOME` / `ProgramFiles(x86)`；`cmd` 不展开 `$(...)`（bash 语法），首条「快照 + move」链路因此中断、文件未移动，已复核后重做（与 b7-e 同族坑）。
5. 构建首跑超采样上限：依赖刷新触发全量重编，`--debug` 首跑 > 600s 采样窗口 → 改后台写日志 + 有界轮询取结论。

## 6. 总结

material_ui 库级退役**收官**：`lib/` 与 `test/` 双面 `package:material_ui` 导入归零、`pubspec.yaml` 零声明，并由门槛测试 `test/theme/material_ui_absence_test.dart` **锁定**该终态。MD3 过渡主题通道（`ThemeData` 体系）在应用侧**完全退场**；全站视觉由 Miuix（`AppThemeHost` / `flutter_miuix`）+ 项目自建替身承担，SDK material（`flutter_miuix` 内部 SDK `TextField` 所需 `MaterialLocalizations`）经 `lib/core/shell/miuix_compat.dart` 局部桥接（**类型与 material_ui 不可互换**，历史坑已记录）。B7 封板完成，闸门 **1 → 0**。