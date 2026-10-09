# B6-4a 复盘：Card 全量迁移（MiuixCard / 平色卡等价迁移）— 2026-10-10

## 1. 现象描述

B6-3（控件批）后，`lib` 内仍有 41 处 Material `Card`（17 文件）：
普通卡 30 处（默认 / 带 `margin` / 带 `clipBehavior`）、平色描边富变体
10 处（番剧剧集卡、文章/直播卡片、成员合集卡等）、自定义圆角卡 1 处
（下载页空态卡）。B7 摘除依赖前须全部迁移。

## 2. 根因

Material Card 依赖 M3 主题色（surfaceContainerLow）、elevation 与圆角体系；
两类形态替换语义不同：
- 普通卡 → `MiuixCard`（squircle 口径，`MiuixCardDefaults`）；
- 平色描边卡（`elevation: 0` + `RoundedRectangleBorder(side:)` 的自定义外观）
  → `MiuixCard` 无描边参数，须用 SDK 原生 `Container + ShapeDecoration` 精确等价。

## 3. 修复方案

- **30 处普通卡（14 文件，脚本转换）**：`Card(` → `MiuixCard(`；
  - `margin` 非零 → `Padding` 外包；`EdgeInsets.zero` 直接省略；
  - `clipBehavior` → 外包 `ClipPath(ShapeBorderClipper(shape: MiuixSquircleBorder(
    cornerRadius: MiuixCardDefaults.cornerRadius)))` 保持圆角裁切；
  - 视觉口径（列入实机验收）：圆角 12→16（squircle）、底色
    surfaceContainerLow→桥接 surfaceContainer、elevation 1→0（Miuix 扁平）。
- **10 处富变体（手工）**：`Container(decoration: ShapeDecoration(color: ..,
  shape: RoundedRectangleBorder(borderRadius: .., side: ..)))` —— 视觉零变化
  （原 `elevation: 0` 本无阴影），保留 margin / clipBehavior 语义。
- **下载页单卡**：`MiuixCard(cornerRadius: shapes.medium.x)`。
- `test/common/skeleton_test.dart`：`find.byType(Card)` → `find.byType(MiuixCard)`
  （2 处断言同步）。

## 4. 验证与回滚

- 快照：`ff0a6d80`（`refs/snapshots/latest`）。
- `dart analyze` 零问题（首轮 1 处缺导入，即修）；
  `flutter test` **164/164 全绿**（首轮 2 失败 = 骨架测试旧断言，按上更新后复绿）；
  双分支构建通过（kernel 01:39:15 / app.so 01:40:32），构建后已自启 Release
  （PID 26544）。
- 残留复核：`Card(` 全库 0 处；`MiuixCard` 51 处；闸门指标维持 **133**。
- 提交推送：`（本批回填）`（代码+复盘+进度表同批）。

## 5. 遗留与踩坑

- 遗留：B6-4b（`ListTile` 16 处，内容行/偏好行两类）→ B6-5 → B6-6。
- 踩坑：① Material Card 的**默认 margin 4** 随替换移除（MiuixCard 无 margin
  概念；各列表由父级 padding/separator 控距，观感变化列入实机验收）；
  ② 转换脚本对"尾随逗号产生的空白尾片"处理不当会产出 `),);` 紧凑闭合与
  多余 `Padding(EdgeInsets.zero)` —— 已二次修正（保留空白尾片、零 margin
  省略、闭合括号换行缩进）；
  ③ 平色描边卡不可用 MiuixCard（无描边），`Container + ShapeDecoration`
  才零变化；④ 组件替换须同步测试断言（`find.byType`）。

## 6. 总结

41 处 `Card` 全量迁移完成（30 机械 + 10 等价 + 1 圆角定制），
18 个 lib 文件 +123/−124；静态检查、164 项测试、双分支构建全绿；
下一批 B6-4b（ListTile）。

## 7. 测试验证指导（本轮产物）

- **骨架屏**（首页/搜索/收藏/历史/稍后再看列表加载态）：卡片圆角与底色观感
  （12→16 squircle、扁平无阴影）。
- **视频卡片**（各列表）：按压反馈与圆角正常。
- **番剧播放页剧集列表**：选中集描边高亮卡外观应与上一版一致（精确等价）。
- **动态页/成员空间**：文章卡、直播卡、成员合集卡外观应与上一版一致。
- **下载页**：空态卡（自定义圆角）。
- **预期结果**：普通卡为 Miuix 口径（圆角/底色/无阴影），富变体零变化；
  如遇描边丢失、圆角异常或间距跳变即回退。
- **日志**：复测后核对 `D:\Documents\.winwin_logs.json` 与
  `D:\Documents\logs\runtime.log` 有无新增条目。
