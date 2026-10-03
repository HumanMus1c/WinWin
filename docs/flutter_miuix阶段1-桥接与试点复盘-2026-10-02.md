# flutter_miuix 分阶段替换 · 阶段1（桥接与试点）复盘 — 2026-10-02

> 五要素结构：分析根因（背景与调研取证）/ 设计修复计划 / 修复效果验证 / 本轮修复总结 / 提交记录。
> 关联：`pubspec.yaml` 依赖注释、`lib/theme/miuix_theme_bridge.dart`、阶段计划 `~/.commandcode/plans/flutter-miuix替换阶段1-桥接与试点.md`。

---

## 一、分析根因（背景与调研取证）

**起因（用户问题）**：本项目 miuix 是否是最新版本库？能否更新到最新版？BiliPai 用的是
`compose-miuix-ui/miuix` 还是 `ChuxinNeko/flutter_miuix`？能否为本项目更换为后者？

**取证链**：

1. **本项目（改动前）没有任何 miuix 第三方依赖**——`pubspec.yaml` 全量核对 +
   全库 grep：`miuix` 是自研风格层（`UiStyle.miuix` 枚举 + `AppShapes/AppChrome/
   AppTypography` Token + 16 处组件的 miuix 分支）。→ 结论：不存在"可升级的 miuix 库"。
2. **BiliPai 使用 `compose-miuix-ui/miuix`（Kotlin/Compose KMP）**：
   `gradle/libs.versions.toml` 声明 `miuix = "0.9.4-5c91d5e5-SNAPSHOT"`，坐标
   `top.yukonga.miuix.kmp:*`（ui/preference/blur/shader/squircle/icons/nav），经
   GitHub Packages 分发；全仓 0 个 `.dart`/`pubspec.yaml`（Kotlin 项目）。
3. **上游最新为 v0.9.4（2026-09-20 发布）**——BiliPai 的 0.9.4 快照基本已在最新线，
   无需升级动作；其本地 `:miuix-navigation` 属仓内 vendored 副本（与本次无关）。
4. **`ChuxinNeko/flutter_miuix` 确实存在且可用**：miuix 的 Flutter 1:1 移植；
   pub.dev 最新 **1.3.0**（约 2 个月内 15 个版本、迭代活跃）；Apache-2.0；纯 Dart +
   frag 着色器；**支持 Windows**；`sdk: ^3.12.2` 与本机 Flutter 3.47.0 匹配。
   另外：pub 缓存源码逐项核对（`MiuixSwitch/MiuixButton/MiuixCard/
   MiuixLinearProgressIndicator/MiuixTheme` 全量签名与内容色传播机制），非凭文档臆断。
5. **决策（用户确认）**：分阶段替换——先试点高收益控件，material3 路径与页面骨架不动，
   每阶段实机验证、可回退。

---

## 二、设计修复计划（方案与关键决策 / 取舍）

### 2.1 依赖

- `pubspec.yaml`：新增 `flutter_miuix: 1.3.0`（**精确锁定**；社区年轻库，升级单独评估，
  可整体回退）。解析结果：`dynamic_color 1.9.0`、`material_color_utilities 0.13.0`
  同步引入（后者传递依赖；前者自带 Windows 插件实现，已随双构建验证）。

### 2.2 主题桥接（新增 `lib/theme/miuix_theme_bridge.dart`）

- **配色**：以 `lightColorScheme()/darkColorScheme()` 为底，`copy(...)` 逐字段覆盖
  `colors.dart` 的 `miuixLight*/miuixDark*` 调色板（primary/onPrimary/primaryContainer/
  tertiaryContainer/background/surface/surfaceContainer(+Highest)/onSurface/outline/
  dividerLine/error）。未映射字段（`secondary/disabled*` 族）保留 flutter_miuix 默认值：
  WinWin 无等效 Miuix 语义 token，且 HyperOS 关闭态开关轨道依赖默认浅灰/深灰。
- **字体**：`defaultTextStyles()` 全部 14 个字段注入 `AppFontNotifier` 字体族。
- **`MiuixThemeScope`**：`main.dart` 的 `MaterialApp.builder` 内按
  `uiStyle == UiStyle.miuix` 条件包裹（位于 Navigator 之上，覆盖全部路由）；
  isDark 用 `Theme.of(context).brightness` 解析（本机 Flutter SDK 源码确认 builder
  上下文即为正确取 Theme 而设计）。落 `Coverage` 覆盖日志：
  `miuixAdopt: scope active/changed`（Release 可查，grep 可取证）。

### 2.3 组件替换（仅 `PrimitiveRenderer.miuix` 分支；MD3 分支行为保留）

| 组件 | 替换为 | 备注 |
|---|---|---|
| `AppSwitch` | `MiuixSwitch` | 删除原 `Transform.scale(0.85)` 近似 |
| `AppPrimaryButton` | `MiuixButton` + `buttonColorsPrimary` | expanded → `SizedBox(double.infinity)`；**渐变→纯色属预期视觉变化** |
| `AppCard` | `MiuixCard` | squircle 圆角；颜色显式取 colorScheme（保持视觉连续性） |
| `AppProgressBar` | `MiuixLinearProgressIndicator` | 保留 tertiary/3px 配色 |

### 2.4 关键取舍

- **保留现有配色**（copy 覆盖）而非换用 flutter_miuix 默认蓝 → 视觉连续性优先；
- 按钮/开关的动效与几何改用原生实现（folme 弹簧 / squircle / 49×28 轨道），
  近似实现退场 → 这是替换的核心收益；
