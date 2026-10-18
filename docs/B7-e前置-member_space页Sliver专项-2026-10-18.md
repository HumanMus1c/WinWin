# B7-e 前置：用户空间页去 Material Sliver 族（自建 AppSliverHeader） — 2026-10-18

## 一、现象

- `lib/` 闸门（`import 'package:material_ui/material_ui.dart'` 文件数）在 b7-d 后余 **3**：
  `core/shell/app_shell.dart`、`theme/app_theme.dart`、`pages/member/member_space_page.dart`。
- 其中 `member_space_page.dart` 是 **b7-e（摘 `app_shell` 宿主）的硬耦合前置**：
  该文件 L969/L978 使用 Material `SliverAppBar` + `FlexibleSpaceBar` 承载用户空间头图
  （折叠 / 视差 / 吸附），而 `flutter_miuix` 零 Sliver 类对应件。
- 用户指令「继续推进下一阶段」→ 按家规 P2（路线图已写下一步）锁定本专项。

## 二、定因

**现物**：`SliverAppBar(pinned:true, expandedHeight:liveCover, toolbarHeight:_topBarHeight(56),
elevation:0, scrolledUnderElevation:0, backgroundColor/surfaceTintColor:transparent,
automaticallyImplyLeading:false, flexibleSpace: FlexibleSpaceBar(background: _buildExpandableHeader(...)))`。

**保真依据**（读 SDK `material/flexible_space_bar.dart` 源码 + 用法推论）：
- 底层原语即 `SliverPersistentHeader(pinned:true)`（`minExtent = toolbarHeight`、`maxExtent = expandedHeight`）。
- `FlexibleSpaceBar` 默认 `CollapseMode.parallax`，逐式：
  `delta = maxExtent - minExtent`；
  `t = clamp(1 - (currentExtent - minExtent) / delta, 0, 1)`，`currentExtent = max(maxExtent - shrinkOffset, minExtent)`；
  头图 `height = maxExtent`（过滚动按 `StretchMode.zoomBackground` 撑满 `constraints.maxHeight`）、`top = -(delta / 4) * t`；
  不透明度 `1 - clamp((t - fadeStart) / (1 - fadeStart), 0, 1)`，`fadeStart = max(0, 1 - 56 / delta)`；
  外层 `ClipRect` 裁剪。

**第二现象（本轮新遇，根因级）**：摘除 `member_space_page.dart` 的 `material_ui` import 后
`dart analyze` 报 **1036 error**，采样形态为**全仓** `MemberSpacePage` 不再是 `Widget` 子类型
（`return_of_invalid_type_from_closure`）+ 本文件 15 处 `override_on_non_overriding_member`。

- **根因**：`package:material_ui/material_ui.dart` 主库含 `export 'package:flutter/widgets.dart';`
  —— 该文件**从未直接 import `package:flutter/widgets.dart`**，`Widget`/`StatefulWidget`/`BuildContext`
  等基础符号全靠 `material_ui` **传递提供**。摘 import 即断供，故塌方式报错（易误判为逻辑错误）。

## 三、方案

1. 新增 `lib/common/widgets/app_sliver_header.dart`（**零 material**）：
   `AppSliverHeader extends StatelessWidget`（返回 `SliverPersistentHeader`）
   + 私有 `_AppSliverHeaderDelegate extends SliverPersistentHeaderDelegate`，
   逐式复刻上节 parallax 语义（含 `zoomBackground` 撑高、`ClipRect` 裁剪、`shouldRebuild` 判定）。
2. `lib/pages/member/member_space_page.dart`：
   - L962 起 `SliverAppBar(...) + FlexibleSpaceBar(...)`
     → `AppSliverHeader(pinned:true, expandedHeight:liveCover, toolbarHeight:_topBarHeight,
     background:_buildExpandableHeader(context, card, images))`；
   - 导入区 `import 'package:material_ui/material_ui.dart';`
     → `import 'package:flutter/widgets.dart';`（补传递依赖；文件内**无任何 material 专有符号**，
     已扫描确认：`TabBar`/`AppBar`/`MaterialApp`/`LinearProgressIndicator` 仅出现在注释）；
   - 增 `import 'package:winwin/common/widgets/app_sliver_header.dart';`；
   - 就地注释更新（`flexibleSpace` 措辞 → 自建件说明）。
