# material_ui 全库迁移 + SelectDialog 现代化复盘（2026-09-29）

**范围**：遗留项 1（material_ui 全库迁移，P3）+ 遗留项 2（SelectDialog 体系），两项合并为一轮交付。
**立项依据**：`docs/组件现代化改造复盘-2026-09-29.md:58-59`。
**用户决策**：双线合并为一轮；先 `material_ui: 1.0.0` 保稳、验证后再升；SelectDialog 保留弹窗形态并对齐 PiliPlus 最新实现。

---

## 一、分析根因（为什么必须迁）

### 1.1 官方时间线（取证来源：docs.flutter.dev / pub.dev）

- Material 与 Cupertino **在 Flutter 3.44 冻结**，SDK 内不再接受新特性；
- Flutter 3.47 起以独立包发布：`material_ui`（verified publisher `flutter.dev`）+ `cupertino_ui`；
- **SDK 内的设计库已排期在后续 stable 正式弃用**（"scheduled for formal deprecation in an upcoming stable release"）；
- 官方自动化通道：`dart fix --apply --code=migrate_design_widgets`；
- 1.0.0 与 SDK 冻结代码**逐字一致**，是官方承诺的 "seamless transition" 版本；1.4.0 起最低要求 Flutter 3.47 / Dart 3.13；
- 本机环境：**Flutter 3.47.0 / Dart 3.13.0**（`D:/flutter`），SDK 的 `packages/flutter/lib/material.dart` 在 3.47.0 **仍是完整实现而非 shim**（直接读取该文件确认）。

### 1.2 关键机制：两套 Material 是独立副本

由于 SDK 未变成 shim，`package:flutter/material.dart` 与 `package:material_ui/material_ui.dart` 是**两份独立代码副本，类型身份不同**。这决定了：

1. **不存在真正的"渐进式迁移"**——混合两套本身就会跨包错配（官方文档原文：values from `package:flutter/material.dart` cannot be assigned to parameters expecting types from `package:material_ui`）；
2. 必须一次性全量迁移，`dart analyze` 作为编译期安全网。

### 1.3 迁移面（本轮实测）

| 类别 | 数量 |
|---|---|
| lib/ 导入 SDK material | 146 处 / 134 文件 |
| lib/ 导入 SDK cupertino | 1 文件（`app_icons.dart`） |
| test/ 导入两者 | 9 文件 |
| **合计迁移** | **144 文件（135 lib + 9 test）** |

### 1.4 参考库 PiliPlus 的实况与差异

- PiliPlus 已全量迁移：**496 文件**用 `package:material_ui/material_ui.dart`，仅 1 文件残留（Linux 专用，WinWin 不涉及）；
- 它**必须自维护 GetX fork**（`bggRGjQaUbCoE/getx.git#dev`）——因为它用 `GetMaterialApp`，GetX 的 `ThemeData` 参数会撞跨包类型；
- **WinWin 无此约束**：根组件是纯 `MaterialApp`（`lib/main.dart`），GetX 仅 13 文件且只当状态管理用（无 `GetMaterialApp`、无 `Get.snackbar`/`Get.dialog`）→ **零依赖 fork**。

### 1.5 三方依赖签名耦合筛查

| 依赖 | 判定 |
|---|---|
| `cached_network_image_ce` / `window_manager` / `file_picker` / `screen_retriever` / `fvp` / `get` | ✅ 安全（仅 `Widget` 交接，无设计类型暴露） |
| `catcher_2` | ✅ 安全（`rootWidget: Widget`） |
| `flutter_inappwebview` | ⚠️ 内部用 SDK Material 且需 `MaterialLocalizations` 可解析 → **兼容桥接的目标场景** |

全库**无任何位置**把 SDK 的 `ThemeData`/`ColorScheme` 传给三方 API，即无签名耦合点。

### 1.6 SelectDialog 的问题

- 10 处调用**全部是内联复制的 `showDialog<T>` + `SelectDialog<T>`**，无共享助手；
- `toggleable` 是**全库死参数**（10 处全用默认 `false`）；
- 它只导入 `material.dart`，**是设置页唯一不感知 miuix 风格的组件**。

