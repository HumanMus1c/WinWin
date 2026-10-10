# B7-b1 复盘：进度指示器与 Tooltip 全量 Miuix 化 — 2026-10-10

> 所属批次：MD3 库级退役 · Part B · **B7-b（控件残批）第一批**
> 前置：b7-a 主题骨架退役（`2087979`）+ b7-a 反馈#1 胶囊居中（`ca113bd`）。

## 1. 现象描述（本批目标）

B7-b 控件残批首刀：把 material_ui 的 **进度指示器**（`CircularProgressIndicator`
79 处 + `LinearProgressIndicator` 4 处）与 **Tooltip**（66 处）全量迁至
flutter_miuix，并建立两个替身组件收敛调用面。

## 2. 根因与设计（形态普查 → 替身组件）

- 形态普查（脚本全量扫描调用点）：
  - 进度环 79 处收敛为约 10 种形态，实为两类：`strokeWidth`/`color`
    （26 处用 biliPink）；`value:` 判定型极少。
  - Tooltip 66 处 40 种形态，95% 为 `(message:, child:)`（4 处带 `waitDuration`）。
- 设计：新建薄替身组件，把 Miuix 的 `colors: MiuixProgressIndicatorColors(...)`
  样板收敛到一处，调用点机械替换：
  - `lib/ui/components/app_progress.dart`：
    `AppProgressIndicator`（环：value/strokeWidth/size/color；默认取 Miuix 语义
    前景色，轨道为 Miuix `secondaryContainer`）、
    `AppLinearProgressIndicator`（条：value/minHeight/backgroundColor/color；
    收敛 `valueColor: AlwaysStoppedAnimation(c)` → `color`）。
  - `lib/ui/components/app_tooltip.dart`：`AppTooltip(message:, child:)` —
    `MiuixTooltipBox` + `MiuixPlainTooltip` 组合；**`waitDuration` 废弃**
    （Miuix 即时显示口径，4 处调用点随批量收敛）。

## 3. 修复方案（改动面）

- 脚本全量替换：**79 CPI + 66 Tooltip = 145 处 / 49 文件**（词边界防护，
  不误伤 `Miuix…` 前缀；注释行跳过；自动补 import；BOM 保持）。
- 手工转换：4 处 `LinearProgressIndicator`（历史/稍后再看/横版卡/用户空间）
  → `AppLinearProgressIndicator`（`valueColor` → `color`、`AlwaysStoppedAnimation` 收敛）。
- `waitDuration` 移除 4 处（emote_picker ×3、dyn_action_bar ×1）。
- 测试适配 3 文件：`find.byTooltip(...)` → `AppTooltip` 谓词定位
  （select_dialog ×2、app_icons ×1）；`byType(Tooltip)` → `byType(AppTooltip)`
  （glass_contrast）。
- 残留复核：lib 内物化 `CircularProgressIndicator(` / `Tooltip(` /
  `LinearProgressIndicator(` **全部归零**（0/0/0）。

## 4. 验证与提交回滚

- `dart analyze` 零问题；`flutter test` **164/164 全绿**；
  双分支构建 Debug **33.3s** / Release **75.8s**（0 错误 0 警告）。
- 快照：`f46e92b7`；提交 `67fdce1`；回滚基准 `git reset --hard f46e92b7`。

## 5. 遗留与踩坑

- **观感变化点（实机对照清单）**：
  1. 加载环新增 Miuix 轨道环（`secondaryContainer`），默认直径取 Miuix 30
     （原 Material 36 量级）——小尺寸容器内随约束收缩；
  2. 提示泡换 Miuix 反色泡（即时显示、Miuix 圆角与投影；原 Material 黑泡有
     悬停延迟）；
  3. 线性进度条换 Miuix 胶囊轨道样式（前景色沿用原 `valueColor`）。
- 踩坑：正则替换 `valueColor: AlwaysStoppedAnimation(...)` 时未吞掉尾逗号
  → 产生 `,,` 双逗号，analyzer 定位后统一修复（脚本替换此类"包裹成对括号
  内的参数"时须连带处理尾分隔符）。
- 遗留：`Tooltip` 的语义 tooltip 属性未复刻（Miuix 泡无 `semanticsTooltip`）；
  如需无障碍朗读可后续在 `AppTooltip` 内补 `Semantics(tooltip:)`。

## 6. 总结

进度指示器（83 处）与 Tooltip（66 处）共 149 处 / 49 文件全量 Miuix 化，
两枚替身组件把参数面收敛为单点；残留归零、全量验证通过。
B7-b 余下：按钮族（~145 处，下一刀）、Chips/Slider/Scrollbar/FAB/表单行等散点。

## 7. 测试验证指导（实机）

1. **加载态巡阅**（进度环+轨道）：首页下拉刷新、评论区加载更多、消息中心/
   会话列表/历史/稍后再看/用户空间等各页加载态——环带轨道、尺寸观感确认。
2. **视频/直播卡进度条**：横版卡播放进度、历史页续播进度、用户空间经验条——
   胶囊轨道样式与颜色确认。
3. **悬停提示**：播放器控制条（音量/播放暂停/画质/弹幕开关）、画廊预览按钮、
   设置/字体弹窗关闭按钮、表情面板、动态操作条——提示泡即时显示、位置与
   观感确认（原延迟显示不再保留）。
4. 浅色/深色两主题各抽查。
5. 日志核对：`D:\Documents\logs\runtime.log` 无新增 [E]；
   `D:\Documents\.winwin_logs.json` 无新条目。
