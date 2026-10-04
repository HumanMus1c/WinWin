# flutter_miuix 阶段5b 收尾（控制条 Widget 化）+ 5c 玻璃预载验证 复盘 — 2026-10-04

> 五要素结构。范围：`_iconButton`/`_PlayerBarIconButton` 图标 Widget 化；
> OS4 玻璃着色器主动预载验证实验。

## 一、分析根因 / 现状取证

- 播放器控制条 `_iconButton`（8 个调用点）与 `_PlayerBarIconButton`：
  `IconData` 参数 + 内部 `ContrastIcon(widget.icon, color: effectiveColor,
  size: widget.size, shadows: glyphShadows)`——字形数据化；需在 Widget 化同时
  **保留 hover 提亮（动态色）与字形高对比阴影**。
- 玻璃：`MiuixGlassRendering` 源码取证——`load()` 公开（幂等、逐 shader 容错、
  失败自动降级非玻璃材质）；此前仅被动探测（惰性 → loaded=0），无法判定可用性。

## 二、设计修复 / 实现

| 项 | 实现 |
|---|---|
| 控制条 Widget 化 | 两处签名 `IconData → Widget`；内部改 `IconTheme(size, effectiveColor)` 注入**动态尺寸与 hover 提亮**；8 个调用点统一传 `Icon(AppIcons.xxx(...), shadows: ContrastStyle.glyphShadows)`——**字形阴影完整保留**（阴影由调用点携带，颜色/尺寸经 IconTheme 继承） |
| 5c 预载验证 | miuix 桥接启动时 `unawaited(MiuixGlassRendering.load())`，完成后输出 `miuixAdopt: glass preload loaded=N error=…` |

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **全库 0 issues** |
| `flutter test` | **130/130 通过** |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |
| **5c 实验**（Release 实例实跑） | **`glass preload loaded=6 error=none`**——着色器全部加载成功、`isLoaded` 成立、无任何错误 ⇒ **Windows 端 OS4 玻璃技术上完全可用** |

### 实机验证（待做）

- [ ] 1. 播放器控制条 8 个按钮：hover 提亮、字形阴影、尺寸（含播放/暂停 20px）不变。
- [ ] 2. 玻璃启用 A/B（5c 第二步，待用户拍板）：候选表面挂实验开关，对比性能/观感。

## 四、本轮总结

- 改动面：2 文件（player_panel、miuix_theme_bridge），+64/−25。
- **5b 全部完成**（批1 5 部件 + 批2 9 组件/数据类、约 60 个调用点；detail/bangumi/
  live 三处局部变量按设计排除）。
- 5c 结论：玻璃可用（loaded=6 error=none）；**是否启用与启用范围待用户拍板**。
- 下一项：5d MD3 触点清单与退役评估（已完成清点，见 `docs/MD3触点清单与退役评估-2026-10-04.md`）。

## 五、GitHub commit 提交记录

- 本轮提交：`663426697142a6a3ca2b5964af022db67d1a896e`（[feat](miuix): 阶段5b收尾—播放器控制条图标 Widget 化；阶段5c—玻璃预载验证探针，2 文件 / +64 −25；按全局开发规定补记）。
- 本 `[docs]` 提交随后推送。
