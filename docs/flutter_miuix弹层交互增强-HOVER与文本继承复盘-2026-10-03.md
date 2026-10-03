# flutter_miuix 弹层交互增强（HOVER / 即时反馈 / 字号继承 / 不透明度对齐）复盘 — 2026-10-03

> 五要素结构。触发：复测反馈（以 MiuixOverlayPanel/弹层壳为基础继续打磨交互与观感）。
> 验证状态：`dart analyze` 0/0、`flutter test` 128/128、Debug/Release 双构建 ✅
> （Release 初次被运行中的 winwin.exe 锁定，用户关闭后补跑通过）。

## 一、分析根因 / 现状取证

1. **无 hover / 无按压反馈**：源码取证——上游 `MiuixDropdownImpl` 行背景为
   "纯矩形填充（`ColoredBox`），无按压涟漪"，且仅 `GestureDetector(onTap)`：
   **桌面 hover 与按压态均不存在**（触屏取向）；上一轮把行底改透明后彻底无交互视觉。
2. **点击即关闭无即时反馈**：原 `_handleSelect` 点击后立即开始收起动画，按压/选中
   变化来不及呈现。
3. **弹层与触发控件字号割裂**：行文本沿用面板基底字号（bodyMedium 14），而播放器
   控制条标签为 12 → 观感不一致。
4. **半透明度**：统一常量 0.88 与替换前播放器弹层（0xD9 ≈ 0.85）不一致。

## 二、设计修复 / 实现

| 项 | 实现 |
|---|---|
| 自绘条目行 | 新增 `_MiuixPopupRow`（替换 `MiuixDropdownEntriesPopupContent` 渲染）：**hover 高亮 8%**（MouseRegion）+ **按压 14%**（onTapDown 即时置亮）+ 选中态勾号（`AppIcons.check`）+ 禁用行弱化；行圆角 8、内距 12×10、多组分隔线保留 |
| 即时反馈后关闭 | `_handleSelect`：点击即触发 `onClick`（按压高亮先呈现），**130ms 后**再执行收起（多组菜单仍保持展开） |
| 字号继承 | `MiuixPopupMenu` 新增 `itemTextStyle`（与面板基底 merge）；播放器三菜单传 `fontSize: 12`（对齐控制条标签）；会话菜单用默认基底 |
| 不透明度对齐 | `kMiuixSurfaceAlpha` 0.88 → **0.85**（0xD9，替换前播放器二级弹层程度；Toast/弹层/毛玻璃面板同源调整） |

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **128/128 通过**（弹层用例补 130ms 延迟收起断言） |
| 双构建 | `windows --debug` ✅；`--release` ⏳ 待用户关闭 winwin.exe 后补跑 |

### 实机验证（待做）

- [ ] 1. 会话三点菜单 / 播放器画质·音轨·倍速：鼠标掠过行有高亮；按下瞬间变深、
      随后约 0.13s 收起；条目字号与控制条一致（12px）。
- [ ] 2. 弹层/Toast/毛玻璃面板半透明程度 = 替换前播放器弹层水平（0.85）。
- [ ] 3. 音轨菜单多组选择保持展开、禁用组标题仍弱化显示。
- [ ] 4. 对角展开、外点/Esc 收起无回归。

## 四、本轮总结

- 改动面：4 文件（miuix_popup_menu / player_panel / miuix_theme_bridge / 测试）。
- 决策记录：行渲染改为自绘（上游无 hover/按压且其行底与半透明面板需求冲突）；
  数值（hover 8% / 按压 14% / 延迟 130ms / 透明度 0.85）均为集中可调点。
- 队列：4c-2 视频卡片右键菜单；live_room 三菜单；4f 图标直参 Widget 化。

## 五、GitHub commit 提交记录

- 本轮提交：`0821c44dc5d318920cc961985214872dee761b32`（[feat](miuix): 弹层交互增强—hover/按压即时反馈/字号继承/透明度对齐，4 文件 / +166 −20；按全局开发规定补记）。
- 本 `[docs]` 提交随后推送。