---

## 二、设计修复计划与实现

### 2.1 迁移（阶段 1–4）

| 决策 | 选择 | 理由 |
|---|---|---|
| 版本 | **精确锁 `material_ui: 1.0.0` + `cupertino_ui: 1.0.0`**（非 `^1.0.0`） | `^1.0.0` 会解析到 1.5.0，失去"等价替换"语义；1.0.0 才与 SDK 3.47 冻结代码逐字一致 |
| 通道 | **官方 `dart fix`**（未回退到手写脚本） | 实测 `136 fixes made in 134 files`，与预期完全吻合 |
| 三方兼容 | 保留 `MaterialUiCompatibilityBridge` | SDK 的 `MaterialApp` 通过 `_localizationsDelegates` 自动附带 `DefaultMaterialLocalizations.delegate`（`D:/flutter/packages/flutter/lib/src/material/app.dart:938`）；迁移后由 `material_ui` 的 `MaterialApp` 接管，SDK 侧子树将失去该供给。`lib/pages/login/geetest_webview_dialog.dart` 的 SDK `AppBar` 依赖 `debugCheckHasMaterialLocalizations` 断言 → **桥接是必需的，非可选** |
| 本地化 | 不改动 | 未使用 `flutter_localizations` 的 `GlobalMaterialLocalizations` |
| 依赖 fork | **零 fork** | 见 §1.4 |

**实现清单：**
1. `pubspec.yaml` 增加 `cupertino_ui: 1.0.0`、`material_ui: 1.0.0`（含中文注释说明锁定理由）；
2. `flutter pub get` → 从镜像 `pub.flutter-io.cn` 成功解析，`pubspec.lock` 锁定 1.0.0；`flutter_localizations` 作为 material_ui 的传递依赖自动引入（SDK 包，无额外下载）；
3. `dart fix --apply --code=migrate_design_widgets` → 136 修复 / 134 文件；
4. `lib/main.dart` 的 `MaterialApp.builder` 内、`AppEscapeScope` 外层加装 `MaterialUiCompatibilityBridge`（`UiStyleScope` 仍为最外层，整树重建语义不变）。

**重要发现（官方桥接已被标记弃用）**：`MaterialUiCompatibilityBridge` 在 `material_ui 1.0.0` 中带 `@deprecated` 注解，原文为"temporary migration utility intended for use only while dependencies are being migrated"。分析器因此报出一条新增 `deprecated_member_use` info。处置：**保留桥接并加显式 `// ignore: deprecated_member_use` + 注释记录理由**——因为移除它会使 SDK 子树失去 localizations 供给（real defect），而官方弃用恰恰证明它就是为当前过渡期设计的。

### 2.2 SelectDialog 现代化（阶段 5）

重写 `lib/pages/setting/widgets/select_dialog.dart`：

- **对齐 PiliPlus 现代写法**：`TextTheme.of(context)` 直取（替代 `Theme.of(context).textTheme`）、`MaterialType.transparency` 点简写；
- **双套渲染风格感知**（复刻 `subtitle_settings_panel.dart` 的面板 Dialog 写法）：
  - M3：`surfaceContainerHigh` + 圆角 24 + 无描边；
  - Miuix：`surface.withValues(alpha: 0.96)` + 圆角 16 + `outlineVariant.withValues(alpha: 0.25)` 描边；
  - 选中色：M3 用 `biliPink`、Miuix 用 `colorScheme.primary`（对齐 `coin_dialog` 的 M3 范式）；
  - 外壳加标题行 + 关闭按钮 + `Divider(height: 1)`（对齐面板惯例）；
