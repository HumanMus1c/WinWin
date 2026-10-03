# flutter_miuix 阶段4（完全化收尾）批次1 复盘 — 2026-10-03

> 五要素结构。范围：4a Toast、4b 底栏外壳、4d 徽章/ActionTile、4e Token 审计、4g 玻璃探测。
> 计划：`~/.commandcode/plans/flutter-miuix完全化收尾-阶段4.md`（面板已批准）。

## 一、分析根因 / 现状取证

- **4a Toast**：卡片视觉由 SnackBar + snackBarTheme 提供（自研质感），未走 flutter_miuix
  材质；机制（宽度自适应测量/点击关闭/单条优先）与 UI 解耦良好，可局部替换。
- **4b 底栏**：自研「毛玻璃胶囊」外壳；替换可行性取决于上游是否强制着色——**源码取证**：
  `_FloatingIconBadge` 使用 `IconTheme.merge`（继承式），显式色标的图标不受影响
  （对比侧栏 `MiuixNavigationRailItem` 的 `ColorFilter(srcIn)` 强制着色，属不同行为）。
- **4d 徽章**：LevelExpBar 进度条、MedalWidget/ActionTile 点按反馈仍为 M3 原语；
  等级 Canvas 字形（LevelBadge）与 PBadge 官方色语义属美术资产，正确做法是保留。
- **4e Token**：`AppShapes.miuix` = 6/12/14/16/23/32/100，与 flutter_miuix 规范
  （卡片/按钮/输入框 16、Tab 12、胶囊 50+）整体一致 → 无需改动（避免大范围视觉抖动）。
- **4g 玻璃**：实机 `runtime.log` 多次采样：`glass loaded=0 error=none`
  （着色器惰性加载、无错误信号；`loadedPrograms` 为 0 属预期，组件未使用玻璃时不会加载）。

## 二、设计修复 / 实现

| 批次 | 实现 |
|---|---|
| 4a | miuix 分支：`SnackBar` 本体透明（`backgroundColor: transparent / elevation 0 / 空 shape`），内容换 `MiuixSurface(cornerRadius 16, color: 原 snackBarTheme 底色, shadowElevation 8)`；文本色取 `snackBarTheme.contentTextStyle`。M3 分支逐字保留 |
| 4b | miuix 分支返回 `MiuixFloatingNavigationBar(children: [5× MiuixFloatingNavigationBarItem(label/selected/onPressed/icon: NavDestinationIcon)])`；`NavDestinationIcon`（彩色/头像/未读徽标合成）直接作 icon 传入 |
| 4d | `MiuixLinearProgressIndicator`（LevelExpBar，等级色 fg、outlineVariant 轨道）；`MiuixPressable`（MedalWidget onTap、ActionTile 整卡） |
| 4e | 审计结论：已对齐，无改动项 |
| 4g | 探测结论归档：无错误信号；启用评估待专项 A/B（记录维持） |

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **126/126 通过**（+5：底栏/Toast/ActionTile/LevelExpBar/MedalWidget） |
| 双构建 | 见下（本批与 4c/4f 合并最终验收前各跑一次） |

### 实机验证清单（待做）

- [ ] 1. Toast：任意操作错误/提示 → Miuix 质感卡片、宽度自适应、点击关闭。
- [ ] 2. （窄屏）底栏：squircle 胶囊、彩色图标、未读徽标、点按切换。
- [ ] 3. 用户空间页：经验进度条为 Miuix 扁平全圆角；粉丝牌点按反馈正常。
- [ ] 4. 个人页/动态页：ActionTile 点按反馈为扁平按压（无 ripple）。
- [ ] 5. 切回 M3：全部路径无回归。

## 四、本轮总结

- 改动面：6 文件（+258/−37）；不涉及持久化与行为契约。
- 决策记录：按"组件可承载则替换、美术语义与硬约束不替换"口径执行——等级 Canvas 字形、
  PBadge 官方色、彩色导航图标均按此保留。
- 遗留（下一批）：**4c 播放器深色菜单 ×3 + 右键菜单**（含 live_room 评估）；
  **4f 图标 IconData 直参 Widget 化**（14 部件 / ≈50 调用点，分两小批）。

## 五、GitHub commit 提交记录

- 批次1 提交：`6ad301c188eae02588e4dbf3d1d6e071f3cb0734`（[feat](miuix): 阶段4a/4b/4d — Toast、底栏外壳、徽章与 ActionTile Miuix 化，6 文件 / +258 −37；按全局开发规定补记）。
- 本 `[docs]` 提交随同推送 `origin/main`。
