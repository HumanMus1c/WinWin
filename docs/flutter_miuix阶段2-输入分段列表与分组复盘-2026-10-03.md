# flutter_miuix 分阶段替换 · 阶段2（输入 / 分段 / 列表行 / 分组）复盘 — 2026-10-03

> 五要素结构：分析根因（背景与源码盘点）/ 设计修复计划 / 修复效果验证 / 本轮修复总结 / 提交记录。
> **用户硬性约束**：保留首页搜索框与分类筛选器**整个控件的背景模糊效果**。
> 关联：阶段1 复盘 `docs/flutter_miuix阶段1-桥接与试点复盘-2026-10-02.md`、计划 `~/.commandcode/plans/flutter-miuix替换阶段2-输入分段列表与分组.md`。

---

## 一、分析根因（背景与源码盘点）

**背景**：阶段1（桥接 + 4 组件）实机复测通过后，用户确认继续阶段2，并提出硬性约束：
保留首页搜索框与分类筛选器的整体控件背景模糊。

**源码盘点结论（取证链）**：

1. **约束落点**：首页搜索框/分类筛选器为 `lib/ui/home/home_page.dart` 中 `_HomeHeader` 自研实现，
   整体包裹于 `ClipRRect + BackdropFilter(ImageFilter.blur(20))` 毛玻璃容器（miuix 分支）；
   → 本轮**零改动该文件**即可完整保留模糊效果（约束以"不迁移动它"兑现）。
2. **AppTextField（登录页 5 处）**：全部携带 `inputFormatters`；而 flutter_miuix 1.3.0 的
   `MiuixTextField` 经 pub 缓存源码逐项核对**无 `inputFormatters` 参数** →
   设计控制器层过滤桥接（复用官方 `TextInputFormatter.formatEditUpdate`，与 EditableText
   内部同一机制），AppTextField 由 Stateless 转 Stateful 承载代理控制器。
3. **AppSegmentedControl**：仅登录页使用（密码/短信/扫码/Cookie 四段）→ `MiuixTabRow`
   （`tabs/selectedTabIndex/onTabSelected` 一一对应）。
4. **行与分组**：`AppGroup → MiuixCard`（外层 `ClipPath(ShapeBorderClipper(MiuixSquircleBorder))`
   保证行内按压不溢出）；`AppListItem/NormalItem → MiuixBasicComponent`；
   `SetSwitchItem`（非 split）→ `MiuixSwitchPreference`（整行点按即切换，语义对齐）。
5. **关键发现（新 SDK Material 消费者）**：`MiuixTextField` 内部使用 **SDK `flutter/material`
   的 `TextField`**；本项目整树基于 `material_ui`（独立延续库，自有 Material/Localizations 类）。
   SDK 材料组件需要：SDK `MaterialLocalizations`（本轮审计复核 SDK 源码：release 下空断言
   崩溃）与 SDK `Material` 祖先（debug 断言）→ 此前"material_ui 兼容桥接摘除"的判据
   （Windows 编译面无运行时可达到的消费者）因输入框引入而失效，**按最小作用域恢复桥接**。
6. **本轮明确不迁移**（与原计划一致）：`AppRefreshIndicator → MiuixPullToRefresh`
   （需 8+ 页面把刷新状态提升为 `isRefreshing`，列为阶段2b）；`AppActionTile`（Miuix 无
   对应网格动作组件）；SearchPage 搜索框（与首页同视觉语言，保持自研）。

---

## 二、设计修复计划（方案与关键决策）

- **改动面（3 个实现文件 + 1 测试文件）**：
  - `lib/ui/components/app_components.dart`：AppTextField（格式化桥接 + MiuixTextField +
    material_ui 桥接包裹）、AppSegmentedControl、AppGroup、AppListItem；
  - `lib/pages/setting/widgets/normal_item.dart`：miuix 分支 → MiuixBasicComponent；
  - `lib/pages/setting/widgets/set_switch_item.dart`：非 split miuix 分支 → MiuixSwitchPreference；
  - `test/ui/components/miuix_adoption_test.dart`：新增阶段2 四组用例。