- **尺寸策略**（有意偏离 PiliPlus）：PiliPlus 用 `tightFor(width: 320)` 硬定宽；本项目实测存在 31 字符说明文案（"M3 原生控件 + 标准 tonal elevation"）会被硬换行，改为 `minWidth: subtitleBuilder != null ? 320 : 0` + `maxWidth: 420` + `maxHeight: 640`；
- **删除死参数 `toggleable`**（全库 0 处使用，属清零）；
- **新增 `showSelectDialog<T>()` 助手**，消灭 10 处复制；保持"点选即提交"与 `null = 取消` 契约不变，调用处的 `if (res != null) { 落盘; setState(); }` 逻辑**未动**（不把持久化入口藏进助手）；
- 10 处调用点改造：`extra_settings.dart:26,49`、`video_settings.dart:35,52,70,92,109,132`、`style_settings.dart:26,66`。

**Esc 语义未受影响**（先验证后改造）：`app_escape_scope.dart` 按**路由类型**判定弹层（`_routes.last is PopupRoute`），与弹窗内部结构无关；设置弹窗从不注册进 `EscapeLayerRegistry`（后者只覆盖无路由浮层）。

---

## 三、修复效果验证

### 3.1 静态检查（`dart analyze`）

| 时点 | error | warning | info | 合计 |
|---|---|---|---|---|
| 改造前（基线） | 0 | 0 | 6 | 6 |
| 迁移后（阶段 2 末） | 0 | 0 | 6 | 6 |
| 加桥接后（阶段 4 末） | 0 | 0 | **7**（+1 桥接弃用） | 7 |
| **最终（阶段 5 末）** | **0** | **0** | **6** | **6** |

最终 6 条 info 与改造前基线**逐条一致**（历史遗留，非本次引入）：`unintended_html_in_doc_comment`、`library_private_types_in_public_api`、2×`constant_identifier_names`、2×`use_build_context_synchronously`。新增的桥接弃用 info 已用显式 ignore 消除。

### 3.2 定点归零校验（grep）

| 检查项 | 结果 |
|---|---|
| lib/ + test/ 中 `import 'package:flutter/material.dart'` | **0**（仅 `docs/` 历史分析文档残留） |
| lib/ + test/ 中 `import 'package:flutter/cupertino.dart'` | **0** |
| `import 'package:material_ui/material_ui.dart'` 等新导入 | 136 处 / 134 文件（与预期吻合） |
| SDK 其他库导入（widgets/foundation/services…） | 未被误改 |
| `toggleable` | **0** |
| `SelectDialog<` 直接构造 | 仅剩定义处 + 助手内部（10 处调用点全部走 `showSelectDialog`） |

### 3.3 测试

**`flutter test`：101 个测试全部通过**（含 9 个 widget 测试文件——这是双份 Material 类型错配最快的探测器；`app_escape_scope_test.dart` 的对话框 Esc 用例亦通过）。

### 3.4 双配置编译（Windows，AGENTS.md 核心规则 2）

| 配置 | 结果 | 耗时 | 产物 |
|---|---|---|---|
| **Debug** | ✅ 通过 | 63.2s | `build\windows\x64\runner\Debug\winwin.exe`（`data/` 于 00:15 重新生成） |
| **Release** | ✅ 通过 | 112.9s | `build\windows\x64\runner\Release\winwin.exe`（`data/` 于 00:18 重新生成） |

**警告：0**（两个配置均无 compiler warning；C++ runner 未重新链接属正常——仅 Dart 代码变更时 Flutter 复用既有 exe，实际产出为 `data/` 内的 Dart 快照，时间戳已核实为新生成）。

> 说明：过程中曾误将 Debug 构建放后台、同时又在前台启动同配置构建，两者争用同一输出目录导致后台任务退出码 1；前台构建成功。Release 为独立串行执行，未受影响。

### 3.5 实机验证清单（待用户执行，验证后回填）

**迁移线：**
- [ ] 三种 UI 风格 × 明暗主题切换，无视觉回退（M3 / Miuix 配色、圆角、阴影）
- [ ] 全局 Esc 分层：对话框 → 二级浮层 → 输入失焦 → 返回上一级，逐层各消耗一次
- [ ] 播放器：控制栏、章节/音量浮层、画质/音轨/倍速菜单（MenuAnchor 深色样式）
- [ ] 直播页、登录页（**极验 WebView 弹窗 —— 桥接专属验证点**）、会员空间
- [ ] 设置页全项（含 10 处 SelectDialog 入口）
- [ ] 首页/动态/历史/消息/我的五页滚动与图片加载（`cached_network_image_ce`）
- [ ] 视频播放正常（`fvp`/`mdk`），弹幕渲染正常（`canvas_danmaku`）

