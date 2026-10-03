# flutter_miuix 修复轮3（字体弹窗搜索框）复盘 — 2026-10-03

> 五要素结构。触发：复测反馈"应用字体搜索框仍然高度异常，溢出容器"（附截图）。

## 一、分析根因

- 字体弹窗的搜索框直接使用**裸 `MiuixTextField`**；其内部由 SDK `flutter/material`
  的 `TextField` 实现，而本项目整树基于 `material_ui`（独立延续库）——需要
  material_ui→SDK 的兼容桥接（SDK `Material` 祖先 + `ThemeData` +
  `MaterialLocalizations`）。
- 缺失后果：debug 为 `No Material widget found` 断言；**release 下 SDK
  MaterialLocalizations 取不到 → 内部 TextField 渲染失败为 release ErrorWidget
  （大灰块）**。而"搜索字体…"标签由 `MiuixTextField` 自身绘制（Stack 内独立
  Text）故仍显示——外观即复测截图中的"超高搜索框溢出容器"。诊断用例可复现。
- 对照：`AppTextField`（登录页）此前已带桥接（阶段2），故只有字体弹窗暴露。

## 二、设计修复

- 抽出共用 `MiuixCompat`（`lib/theme/miuix_theme_bridge.dart`）：
  `MaterialUiCompatibilityBridge + legacy.Material(transparency)`，最小作用域；
  文件/使用处均带 `// ignore: deprecated_member_use`（官方迁移工具）。
- `AppTextField` miuix 分支改用 `MiuixCompat`（去重）；字体弹窗搜索框包
  `MiuixCompat`；搜索框保持 `singleLine: true`。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **121/121 通过**（新增回归：固定高度 Column 下 MiuixTextField 高度 <100 且宽度正常；桥接缺失时该用例可复现异常） |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证（待做）

- [ ] 1. 设置 → 外观 → 应用字体：搜索框高度正常、不溢出；搜索/点选/导入/恢复默认正常。
- [ ] 2. 登录页输入框（同走 MiuixCompat）无回归。

## 四、本轮总结

- 改动面：5 文件（bridge/app_components/style_settings/测试 + 复盘）。
- 教训归档：**凡在 miuix 风格下使用 flutter_miuix 内依赖 SDK `flutter/material`
  的组件（当前为 MiuixTextField），必须包 `MiuixCompat`**——后续 sweep 若引入
  MiuixSlider 之外的 SDK 材料类组件时按此规则执行。

## 五、GitHub commit 提交记录

- 修复提交：`d2bb6b415f3335569afa5358531c846f3d7b6cbd`（[fix](miuix): 字体弹窗搜索框补 SDK 材料桥接（修复高度异常溢出），4 文件 / +78 −19；按全局开发规定补记）。
- 本 `[docs]` 提交随同推送 `origin/main`。
