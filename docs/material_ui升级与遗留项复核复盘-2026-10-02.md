# material_ui 1.5.0 升级与遗留项复核复盘（2026-10-02）

**范围**：迁移遗留项 1（material_ui 升级实施）+ 遗留项 3（极验弃用 API）复核归档 + 遗留项 2（桥接摘除）评估固化。
**立项依据**：`docs/material_ui全库迁移与SelectDialog现代化复盘-2026-09-29.md` §4。
**执行计划**：`~/.commandcode/plans/material_ui迁移遗留项清理计划.md`（R3 / R2 / R4，2026-10-02 面板批准）。

---

## 一、分析根因（为什么升、升到哪里）

### 1.1 立项背景

遗留项 1 原文："**升级评估**：`material_ui 1.0.0 → 1.5.0`（IconButton 的 M3 Expressive 支持、M3 对比度基线、`StyleVariant` 枚举等）。需单独快照 + 单独回归，重点看 `app_theme.dart` 与 `app_components.dart`。"

### 1.2 版本与约束面（`flutter pub outdated` 实测）

- `material_ui`：Current 1.0.0 → Resolvable / Latest 均为 **1.5.0**；
- 1.5.0 环境要求 Flutter ≥3.47 / Dart ^3.13 —— 本机恰为 Flutter 3.47.0 / Dart 3.13.0，**满足**；
- 依赖约束核对：intl ^0.20.2、collection ^1.19.1、material_color_utilities ^0.13.0 与 lock 现值兼容；
- `cupertino_ui`：Latest 1.1.1（本轮**不动**，见 §2 决策表）。

### 1.3 变更面核实（changelog 1.1.0→1.5.0 + 源码抽查）

- **无破坏性条目**；均为可选能力与修复：`StyleVariant` 枚举（1.2.0）、`@awaitNotRequired`（1.3.0）、min SDK 提升（1.4.0）、IconButton M3 Expressive 支持 / M3 对比度基线 / Tooltip WCAG / InputDecoration 等（1.5.0）；
- **关键取证：Expressive 非默认外观**——`icon_button.dart:767-768`：`IconButtonTheme.of(context).variant ?? StyleVariant.material3`，需显式开启；1.0.0 中完全无 `styleVariant` 符号；
- **桥接仍存留**：1.5.0 仍导出 `MaterialUiCompatibilityBridge`（仍 `@Deprecated`、措辞未变）→ `main.dart:238` 的 `// ignore: deprecated_member_use` 继续有效，升级无需触碰桥接。

---

## 二、设计修复计划（关键决策）

| 决策 | 选择 | 理由 |
|---|---|---|
| 锁定方式 | **精确锁 `material_ui: 1.5.0`**（非 caret） | 延续既有锁版策略：显式版本 = 显式行为承诺；`^1.5.0` 会滑向未来未知版本 |
| `cupertino_ui` | **保持 1.0.0 不动** | 遗留项仅指名 material_ui；1.1.1 仅修 bug + 提下限，收益低，留作独立评估 |
| 兼容桥接 | **保持** | 摘除判据未满足（见附录 B） |
| 新能力采用 | **本轮不采用**（Expressive / 对比度基线等留待按需） | 本轮目标 = 升级保稳，不引入预期外视觉变化 |
| 回归重点 | `app_theme.dart` / `app_components.dart` + R1 新增的 SelectDialog 契约测试 | 按遗留项原文指定的重点面 + 新增契约网 |

---

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `flutter pub get` | **仅 1 个依赖变更**：material_ui 1.0.0 → 1.5.0（lock sha256 `32d98f11…`）；cupertino_ui 保持 1.0.0 |
| `dart analyze` | **0 error / 0 warning / 6 info**（与基线逐条一致；**零新增弃用**） |
| `flutter test`（全量） | **105/105 通过**（含 R1 新增 4 个 SelectDialog 契约用例） |
| `flutter build windows --debug` | ✅ 通过（50.7s，依赖变更后全量重编） |
| `flutter build windows --release` | ✅ 通过（71.3s） |
| 产物取证 | `kernel_blob.bin` 2026-10-02 16:45:16、`app.so` 2026-10-02 16:46:40 均为新生成；exe 未重链属正常（仅 Dart 变更） |

### 实机验证清单（✅ 用户实机确认，2026-10-02）