**SelectDialog 线（风格感知专项）：**
- [ ] M3 风格：点任一设置项 → 弹窗为 `surfaceContainerHigh` + 圆角 24 + 标题行 + 关闭按钮
- [ ] Miuix 风格：同一入口 → 弹窗为 `surface` 半透明 + 圆角 16 + 描边
- [ ] 弹窗内点选某项 → 立即提交并关闭，副标题/数值即时刷新
- [ ] 界面风格弹窗的说明文案（"M3 原生控件 + 标准 tonal elevation"）完整显示、不溢出
- [ ] 弹窗打开时按 Esc → 仅关闭弹窗且**不写入**（取消语义），再按 Esc 才返回上一级

---

## 四、本轮修复总结

**改动面**：**136 文件，+382 / -280 行**（含 `pubspec.yaml`、`pubspec.lock`、`lib/main.dart`、`lib/pages/setting/widgets/select_dialog.dart` 与 3 个设置模型文件，其余 131 文件为导入替换）。另有本文档。

**行为预期**：
- 全库 Material/Cupertino 组件改由官方独立包提供，与 SDK 3.47 冻结代码等价（1.0.0），**预期零视觉变化**；
- SDK 内设计库的弃用倒计时对 WinWin 不再构成阻塞（已在新包轨道上）；
- SelectDialog 获得风格感知（M3/Miuix 双外观）与统一调用入口，10 处复制样板清零，死参数清零；
- Esc 分层与"点选即提交"交互语义保持不变。

**遗留项（本轮不做，已记录）**：
1. **升级评估**：`material_ui 1.0.0 → 1.5.0`（IconButton 的 M3 Expressive 支持、M3 对比度基线、`StyleVariant` 枚举等）。需单独快照 + 单独回归，重点看 `app_theme.dart` 与 `app_components.dart`；
2. **桥接摘除评估**：待 `flutter_inappwebview` 上游迁移到 material_ui 后移除此桥接。判据：grep 三方包源码中 `package:flutter/material.dart` 是否归零；摘除时可顺带移除 `// ignore: deprecated_member_use`；
3. **三方弃用清理**：`lib/pages/login/geetest_webview_dialog.dart:190/201` 的 flutter_inappwebview 弃用 API（随包升级处理）；
4. **SelectDialog 测试补齐**：当前零覆盖，可补 widget 测试锁定"点选即提交 + Esc 取消不写入"契约。

---

## 五、GitHub 提交记录与回滚

**快照（改动前基准）**：
- `f479f37957fbd87c4800186eb207a98dd2468ee9`
- 指向：`refs/snapshots/latest`；stash：`snapshot_20260930_000032`
- 回滚命令：`git reset --hard f479f37957fbd87c4800186eb207a98dd2468ee9`

**提交**（按 bracketed conventional 格式，UTF-8 无 BOM 文件 + `git commit -F`）：
- `a35edb2` [chore](taste): 提交累积的偏好学习记录（前置清理，非本轮功能改动）
- `9a7b769` [refactor](theme): 全库迁移至 material_ui/cupertino_ui 独立包（132 文件）
- `a149329` [refactor](setting): SelectDialog 现代化 — 对齐 PiliPlus + 双套渲染 + 共享助手（4 文件）
- 本文档提交：`[docs](migration): material_ui 迁移与 SelectDialog 现代化复盘`（hash 待回填）

**推送状态**：按用户惯例，**推送在会话末尾统一执行**；待回填。

> 补记说明（按全局开发规定，提交 hash 事后回填）：迁移与 SelectDialog 两笔提交的 hash 已回填如上；本文档自身的提交 hash 由本次补记提交承载，回填于文末。