3. 附核：头图构建链（`_buildExpandableHeader` → `_buildHeaderBackground`/`_headerScrim`/
   `_defaultHeaderGradient`）**仅图像 / 渐变 / 遮罩，无 `Text`** —— 不依赖 `AppBar` 注入的
   `Material` 祖先与 `toolbarTextStyle`，摘除后无样式漂移。

## 四、验证

- `dart analyze`：**No issues found!**（0 错 0 警告；首轮 1036 error 为上述"传递依赖断供"根因，
  补 `package:flutter/widgets.dart` 后归零）。
- `flutter test`（注入 env）：**+186 All tests passed!**（基线保持，0 回归）。
- `flutter build windows --debug` / `--release`：`√ Built build\windows\x64\runner\Debug\winwin.exe`
  / `√ Built build\windows\x64\runner\Release\winwin.exe`，0 错 0 警告。
- 闸门：**3 → 2**（余 `app_shell.dart` 随 b7-e、`app_theme.dart` 随 B7 封板）。
- 实机：⏳ 待用户复验（头图折叠 / 展开 / 吸附与投影、像素零变化；明暗双主题）。

## 五、提交与回滚

- 提交：`6b3c6f7`（本专项 = 1 新增 lib + 1 改 lib + 2 docs）。
- 回滚点：改动前工作树 **clean**，基线 = `70959ff`（`git reset --hard 70959ff` 可全量回退）。

## 遗留与踩坑

- **踩坑 1（根因级）**：`material_ui` 传递导出 `flutter/widgets.dart`。
  教训：探针法摘 `material_ui` import 前，须先确认目标文件**是否自持** `package:flutter/widgets.dart`；
  否则 `dart analyze` 会以"目标类不再是 `Widget`"的**全仓塌方**形式暴露（形态误导）。
- **踩坑 2**：`FlexibleSpaceBar` 淡出常量用全局 `kToolbarHeight`(56)；本用例 `toolbarHeight` 恰为 56，
  故自建件用 `minExtent` 复刻**等价**。将来若 `toolbarHeight ≠ 56` 需回看此点。
- **遗留 1**：lib 闸门余 2（`app_shell.dart` / `app_theme.dart`）——本专项完成后
  **b7-e 的硬耦合前置已解阻**，可开工摘 `app_shell` 过渡主题（`ThemeData`/`AnimatedTheme`）。
- **遗留 2**：3 个 shell test（`test/core/shell/app_shell_layer_test.dart`、
  `test/core/shell/app_shell_material_parity_test.dart`、`test/immersive_title_bar_test.dart`）随 b7-e；
  `test/tools/icon_sheet_test.dart` **豁免**（保持 HEAD，随 B7 / 生成器处置）。
- **遗留 3**：`app_shell.dart` / `app_theme.dart` 摘除 + `pubspec.yaml` 删 `material_ui`
  + 门槛测试「残留 = 0」= **B7 封板**。

## 总结

本专项以「自建零-material 折叠头图容器 `AppSliverHeader`」**1:1 复刻** Material
`SliverAppBar(pinned) + FlexibleSpaceBar(parallax)` 语义，替代 `member_space_page.dart`
的最后一处 Material Sliver 族并摘除其 `material_ui` import，闸门 **3 → 2**；
同时定位并修正了「`material_ui` 传递导出 `flutter/widgets.dart`」导致的摘 import 塌方。
三级验证（analyze / 全量测试 / 双构建）全绿、无回归；**b7-e 的硬耦合前置就此解阻**，
下一阶段可直接推进 `app_shell` 宿主退役。