- [x] 三种 UI 风格 × 明暗主题：IconButton / 按钮 / 菜单 / 对话框 / Tooltip 视觉抽查（重点确认无默认外观变化）
- [x] 登录页极验 WebView 弹窗（桥接 + WebView 链路）——经诊断入口链路全程验证（含承载形态四轮调整后的终版）
- [x] 设置页 SelectDialog 10 处入口：点选即提交、Esc 取消不写入、副标题完整显示
- [x] 播放器：控制栏、章节 / 音量浮层、画质 / 音轨 / 倍速菜单

---

## 四、本轮修复总结

- **改动面**：`pubspec.yaml` + `pubspec.lock`（2 文件，+7 / -6）+ 本文档；**生产 Dart 代码零改动**。
- **行为预期**：material_ui 由 1.0.0（SDK 3.47 冻结等价线）升至 1.5.0（发布线）；升级内容均为可选能力与修复，**默认外观不变**；SDK 内设计库弃用倒计时对该包的阻塞进一步解除。
- **遗留项**：实机验证 ✅ 已完成（用户实机确认，2026-10-02；极验弹窗经诊断入口链路全程验证）；`cupertino_ui 1.1.1` 独立评估（可选，非阻塞）。

---

## 五、GitHub 提交记录与回滚

**快照（改动前基准）**：
- 工作区干净，基准 = `HEAD`：`11638db99aa3d2eab9ff7782d82f710e5e3a6c41`
- `refs/snapshots/latest` 已同步指向该提交；本轮无新增 stash 条目（干净树无内容可暂存）
- 回滚命令：`git reset --hard 11638db99aa3d2eab9ff7782d82f710e5e3a6c41`

**提交**：
- `60cbb1e` [chore](deps): material_ui 1.0.0 → 1.5.0（迁移后评估升级）
- 本文档提交 hash：`844146b`（已回填）

**推送状态**：随本次收尾统一推送（2026-10-02，含本文档及全部提交）。

---

## 附录 A：遗留项 3 复核归档（极验弃用 API 清理）

**结论：已闭环，无需动作。**

- **既成事实**：2026-09-29 12:24 的 `395cd9e`（[fix](login): 移除极验 WebView 两处弃用设置字段，全库弃用 info 清零）已删除 `clearCache` / `saveFormData` 两处弃用字段；提交信息明确记录"dart analyze：8 → 6 条 info，弃用类 info 清零"。
- **本次复核（2026-10-02）**：`dart analyze` 全库 **0 条 `deprecated_member_use`**（含 `geetest_webview_dialog.dart` 在内）；该文件自 `bc2f5d7`（迁移文档提交）以来无代码差异。
- **陈旧记载澄清**：迁移复盘文档中"190/201 行弃用 API"为陈旧记载——现 190/201 行是 `javaScriptEnabled` / `isFraudulentWebsiteWarningEnabled`，平台接口源码（`flutter_inappwebview_platform_interface-1.4.0-beta.3`）逐项核实**均无 @Deprecated**。
- **后续约定**：随 `flutter_inappwebview` 版本升级复查弃用（当前 6.2.0-beta.3 已是最新，无升级可用）。

## 附录 B：遗留项 2 桥接摘除评估（结论：维持桥接）

- **判据（原文）**：grep 三方包源码中 `package:flutter/material.dart` 是否归零。
- **实测（Windows 解析线 = 6.2.0-beta.3 家族）仍 4 个文件引用**：
  1. `flutter_inappwebview/src/in_app_webview/in_app_webview.dart`
  2. `flutter_inappwebview_platform_interface/src/util.dart`
  3. `flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart`
  4. `flutter_inappwebview_windows/src/in_app_webview/in_app_webview.dart`
- **上游版本**：`flutter_inappwebview` 6.2.0-beta.3 = Latest（`pub outdated` 未列出 → 已最新），无可用升级。
- **旁证（不足以支撑提前摘除）**：上述 4 文件未检索到 `MaterialLocalizations` / `Theme.of` 等活跃符号（import 疑似上游残留），但①判据未归零；②摘除后的影响面（SDK 设计状态供给）实机验证成本高 → **保守维持**。
- **复查命令（本机）**：
  ```powershell
  Get-ChildItem "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.flutter-io.cn\flutter_inappwebview*\lib" -Recurse -Filter *.dart |
    Select-String 'package:flutter/material.dart' -List
  ```
- **摘除前置清单（将来上游归零后再执行）**：
  1. 移除 `main.dart:239` 的桥接包裹（保留 `UiStyleScope` / `AppEscapeScope` 层级不变）；
  2. 删除 `main.dart:238` 的 `// ignore: deprecated_member_use`；
  3. 实机复验极验弹窗 + 全量回归（analyze / test / 双编译 / 实机清单）。
