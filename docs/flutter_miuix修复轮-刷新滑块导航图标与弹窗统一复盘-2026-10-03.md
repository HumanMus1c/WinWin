# flutter_miuix 修复轮（复测 6 项反馈）复盘 — 2026-10-03

> 五要素结构。触发：用户复测反馈 6 项（刷新不触发 / 弹窗与滑块问题 / 导航图标 / 关闭按钮）。
> 快照：`d2b3c835a4dd4cfc60a255d9f34d7ea91b5fbce5`。

---

## 一、分析根因（逐项定因）

1. **下拉刷新只回弹、不出现刷新提示、不触发刷新**（消息/番剧/直播/动态/用户空间 8 处）：
   `MiuixPullToRefresh` 由顶端越界的 `OverscrollNotification` 驱动（`_pullDownOverscroll`
   要求 Clamping 物理在顶端派发的负 overscroll）；而本项目全局 `AppScrollBehavior`
   （`BouncingScrollPhysics`）会把下拉位移**吸收为 overscroll 位置**（制造回弹观感），
   不派发该通知 → 控制器无输入 → 仅回弹。**诊断证据**：探针显示 Clamping 下
   `over=-20/-380 depth=0` → `fullDragProgress=1.0`（越过阈值）→ 松手弹簧 →
   `onRefresh` 触发（t≈1.3s）；Bouncing 下无该通知。
2. **弹幕/字幕面板滑块"缺失"**：`MiuixSlider` 内部 `CustomPaint` 无宽度撑满逻辑
   （仅 `SizedBox(height)`）；面板 `_SliderRow` 的 `Column(crossAxisAlignment: start)`
   给出**宽松宽度约束** → CustomPaint 坍缩为 **0 宽** → 不可见、无法调节。
   （独立紧宽度语境下可渲染，故此前未暴露。）
3. **弹窗未统一 / 应用字体弹窗旧样式 / 滑块设置未 Miuix 化**：`_FontPickerDialog`
   为 M3 AlertDialog；字体大小/界面缩放/缓冲大小/缓冲时长 4 项为两处内联
   `AlertDialog + Slider`（未走风格分发）。
4. **宽屏侧栏图标不一致且丢失彩色**：3c 将 `NavDestinationIcon` 字形接入 Miuix 矢量，
   导致"动态=描边、其余=实心"的观感不一致，且统一 tint 取代了逐项强调色。
5. **弹窗关闭按钮不直觉**：`clear` 字形被映射到 Miuix extended `clear`，观感不符 X 预期。
6. 会话更多菜单经复测确认正常（无需改动）。

## 二、设计修复计划与实现

- 刷新：`AppRefreshIndicator` miuix 分支外包 `ScrollConfiguration(_MiuixRefreshScrollBehavior)`
  → `ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics)`（保留鼠标/触控板拖拽）；
  M3 分支与其余页面不变。
- 滑块：面板使用处显式 `SizedBox(width: double.infinity)` 包裹 `MiuixSlider`。
- 弹窗统一：新增 `lib/pages/setting/widgets/slider_dialog.dart`（`AppSliderDialog`，
  miuix 分支 = `MiuixDialogShell` + `MiuixSlider`(撑满) + `MiuixTextButton` 操作区；
  M3 分支保留原 AlertDialog 行为与数值格式，`decimals` 参数区分 2 位/自适应）；
  style_settings 与 video_settings 各 2 处调用点切换，删除两处内联实现。
- 字体弹窗：新增 miuix 分支（`MiuixTheme(默认 textStyles 隔离全局字体)` +
  `MiuixDialogShell` + 原生 `MiuixTextField` 搜索 + `MiuixBasicComponent+MiuixRadioButton`
  字体行，行内字体预览样式保留；标题栏含 X 关闭）；**M3 分支逐字保留**。
- 导航图标：`NavDestinationIcon` 恢复 Cupertino 字形 + 逐项强调色（作用于侧栏与底栏）；
  侧栏外壳/主题指示/MiuixBadge 保持 flutter_miuix。
- 关闭按钮：`CupertinoIcons.clear → MiuixIcons.basic.close`（描边 X）。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **120/120 通过**（新增 3 例：Clamping 拖拽触发刷新回归 / MiuixSlider 宽松宽度可见性 / AppSliderDialog miuix 渲染与返回值） |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证清单（待做 — 用户操作）

- [ ] 1. **下拉刷新**（8 处）：出现 Miuix 下拉提示与中文文案、松手触发刷新、完成复位；鼠标拖拽可触发（滚轮不触发属预期）。
- [ ] 2. 弹幕/字幕设置：滑块可见、可拖动、松手落盘（不透明度/字号/区域/时长/描边/行高/云屏蔽 等）。
- [ ] 3. 设置 → 外观：字体大小 / 界面缩放 弹窗为 Miuix（squircle + Miuix 滑块 + 中文按钮）。
- [ ] 4. 设置 → 播放：缓冲大小 / 缓冲时长弹窗同上。
- [ ] 5. 应用字体弹窗：Miuix 外观、搜索可用、字体预览样式保留、点选即切换、关闭 X 与「导入字体文件/恢复默认」正常。
- [ ] 6. 宽屏侧栏：图标恢复逐项彩色（选中强调色），其余（外壳/指示）为 Miuix；窄屏底栏行为不变。
- [ ] 7. 弹窗关闭按钮为 X（描边）观感正常。
- [ ] 8. 切回 Material 3：以上全部恢复原样。

## 四、本轮总结

- 改动面：9 文件（+533/−159）：refresh_indicator、style_settings、video_settings、
  slider_dialog（新）、danmaku/subtitle 面板、app_icons、frosted_bottom_bar、测试。
- **遗留（下一轮，正在排队）**：用户点名的"其余保留自研项全部 flutter_miuix 化"——
  ① Toast 浮动卡 → Miuix 材质/组件；② 窄屏底栏外壳 → `MiuixFloatingNavigationBar`
  评估（需承载彩色自定义图标）；③ 播放器深色菜单/右键菜单 → Miuix 弹层；
  ④ 徽章三件套（LevelExpBar/MedalWidget/PBadge）→ Miuix 化；⑤ `AppActionTile`。
  （首页头部按约束保持；导航图标已按要求回退。）

## 五、GitHub commit 提交记录

- 修复提交：`9eff270c03e18ff68fc632c9d4b5b63e316ec3a4`（[fix](miuix): 修复刷新不触发与面板滑块缺失；弹窗统一 Miuix 化；导航图标回退彩色，9 文件 / +533 −159）。
- 本 `[docs]` 提交随同推送 `origin/main`（状态事后补记）。
- 回滚基准：`git reset --hard d2b3c835a4dd4cfc60a255d9f34d7ea91b5fbce5`。