- 本轮**不动**图标层、弹窗面板、导航、玻璃材质（阶段2/3 另评）。

---

## 三、修复效果验证

### 3.1 编译与静态检查（已完成）

| 项目 | 结果 |
|---|---|
| 快照（回滚基准） | `8b9958d79d43332ffdd89e60de21f0dfc3e913ed`（`refs/snapshots/latest` / `stash@{0}`） |
| `dart analyze` | **0 错误 0 警告**；另有 6 条 info 级既有提示（account_service / keyword_filter_policy / home_feed_anonymizer_policy / login_page 等——均为本次未触碰文件，存量） |
| `flutter test` | **110/110 全部通过**（含新增 `test/ui/components/miuix_adoption_test.dart` 5 例；更新 `badges_and_interaction_test` 双风格断言） |
| `flutter build windows --debug` | ✅ 42.0s，0 警告 0 错误 → `build\windows\x64\runner\Debug\winwin.exe` |
| `flutter build windows --release` | ✅ 85.6s，0 警告 0 错误 → `build\windows\x64\runner\Release\winwin.exe` |

测试输出取证：`Coverage: miuixAdopt: scope active isDark=false font=system`（测试运行可见）。

### 3.2 实机验证（已完成 — 2026-10-03 复测 + 日志取证）

- [x] 1–5. 用户于 2026-10-03 复测通过（Miuix 风格下开关 / 主按钮 / 卡片 / 进度条外观与交互正常；
  会话路径覆盖界面风格弹窗、Esc 层级、视频起播/退出、登录页进入等，无异常迹象）。
- [x] 6. 日志取证（`D:\Documents\logs\runtime.log`，2026-10-03 复测会话）：
  - `2026-10-03T13:20:40.348265 [W] Coverage: miuixAdopt: scope active isDark=false font=PingFang SC`
    → 桥接 Scope 实机生效（Release 运行；字体注入 = 用户导入字体 PingFang SC）。
  - 2026-10-02 / 10-03 全量检索：**0 条 [E]**（全文件 4 条 [E] 均为 09-28/09-29 旧会话）；
    无 Miuix / 着色器 / 布局溢出 / dynamic_color 相关告警。
  - `.winwin_logs.json` 末次写入 2026-10-02 19:03（早于本次构建）：复测期间**无新增崩溃报告**。
  - 说明：本次会话未发生 m3↔miuix 往返切换（风格弹窗以 cancelled 关闭）；切换路径此前会话
    （10-02 22:31 material3→miuix、10-02 17:54 miuix→material3）已有记录，且由单测覆盖。
- 结论：阶段1 复测通过、无回归证据，可进入阶段2。

> 回滚基准保持 `8b9958d7…`；如需回滚 `git reset --hard 8b9958d79d43332ffdd89e60de21f0dfc3e913ed`。

---

## 四、本轮修复总结

**改动面（9 个既有文件 + 2 个新文件 + 本复盘）**：

- `pubspec.yaml` / `pubspec.lock`：依赖引入；
- `lib/theme/miuix_theme_bridge.dart`（新）：桥接；
- `lib/main.dart`：builder 链接线；
- `lib/ui/components/app_components.dart`：4 组件分支替换；
- `test/ui/components/badges_and_interaction_test.dart`（更新）、
  `test/ui/components/miuix_adoption_test.dart`（新）；
- `windows/flutter/generated_plugins.cmake` / `generated_plugin_registrant.cc`：
  `dynamic_color` 插件注册（由 `flutter pub get` 自动生成，双构建已验）；
- 本复盘文档。

**行为预期**：miuix 风格下上述四类控件使用 flutter_miuix 原生实现（更贴近 HyperOS 规范）；
MD3 路径与其余 12 处 miuix 分支行为不变。

**遗留项 / 后续**：

1. 阶段2：输入框/搜索框（MiuixTextField/MiuixInputField）、分段控件（MiuixTabRow 评估）、
   列表行（AppListItem/NormalItem/SetSwitchItem）、AppGroup/AppActionTile、下拉刷新；
2. 阶段3（评估后启动）：弹窗/面板（优先不依赖 MiuixScaffold 的 `MiuixWindow*` 系列）、
   Snackbar、导航（Floating/Glass NavigationBar、NavigationRail）、图标体系（AppIcons 重构）、
   OS4 玻璃（先探测 shader 支持：`MiuixGlassRendering.loadError/loadedPrograms/has()`）；
3. 细节候选：disabled* 色族按需增补映射；`fontWeightAdjustment` 未接 `boldText`；
   `MiuixLinearProgressIndicator` 在 0 进度时会显示最小圆头胶囊（与旧表现差异，实机对照后定）；
4. 历史清点发现（未处理）：`Pref.uiStyle` 为死代码且默认值口径与 notifier 冲突（0→miuix vs material3）。

---

## 五、GitHub commit 提交记录

- 阶段1提交：`daef8cbe28d69995819a236f6decc67c24afcb03`（`[feat](miuix): 引入 flutter_miuix 桥接并试点替换 4 个自适应组件（阶段1）`，12 文件 / +526 −53）
  + `637c764`（docs 回填）——已于 **2026-10-03 推送 `origin/main`**。
- 复测回填：本 `[docs]` 提交（提交 hash 按全局开发规定事后补记；随同阶段1一并推送）。
- 快照 / 回滚基准：`8b9958d79d43332ffdd89e60de21f0dfc3e913ed`
  （改动前状态；`git reset --hard 8b9958d79d43332ffdd89e60de21f0dfc3e913ed` 秒级回滚）。
