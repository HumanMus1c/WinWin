# flutter_miuix 分阶段替换 · 阶段3a/3b（弹窗/菜单 · 导航）复盘 — 2026-10-03

> 五要素结构：分析根因（背景与盘点）/ 设计修复计划 / 修复效果验证 / 本轮总结 / 提交记录。
> 大指令：用户要求"继续后续阶段，直到完全使用 flutter_miuix 进行完全化替换"。
> 关联：阶段1/2 复盘、计划 `~/.commandcode/plans/flutter-miuix完全化替换-阶段3.md`。
> 后续：3c 图标体系、3d 刷新/玻璃探测（本复盘状态随进展更新）。

---

## 一、分析根因（背景与盘点取证）

阶段2 完成后按"完全化替换"指令全量盘点剩余面（`resolvePrimitiveRenderer` 31 处 / 16 文件；
`UiStyle.miuix` 187 处 / 32 文件），剩余五类：**弹窗/菜单、导航、图标、刷新、徽章/杂项**。本轮（3a/3b）处置前两类：

1. **三处对话框外壳复制粘贴**：`select_dialog.dart`、`danmaku_settings_panel.dart`、
   `subtitle_settings_panel.dart` 各自内联同一套「M3 vs Miuix」Dialog 外壳
   （miuix = surface α0.96 / r16 / outlineVariant 描边；M3 = surfaceContainerHigh / r24）。
2. **SelectDialog**（10 调用点，走 `showSelectDialog` 助手）：契约 = 点选即提交（无确定按钮）/
   Esc → null / 副标题 minWidth 320 / 宽度 320–420；选项行是 RadioListTile（M3 观感）。
3. **会话更多菜单**（`session_more_menu_button.dart`）：MenuAnchor + 自绘 MenuStyle 近似 miuix。
4. **导航**：`main_layout.dart` 宽屏自绘 `AppNavRail`（80px、逐项强调色 pill）；
   窄屏自绘 `FrostedBottomBar`（毛玻璃胶囊 + 图标 + 10px 文字 + 逐项强调色 + 滚动隐藏）；
   `NavDestinationIcon` 含头像 / 未读角标（M3 `Badge`）。
5. **对照 flutter_miuix 能力**（源码核对）：`MiuixSurface`（squircle）；`MiuixRadioButton/
   RadioButtonPreference/BasicComponent/DropdownItem`；`MiuixWindowIconDropdownMenu`；
   `MiuixSwitch/MiuixSlider`（steps 语义 = divisions−1）；`MiuixNavigationRail`（固定紧凑
   图标+文字，minWidth 80）；`MiuixBadge/BadgedBox`；**`MiuixFloatingNavigationBar` 为
   icon-only（label 仅语义）且统一着色**——无「图标+文字+逐项强调色」的毛玻璃浮动底栏对应物。

---

## 二、设计修复计划（方案与关键决策）

### 3a 弹窗/菜单
- 新增 **`lib/common/widgets/miuix_dialog_shell.dart`**：三处共用的 `MiuixDialogShell`
  （Dialog 路由不变；miuix 分支 = `MiuixSurface` squircle 16 + shadow 8 + 描边）。
- SelectDialog：miuix 行 → `MiuixRadioButton + MiuixBasicComponent` 组合行（保留副标题
  Widget 与整行点选即提交；M3 分支原样保留）。
- 弹幕/字幕面板：外壳统一；`Switch → MiuixSwitch`、`Slider → MiuixSlider`（steps=divisions−1；
  `onValueChangeFinished → onChangeEnd(当前值)`）、字幕轨道与 AI 策略行 → Miuix 单选组合行、
  字重下拉 → `MiuixWindowDropdownPreference`（字符项目 w100–w900）。FilterChip 无对应物保留。
- 会话菜单 → `MiuixWindowIconDropdownMenu.entries`（两组 + 分组分隔）。**已知差异**：上游
  `MiuixDropdownItem` 不支持逐项文本色——删除项红色图标保留、文本退化为默认内容色。

