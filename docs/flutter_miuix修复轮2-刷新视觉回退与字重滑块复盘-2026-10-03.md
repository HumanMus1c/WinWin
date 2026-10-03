# flutter_miuix 修复轮2（复测 3 项反馈）复盘 — 2026-10-03

> 五要素结构。触发：用户复测（含截图）3 项反馈。快照基准沿用 `d2b3c835a4dd4cfc60a255d9f34d7ea91b5fbce5`。

---

## 一、分析根因（逐项定因）

1. **下拉刷新视觉非既有观感**：3d 引入的 `MiuixPullToRefresh` 指示器视觉（圆环+中
   文案）与滚动手感（配套 Clamping 物理）均非项目既有观感；用户明确"原已有的
   下拉视觉更好"。原 `RefreshIndicator` 紧凑实现本来就工作正常（其拖拽跟踪兼容
   回弹物理，历史长期可用，3d 的"不触发"仅属 Miuix 组件路径）。
2. **应用字体搜索框高度异常、溢出父容器**（截图取证）：该处 `MiuixTextField` 未限定
   行数（`maxLines` 默认 null）→ 高度不收敛、视觉溢出灰底列表区。
3. **宽屏侧栏图标黑白**：源码取证 `MiuixNavigationRailItem` 内部将图标包进
   `ColorFiltered(ColorFilter.mode(contentColor, BlendMode.srcIn))` —— **强制把图标
   全部像素重着色为统一 content 色**，组件层面无法保留逐项彩色图标。
4. **字幕"字重"交互形态**：此前为 `MiuixWindowDropdownPreference` / M3 DropdownMenu
   下拉选择，用户要求与其它样式项一致改为滑块（min 100 / max 900 / 步进 100）。

## 二、设计修复计划与实现

- 刷新：`git checkout 6718f3f^` 恢复原 `refresh_indicator.dart`（两分支 RefreshIndicator；
  miuix = displacement×0.8 + strokeWidth 2.2）——视觉与滚动手感同时回退；删除
  Clamping 覆盖与中文文案常量；测试改为「miuix 渲染 RefreshIndicator」+「下拉触发
  onRefresh」两条回归。
- 字体搜索框：`MiuixTextField` 补 `singleLine: true`。
- 侧栏：`git checkout 27e4a01^` 恢复自绘 `AppNavRail`（原彩色逐项强调色 + pill 选中，
  即用户要求的"替换之前的彩色图标"原视觉）；底栏毛玻璃/徽标等其余 Miuix 化保持。
- 字重：subtitle 面板"字重"整块替换为 `_SliderRow`（value=(索引+1)×100，divisions 8，
  valueLabel w100–w900，onReset=5）；**存储保持 0..8 索引**，`player_panel`
  `_fontWeightFromIndex` 消费链路不变；M3/Miuix 双风格一致。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **120/120 通过**（刷新两条用例按回退后行为重写） |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证清单（待做 — 用户操作）

- [ ] 1. 下拉刷新：8 处页面为**原视觉**（紧凑指示环）、下拉可触发、回弹手感恢复原样。
- [ ] 2. 应用字体：搜索框高度正常不溢出；搜索/点选/导入/恢复默认正常。
- [ ] 3. 字幕设置「字重」：滑块 100–900、步进 100，拖动生效并落盘，重启后保持。
- [ ] 4. 宽屏侧栏：彩色图标与 pill 选中恢复（与替换前一致）。
- [ ] 5. 切回 Material 3 无回归。

## 四、本轮总结

- 改动面：5 文件（+149/−192）：refresh_indicator（回退）、style_settings（1 行）、
  subtitle_settings_panel、main_layout（回退）、测试。
- **决策记录**：两处"回退自研"均为**用户复测偏好 + 上游硬约束**双重依据——
  ① 刷新视觉以用户既有观感为准；② MiuixNavigationRailItem 的 `srcIn` 强制着色使
  "保留彩色图标"在组件层面不可达（若后续上游开放 per-item colors，可重新评估接入）。
- 遗留：保留自研 sweep（Toast / 底栏外壳 / 播放器深色菜单 / 徽章三件套 / ActionTile）
  仍在下轮队列。

## 五、GitHub commit 提交记录

- 修复提交：`e84a15717f9d9a391ee58bb0a9c5b60ba1f96e0a`（[fix](miuix): 刷新视觉回退原样式；字体搜索框单行化；字幕字重改滑块；侧栏回退自绘彩色，5 文件 / +149 −192）。
- 本 `[docs]` 提交随同推送 `origin/main`（状态事后补记）。
