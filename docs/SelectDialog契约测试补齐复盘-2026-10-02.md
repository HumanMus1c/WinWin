# SelectDialog 契约测试补齐复盘（2026-10-02）

**范围**：material_ui 迁移遗留项 4 —— SelectDialog 体系（控件 + 共享助手）零测试覆盖 → 契约锁定。
**立项依据**：`docs/material_ui全库迁移与SelectDialog现代化复盘-2026-09-29.md` §4 遗留项 4。
**执行计划**：`~/.commandcode/plans/material_ui迁移遗留项清理计划.md`（R1，2026-10-02 面板批准）。

---

## 一、分析根因（为什么必须补）

### 1.1 现象描述

`SelectDialog` + `showSelectDialog` 支撑全库 **10 处设置入口**（extra_settings ×2、video_settings ×6、style_settings ×2），共享同一交互契约：

- **点选即提交**：点任一选项 → 立即 `Navigator.pop(所选值)`，无确定按钮；
- **取消不写入**：Esc / 关闭按钮 / 遮罩 → pop null，调用点 `if (res != null) { 落盘; setState(); }` 保证不落盘。

迁移轮（2026-09-29）重写 `select_dialog.dart`（双套渲染 + 统一助手）后，该体系**零测试覆盖**——后续任何重构（含本轮计划的 material_ui 1.5.0 升级）没有回归网。这是 §4 遗留项 4 的根因。

### 1.2 可行性取证（先验证再动手）

| 疑点 | 取证 | 结论 |
|---|---|---|
| 测试里调用 `showSelectDialog` 会否触发 `AppLogger.w` 落盘/崩溃？ | `log_collector.dart:60`：`if (!_initialized) return;` —— 未初始化直接早退；`logger.w` 仅控制台输出 | ✅ 测试环境安全（探针日志不会写文件） |
| Esc 取消路径能否在 widget 测试中复现？ | `app_escape_scope.dart:94-98`：路由级弹层在最上层 → `maybePop()`；`test/ui/app_escape_scope_test.dart` 已有同构先例 | ✅ 可复刻宿主（MaterialApp + `AppEscapeNavigatorObserver` + `AppEscapeScope`） |
| Esc 语义是否依赖弹窗内部结构？ | 按**路由类型**判定（`_routes.last is PopupRoute`），与 SelectDialog 实现无关 | ✅ 测试锁定的是真实路径 |

---

## 二、设计修复计划（关键决策）

新增 `test/pages/setting/select_dialog_test.dart`（4 用例）：

1. **点选即提交**：点「2 次」→ 宿主收到 `2`、弹窗关闭；
2. **Esc 取消不写入**：Esc（真实 AppEscapeScope 路径，探针实测记录 `Esc layer1 popup-route`）→ 宿主未写入、弹窗关闭、页面保留；
3. **关闭按钮取消**：tooltip「关闭」→ null、不写入；
4. **副标题/宽度 smoke**：`subtitleBuilder` 存在时卡片宽度 ∈ [320, 420]、31 字符说明文案完整渲染（M3 / Miuix 双风格各一次）。

**关键决策与取舍：**

- **宿主与 `main.dart` 同构**（UiStyleScope + MaterialApp + AppEscapeScope），仅去除与本用例无关的兼容桥接——确保 Esc 分层、风格感知都走真实链路；
- **不测「重复点选已选项」**：`RadioGroup` 同值点击是否触发 `onChanged` 属框架行为、非本项目契约，避免锁定框架细节（如需可后续单独评估）；
- **宽度断言先失败过一次**（首跑 `find.byType(Dialog)` 得 800.0）：Dialog 根部是铺满全屏的 `Align`，实际卡片是内部受 `ConstrainedBox` 约束的 `Material` —— 测量目标修正为 SelectDialog 子树首个 Material 后通过。此教训已在此记录，后续同类断言直接对内部卡片取尺寸。

---

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 error / 0 warning / 6 info**（与基线逐条一致，零新增） |
| `flutter test`（全量） | **105/105 通过**（101 基线 + 4 新增；新文件首跑 3 通过 1 失败 → 修正测量目标后 4/4） |
| `flutter build windows --debug` | ✅ 通过（22.5s） |
| `flutter build windows --release` | ✅ 通过（20.5s） |
| 产物 | `build\windows\x64\runner\Debug\winwin.exe`、`Release\winwin.exe` 生成成功 |

> 说明：本轮为纯测试新增（不参与应用构建），双编译为规则性验证；应用二进制无行为变化，**实机验证无需执行**。

---

## 四、本轮修复总结

- **改动面**：新增 1 文件（`test/pages/setting/select_dialog_test.dart`，198 行）+ 本文档；**生产代码零改动**。
- **行为预期**：契约「点选即提交 / Esc 取消不写入 / 关闭取消 / minWidth 320 防硬换行」被 4 用例锁定；后续 material_ui 升级轮直接复用为回归网。
- **遗留项**：无新增。

---

## 五、GitHub 提交记录与回滚

**快照（改动前基准）**：
- `144191d98a728512da091cb9afa1678780b5eaa9`
- 指向：`refs/snapshots/latest`；stash：`snapshot_20261002_160300`
- 回滚命令：`git reset --hard 144191d98a728512da091cb9afa1678780b5eaa9`

**提交**：
- `13c158b` [chore](taste): 提交累积的偏好学习记录（前置清理，非本轮功能改动）
- `0d76178` [test](setting): SelectDialog 契约测试补齐 — 点选即提交 / Esc 取消不写入（上方全部验证对应的代码提交）
- 本文档提交 hash：`11638db`（已回填）

**推送状态**：随本次收尾统一推送（2026-10-02，含本文档及全部提交）。