### 3b 导航
- 宽屏侧栏：自绘 `AppNavRail`（删除）→ **`MiuixNavigationRail`**（固定紧凑）。**已知差异**：
  选中指示由「逐项强调色 pill」变为 Miuix 主题 indicator（surfaceContainerHigh）。
- 窄屏底栏：**保留自研毛玻璃外壳**（设计性保留：flutter_miuix 无带文字/逐项强调色的浮动
  底栏对应物；BiliPai 同源设计）；未读角标 → `MiuixBadgedBox + MiuixBadge`。

---

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| 快照（回滚基准） | `debdedbd488ca514ea64b97f8d7d60a2a9cdebae`（`refs/snapshots/latest`） |
| `dart analyze` | **0 错误 0 警告**（6 条既有 info 与基线一致） |
| `flutter test` | **114/114 全部通过**（SelectDialog 双风格契约、会话菜单双风格、阶段1/2 用例全绿） |
| `flutter build windows --debug` | ✅ 33.3s，0 警告 0 错误 |
| `flutter build windows --release` | ✅（首跑被运行中的 `winwin.exe`（PID 33324，15:33 启动的 Release 实例）锁定 `WebView2Loader.dll` 阻塞 —— 既知环境型 MSB3021；按惯例不强杀进程，用户关闭后重跑通过，0 警告 0 错误） |

### 实机验证（待做 — 用户操作）

- [ ] 1. SelectDialog（设置页 10 处入口）：miuix 下 squircle 外壳；点选即提交；Esc/遮罩取消不写入；副标题完整不硬换行。
- [ ] 2. 弹幕设置面板：squircle 外壳；开关/滑块为 Miuix 样式且拖动生效、松手落盘；轨道/AI/字重控件正常。
- [ ] 3. 字幕设置面板：同上（含字重 `MiuixWindowDropdownPreference` 弹层）。
- [ ] 4. 会话更多菜单：miuix 下 Miuix 弹层；置顶/免打扰/删除行为正常；确认「删除项文本非红色」可接受。
- [ ] 5. 窄屏底栏：毛玻璃与滚动隐藏保持；未读角标为 Miuix 样式。
- [ ] 6. 宽屏侧栏（≥900px）：MiuixNavigationRail；确认「选中指示为主题色、不再逐项强调色」可接受。
- [ ] 7. 切回 Material 3：以上全部恢复原样，无布局错位。

> 回滚：`git reset --hard debdedbd488ca514ea64b97f8d7d60a2a9cdebae`（本轮全部子阶段）。

---

## 四、本轮修复总结

- **改动面**：3a = 新增 1 文件 + 4 文件修改（+446/−275）；3b = 2 文件修改（+53/−103）。
- **行为预期**：miuix 风格下对话框外壳/选项行/面板控件/会话菜单/宽屏侧栏/未读角标由
  flutter_miuix 原生组件驱动；M3 路径不变；首页头部（模糊约束）与底栏毛玻璃外壳保持不变。
- **已知差异（验收确认项）**：① 菜单删除项文本色；② 侧栏选中指示改主题色。
- **遗留项**：3c 图标体系（AppIcons→Miuix 矢量，覆盖通用语义）；3d 刷新（MiuixPullToRefresh ×8）
  与 OS4 玻璃探测；徽章三件套/Toast/播放器深色菜单按盘点维持自研（记录 ≠ 遗漏）。

---

## 五、GitHub commit 提交记录

- 3a 提交：`968640d5b9b71bbf025a859a8fe301f98d7eff3d`（[feat](miuix): 阶段3a 弹窗/菜单迁移至 flutter_miuix）
- 3b 提交：`27e4a0136752b264d90fa2659337491a2319c50e`（[feat](miuix): 阶段3b 导航迁移至 flutter_miuix）
- 回填与推送：本 `[docs]` 提交随同 3a/3b 一并推送 `origin/main`（推送状态事后补记）。
- 快照 / 回滚基准：`debdedbd488ca514ea64b97f8d7d60a2a9cdebae`。
