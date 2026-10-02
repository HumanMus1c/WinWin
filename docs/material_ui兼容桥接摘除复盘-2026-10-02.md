# material_ui 兼容桥接摘除复盘（R4，2026-10-02）

**范围**：R4「兼容桥接摘除」——上一轮评估（`docs/material_ui升级与遗留项复核复盘-2026-10-02.md` 附录 B）经本轮全依赖审计改判为「可摘除」，实施摘除并验证。
**执行计划**：`~/.commandcode/plans/material_ui兼容桥接摘除计划-2026-10-02.md`（2026-10-02 面板批准）。

---

## 一、分析根因（为什么摘、判据为什么变）

### 1.1 旧结论与旧判据

- 附录 B 旧判据：「grep 三方包源码中 `package:flutter/material.dart` 是否归零」，未归零（inappwebview 家族 5 处导入）→ 保守维持。
- 复核发现：**判据过粗**——import 存在 ≠ 运行时有 SDK 设计状态消费者。

### 1.2 本轮审计（证据链）

1. **桥接提供面**（material_ui 1.5.0 `src/migration_utility.dart:75`）：实际只提供两样——
   - SDK `ThemeData`（映射 colorScheme / textTheme / platform / visualDensity）；
   - SDK `Localizations.override`（SDK 3.47 源码 `widgets/localizations.dart:521-540`：为**合并**语义，仅在前插入 SDK Global* delegates，不影响 material_ui 自身局部化）。
2. **缺失后果**（SDK 3.47 源码核实）：
   - `MaterialLocalizations.of`：debug 断言报错、**release 空断言崩溃**（`assert(debugCheckHasMaterialLocalizations(context)); return ...!;`）；
   - `Theme.of`：有 `_kFallbackTheme` 兜底，不崩。
   → 唯一「承重」的是 SDK localizations。
3. **全依赖扫描**（按 `pubspec.lock` 130 个已解析包逐包检索 `package:flutter/material.dart|cupertino.dart`）：命中 **22 包**；对 Windows 编译面成员继续以大小写敏感检索 + 删导入分析器实验核查。
4. **inappwebview 家族（5 处导入）删导入分析器实验**（pub 缓存副本实验，不动仓库）：
   - 主包 `src/in_app_webview/in_app_webview.dart`、windows 包 2 文件：删导入后 0 新增错误（无 material 独占符号使用）；
   - platform_interface `src/util.dart`：仅 `EdgeInsets`（数据类）；`print_job_settings.dart`：仅 cupertino 的 `EdgeInsets`。
   → 无 Material 组件 / Theme / 局部化使用。
5. **其余编译面成员**：
   - `cached_network_image_ce` / `flutter_staggered_grid_view`：material 仅作 widgets 伞（Widget/Key/EdgeInsets 级，大小写敏感全包零 Material 独占符号）；cached 无占位/进度时强制空 `Container()`，octo 的 material 默认件不可达；
   - `catcher_2`：SilentReportMode；material UI（AlertDialog/Scaffold/TextButton…）无调用方，`addDefaultErrorWidget` 全包仅定义未调用；即便启用也仅用 `Theme.of`（兜底安全）；
   - `window_manager`：material 组件（WindowCaption/VirtualWindowFrame…）项目 0 使用；
   - `octo_image` / `video_player` / `fluttertoast`：默认件不可达 / 仅 `Colors`·`DefaultTextStyle` / 未使用（经 catcher 传递引入）；
   - 全库唯一 SDK `MaterialLocalizations` 调用点在 `get` 的导航代码（`extension_navigation.dart` / `bottomsheet.dart`），项目 0 使用（仅状态管理）。
6. **结论**：Windows 编译面不存在运行时可达到的 SDK `MaterialLocalizations` / `Theme` 消费者 → **摘除可行**。

### 1.3 附加动机

- 桥接在 material_ui 1.x 已 `@Deprecated`（"will be removed in a future release"）；维持 = 把可控摘除拖成未来升级时的被迫迁移。

**复查命令（本机）**：
```powershell
# 依赖面导入扫描（按 lock 版本）
$cache="$env:LOCALAPPDATA\Pub\Cache\hosted\pub.flutter-io.cn"
Get-ChildItem "$cache\flutter_inappwebview*\lib" -Recurse -Filter *.dart |
  Select-String -CaseSensitive 'MaterialLocalizations|debugCheckHasMaterialLocalizations'
```

---

## 二、设计修复计划与实现

- **决策**：执行摘除；不动 `cupertino_ui`、其他依赖与已验收功能。
- **改动面**（`lib/main.dart` 单文件，+7/-12 行）：
  - 移除 `MaterialUiCompatibilityBridge` 包装层与 `// ignore: deprecated_member_use`；
  - `UiStyleScope` / `AppEscapeScope` 层级与整树重建语义不变；
  - 注释更新为摘除说明（含本文档引用）。

---

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 error / 0 warning / 6 info**（与基线逐条一致，零新增；弃用 ignore 一并清零） |
| `flutter test`（全量） | **105/105 通过** |
| `flutter build windows --debug` | ✅ 通过（37.7s） |
| `flutter build windows --release` | ✅ 通过（105.5s） |
| 产物取证 | Debug `data/flutter_assets` 2026-10-03 00:08:05、Release `data/app.so` 2026-10-03 00:09:56 均为新生成；exe 未重链属正常（仅 Dart 变更） |

### 实机验证清单（待用户执行，验证后回填）

- [ ] 启动 → 首页/动态页滚动（瀑布流 + 图片占位、视频卡片）
- [ ] 登录页极验弹窗全流程（成功 / 取消 / Esc 关闭）—— 摘除后**重点项**
- [ ] 设置页 SelectDialog 10 处入口（点选即提交、Esc 取消不写入）
- [ ] 播放器：控制栏、章节 / 音量浮层、画质 / 音轨 / 倍速菜单
- [ ] 三风格 × 明暗切换（含个人页 / 设置页 / 首页）
- [ ] 全程无 `No MaterialLocalizations` / 空断言类报错（可查 `Documents/logs/runtime.log`）

---

## 四、本轮修复总结

- **改动面**：`lib/main.dart` 1 文件（+7/-12）；另有本文档与旧复盘附录 B 注记。
- **行为预期**：**零预期视觉/行为变化**（审计结论：无消费者）；消除 1 处 deprecated 依赖面与一层包装节点。
- **遗留项**：无新增；`cupertino_ui 1.1.1` 独立评估（可选，非阻塞）。

---

## 五、GitHub 提交记录与回滚

**快照（改动前基准）**：
- 前置清理：`926357f`（`[chore](taste)`，非本轮功能改动）
- 基准 = `HEAD`：`926357fd2a09bdc718969fd188e755c3a7d5a1f2`；`refs/snapshots/latest` 已同步指向该提交；无新增 stash 条目（干净树无内容可暂存）
- 回滚命令：`git reset --hard 926357fd2a09bdc718969fd188e755c3a7d5a1f2`

**提交**：
- `a2898b2` [refactor](theme): 摘除 material_ui 兼容桥接（R4 全依赖审计通过）
- 本文档提交 hash：`8d78cfc`（本补记提交承载回填）

**推送状态**：已推送 `origin/main`（`6f1ccee..8d78cfc`，含前置清理 / 代码 / 本文档；本补记提交随第二次推送同步，补记链终止）。
