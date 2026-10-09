# B6-3b 复盘：IconButton 全量 Miuix 化（MiuixIconButton）— 2026-10-10

## 1. 现象描述

B6-3a（InkWell）完成后，`lib` 内仍有 58 处 Material `IconButton`
（30 文件，含 `.filled` / `.filledTonal` 变体与 `styleFrom` 定制），
依赖 Material 祖先与 M3 主题色体系；B7 摘除 `material_ui` 前须迁移到
`MiuixIconButton`（min 40×40、全圆角、可选背景、无 tooltip/padding/
constraints 参数）。

## 2. 根因

`IconButton` 属 material_ui 控件家族；`MiuixIconButton` 的构造面更窄
（`onPressed/child/enabled/backgroundColor/cornerRadius/minWidth/minHeight`），
原有 `padding/constraints/visualDensity/color/style/tooltip` 参数需逐类映射：
约束尺寸→`minWidth/minHeight`、颜色→下放图标、tooltip→child 层包裹。

## 3. 修复方案

- **40 处标准站点（21 文件）机械转换**：顶层参数 ⊆ `{onPressed, icon, tooltip}`
  的站点，`icon:`→`child:`；有 `tooltip` 站点外提为
  `child: Tooltip(message: .., child: <图标>)`；脚本按顶层参数切分重建并自动补
  `show MiuixIconButton` 导入。
- **18 处手工站点逐点映射**：
  - `constraints: BoxConstraints(minWidth: N, minHeight: N)` → `minWidth/minHeight: N`
    （history / toview / select_dialog / live_room 弹幕清空 / 弹幕·字幕设置）；
  - `color:` → 下放至图标（history / toview / 弹幕·字幕设置 / 搜索清除）；
  - `styleFrom(backgroundColor/foregroundColor/hoverColor/padding)` →
    `backgroundColor` + 图标色（hover 收敛为 Miuix 默认 overlay）；
  - `.filledTonal`（member 私信）→ `backgroundColor: cs.secondaryContainer` +
    图标 `color: cs.onSecondaryContainer`；
  - `.filled`（弹幕添加 biliPink、聊天发送）→ `backgroundColor` + 白/`onPrimary` 图标；
  - 画廊 5 处暗底浮层按钮 → 保留黑底、`minWidth/minHeight: 52 / 42` 命中区；
  - `AppBackButton`（app_icons.dart）→ `minWidth/minHeight: 0` +
    `Padding(padding)` 内容自适应（保留调用方自定义 padding/size）。
- `child` 一律置于参数末位（`sort_child_properties_last` lint 驱动，回修 5 处）。

## 4. 验证与回滚

- 快照：`d69d26d8`（`refs/snapshots/latest`）兜底，逐文件可 checkout 回滚。
- `dart analyze` 零问题（首轮 11：6 处缺导入 + 5 处 child 位置）；
  `flutter test` **164/164 全绿**；
  `flutter build windows --debug` / `--release` 双通过、0 警告
  （kernel_blob 01:28:27 / app.so 01:29:51；编译前已清残留进程，
  构建后按约定自启 Release，PID 10588）。
- 残留复核：`IconButton` 全库 0 处；`MiuixIconButton` 78 处；闸门指标维持 **133**。
- 提交推送：`（本批回填）`（代码+复盘+进度表同批）。

## 5. 遗留与踩坑

- 遗留：B6-4（`Card`/`ListTile`）→ B6-5（`Divider`/`Material(` 收尾）→
  B6-6（`Colors.`→Token）。`Tooltip` 仍来自 material_ui（B7 时需再处置）。
- 踩坑：① `MiuixIconButton` 无 `tooltip` 参数——必须外提到 child 层包裹；
  ② 紧凑站点若不给 `minWidth/minHeight`，默认 40×40 会顶破外层
  26/24/28 的 const 布局；③ `sort_child_properties_last` 为 info 级但计入
  「0 问题」口径，`child` 必须置末；④ `.filled` 的默认主题色不会自动跟随，
  需显式映射（primary/onPrimary、secondaryContainer/onSecondaryContainer）。

## 6. 总结

B6-3 全批收官：`InkWell` 71 处 + `IconButton` 58 处共 **129 处控件**
完成 Miuix 化（含 5 处 filled 变体颜色语义映射），27 文件 +376/−287；
静态检查、164 项测试、双分支构建全绿；Material 控件家族再退一城，
下一批 B6-4（`Card`/`ListTile`）。

## 7. 测试验证指导（本轮产物）

- **右上操作区**：文章/番剧详情/动态详情/下载/历史/收藏页右上按钮——
  点击行为与 tooltip 悬停提示正常。
- **直播页**：右下弹幕输入框清空按钮（输入后出现）；画质/线路浮层。
- **弹幕·字幕设置面板**：「恢复默认」小按钮（数值行右侧）点击生效。
- **画廊（暗底浮层）**：左右翻页箭头、保存/复制/关闭按钮——黑底白图标观感
  与上一版一致（hover 由 Miuix overlay 提供）。
- **搜索**：搜索结果页输入框尾部清除按钮。
- **成员空间**：私信（filledTonal 圆钮，SecondaryContainer 配色）点击正常。
- **聊天**：会话详情发送按钮（filled，primary 底）发送/禁用态正常。
- **预期结果**：布局零变化（紧凑按钮仍紧凑）；点击/悬停反馈为 Miuix 口径；
  任一按钮缺失、尺寸跳动或点击失效即回退。
- **日志**：复测后核对 `D:\Documents\.winwin_logs.json` 与
  `D:\Documents\logs\runtime.log` 有无新增条目。