- **格式化桥接**（`_FormatterProxyController`）：改写控制器 `value` setter，在写入前经官方
  formatter 链过滤；`_inner` 为外部/自建基础控制器；生命周期由 AppTextField 状态管理
  （didUpdateWidget 处理 controller 变更；上游补齐参数后整体移除）。
- **material_ui 桥接恢复（最小化）**：仅包裹输入框子树：
  `MaterialUiCompatibilityBridge(child: legacy.Material(type: transparency, child: MiuixTextField))`；
  `// ignore: deprecated_member_use`（官方迁移工具，deprecated；若 material_ui 未来移除该 API，
  改为手写等价 ThemeData/Localizations 注入）。
- **首页头部**：零改动（约束兑现）。

---

## 三、修复效果验证

### 3.1 编译与静态检查（已完成）

| 项目 | 结果 |
|---|---|
| 快照（回滚基准） | `35a13b798a874d5037fc4091fa1b7aee6f621f0f`（`refs/snapshots/latest`） |
| `dart analyze` | **0 错误 0 警告**（6 条 info 为既有存量，逐条与基线一致） |
| `flutter test` | **114/114 全部通过**（新增 4 例：输入框格式化过滤 / TabRow 切换 / Card+行组件渲染 / 行点击回调） |
| `flutter build windows --debug` | ✅ 33.3s，0 警告 0 错误 |
| `flutter build windows --release` | ✅ 76.9s，0 警告 0 错误 |

调试期修复记录：首轮测试暴露 SDK TextField 材料依赖（`No Material widget found` +
`Bad state`）→ 以最小桥接包裹修复，单测复跑通过后全量通过。

### 3.2 实机验证（待做 — 用户操作）

- [ ] 1. **约束项**：首页搜索框 + 分类筛选器**毛玻璃背景完整保留**（切到 Miuix 后滚动浏览，模糊正常）。
- [ ] 2. 登录页 4 个输入框：Miuix 浮动标签 + 聚焦 squircle 边框；输入空格/字母验证过滤
      （手机号与验证码仅数字、账号/密码/Cookie 拒绝空白）；「获取验证码」按钮、区号下拉、多行 Cookie 可用。
- [ ] 3. 登录页分段控件为 Miuix TabRow，四段切换正常。
- [ ] 4. 设置/关于/我的：分组为 squircle 圆角（MiuixCard），行样式为 Miuix 行 + 按压反馈。
- [ ] 5. 设置项开关：普通行整行点按即切换；split 行（左进入子页/右独立开关）保持原行为。
- [ ] 6. 切回 Material 3：上述控件全部恢复原样，无布局错位。
- [ ] 7. 日志取证：`miuixAdopt: scope active` 可见；无新增 [E] / 崩溃报告。

> 异常则截图/日志回传；必要时 `git reset --hard 35a13b798a874d5037fc4091fa1b7aee6f621f0f` 秒级回滚。

---

## 四、本轮修复总结

- **改动面**：3 个实现文件 + 1 个测试文件 + 本复盘（另有阶段2 计划文件）。
- **行为预期**：miuix 风格下输入框 / 分段 / 分组 / 设置行改用 flutter_miuix 原生实现
  （浮动标签、squircle、整行按压语义）；MD3 路径与首页头部（含毛玻璃）不受影响。
- **遗留项**：
  1. `MiuixTextField.inputFormatters` 上游补齐后移除 `_FormatterProxyController` 桥接；
  2. `MaterialUiCompatibilityBridge` 为 deprecated API：material_ui 移除时改为手写等价注入；
  3. 阶段2b：`AppRefreshIndicator → MiuixPullToRefresh`（含页面刷新状态提升评估）；
  4. `AppActionTile` 维持自研（Miuix 无对应组件）；
  5. 阶段3 候选不变（弹窗/导航/图标/OS4 玻璃）。
- **回滚**：`git reset --hard 35a13b798a874d5037fc4091fa1b7aee6f621f0f`。

---

## 五、GitHub commit 提交记录

- 提交：`<提交后按全局开发规定回填>`（阶段2 实现 + 本文档）。
- 快照 / 回滚基准：`35a13b798a874d5037fc4091fa1b7aee6f621f0f`。
- 推送：提交后推送 `origin/main`（状态事后补记）。
