# flutter_miuix 分阶段替换 · 阶段3d（刷新/玻璃探测）与阶段3 收官复盘 — 2026-10-03

> 五要素结构 + 阶段3 收官总表。大指令：完全化替换。
> 关联：3a/3b 复盘、3c 复盘、计划 `~/.commandcode/plans/flutter-miuix完全化替换-阶段3.md`。

---

## 一、分析根因（背景与方案取舍）

1. **下拉刷新**（`AppRefreshIndicator`，8 调用点 / 6 文件）：调用点契约全部为
   `onRefresh: () async {…}`（Future 语义），**不向指示器暴露任何 isRefreshing 状态**；
   `MiuixPullToRefresh` 则要求 `isRefreshing` 提升管理。两条路：
   a) 逐页状态提升（8 处页面改造，回归面大）；
   b) **组件内接缝**：`AppRefreshIndicator` 内部把 Future 映射为 `isRefreshing`
      （触发置真、完成复位），调用点零改动 ← **已采用**（风险最小、行为可单点回滚）。
2. **OS4 玻璃探测**：当前界面未启用任何 `MiuixGlass*` 组件；着色器为**惰性加载**，
   `MiuixGlassRendering.loadedPrograms / loadError / has()`（components/miuix_glass.dart）
   可直接读取静态状态。以日志形式在 MiuixThemeScope 激活时采样（跨会话取证），
   待实际启用玻璃材质前先积累环境证据。

## 二、设计修复计划与实现

- `AppRefreshIndicator` 转 StatefulWidget：miuix 分支 → `MiuixPullToRefresh`
  （`kMiuixRefreshTexts` 中文文案：下拉刷新/松开刷新/刷新中/刷新完成；
  `_handleRefresh` 守卫防重入、`finally` 复位）；M3 分支与
  `displacement/edgeOffset` 原行为保留。
- `MiuixThemeScope._logCoverage` 增加 `miuixAdopt: glass loaded=N error=…` 探测日志。
- 测试：`AppRefreshIndicator：渲染 MiuixPullToRefresh 且刷新状态闭环`
  （Completer 驱动：isRefreshing false→true→false）。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **117/117 通过**（新增刷新闭环用例） |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 阶段3 实机验证总清单（待做 — 用户操作，覆盖 3a–3d）

- [ ] 1. **下拉刷新（重点）**：消息页 / UP 空间页 / 剧目详情 / 直播间（两处）/ 番剧索引（两处）/ 动态页——指示器为 Miuix 样式、中文文案、松手触发一次、状态「刷新中→完成」正确。
- [ ] 2. SelectDialog（设置 10 处）：squircle 外壳、点选即提交、Esc 取消、副标题完整。
- [ ] 3. 弹幕/字幕设置面板：squircle 外壳；Miuix 开关/滑块拖动生效、松手落盘；轨道/AI/字重控件正常。
- [ ] 4. 会话更多菜单：Miuix 弹层；置顶/免打扰/删除正常；**确认「删除项文本非红色」可接受**。
- [ ] 5. 窄屏底栏：毛玻璃与滚动隐藏保持；未读角标 Miuix 样式。宽屏侧栏：MiuixNavigationRail；**确认「选中指示为主题色」可接受**。
- [ ] 6. 图标：导航（首页/历史/消息）/返回/设置/搜索/更多/播放/暂停等为 Miuix 矢量；动态/我的/播放器深链图标为 Cupertino（预期）。
- [ ] 7. 切回 Material 3：以上全部恢复原样（零变化）。
- [ ] 8. 日志取证：`miuixAdopt: scope active`、`miuixAdopt: glass loaded=… error=…`、无新增 [E]/崩溃报告。

> 回滚：`git reset --hard debdedbd488ca514ea64b97f8d7d60a2a9cdebae`（阶段3 统一基准）。

---

## 四、阶段3 收官总结（完全化替换状态）

| 子阶段 | 状态 | 提交 |
|---|---|---|
| 3a 弹窗/菜单 | ✅ 已实现/验证/推送 | `968640d` + `417f8b3`（回填） |
| 3b 导航（侧栏/徽标） | ✅ 已实现/验证/推送 | `27e4a01` |
| 3c 图标体系（通用语义） | ✅ 已实现/验证/推送 | `fec2603` + `430322b`（回填） |
| 3d 刷新/玻璃探测 | ✅ 已实现/验证/推送 | `6718f3f` + 本复盘提交 |

**保留自研（记录 ≠ 遗漏，均有明确理由）**：首页头部（用户模糊约束）、Toast 浮动深色卡
（既有设计）、底栏毛玻璃悬浮外壳（flutter_miuix 无带文字/逐项强调色的浮动底栏）、
播放器深色菜单/右键菜单（固定深色设计）、徽章三件套与 `AppActionTile`（无对应组件）、
Token 层（桥接基础）、弹幕/字幕面板的毛玻璃承载形态。

**已知差异（验收确认项）**：① 菜单删除项文本色；② 侧栏选中指示；③ 动态/我的与播放器
专属图标保留 Cupertino；④ 面板内 FilterChip 保留（无对应）。

**遗留 backlog**：图标 IconData 直参 ≈50 处 / 14 部件签名 Widget 化（逐部件小步）；
OS4 玻璃材质启用评估（待探测日志积累）；disabled 色族按需增补；fontWeightAdjustment 接 boldText。

---

## 五、GitHub commit 提交记录

- 3d 提交：`6718f3fff2833f9236647180a882df224a2f59f4`（[feat](miuix): 阶段3d 下拉刷新接入 MiuixPullToRefresh + 玻璃探测日志，3 文件 / +103 −22）。
- 本 `[docs]` 提交随同推送 `origin/main`（状态事后补记）。
- 阶段3 提交链：`968640d` → `27e4a01` → `417f8b3` → `fec2603` → `430322b` → `6718f3f` → 本提交。
- 快照 / 回滚基准：`debdedbd488ca514ea64b97f8d7d60a2a9cdebae`。
