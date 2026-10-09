# AppScaffold 补 Material 祖先根治红屏复盘 — 2026-10-09

> 回归来源：**B5（页面骨架）**；承接 `三页面样式布局修复复盘-2026-10-09.md`（`9992bff` 修后仍红屏）。
> 代码提交：`9da1ce4`。

## 1. 现象描述

上一轮修复后四页仍红屏，用户截图钉死为 **`No Material widget found` 硬崩溃**：

- 聊天页 / 专栏页 / 视频页的 `TextField`（评论/弹幕输入框）；
- 用户空间页的 `InkWell`（`_InkResponseStateWidget`）。

各页祖先链自 `MiuixScaffold→AppScaffold` 往上**无任何 `Material`**；另伴随错误文本自身的
`BOTTOM OVERFLOWED BY 29067/99029 PIXELS`（红屏错误 UI 的连带症状，非独立布局 bug）。

## 2. 定因（根因链）

B5-3 将骨架从 Material `Scaffold` 换成纯 widgets 实现的 `MiuixScaffold` 后，
整棵 `AppScaffold` 体系失去 `Material` 祖先。`TextField`/`InkWell`/`ListTile` 等
Material 系控件构建时断言要求祖先 `Material`，缺失即整页红屏。
上一轮只治了水波警告与顶栏叠加，没补祖先，故未修复。

全量审计 26 处 `TextField`：除 `AppScaffold` 体系外，其余均在自供 Material 的容器下，
无需改动——原生 `Scaffold`（直播页 `live_room_page.dart:852`、搜索页）、
`Dialog`（弹幕屏蔽）、`AlertDialog`（粉丝牌编辑/追番跳转）、`SimpleDialog`（追番状态）；
登录页 `AppTextField` 内核为 `MiuixTextField`，本就不依赖 Material。

## 3. 修复方案

`lib/core/shell/app_scaffold.dart`（单文件 +15/−2，**单点根治**，各页零负担）：

```dart
// B5-3 起骨架改用纯 widgets 实现的 MiuixScaffold，树上不再有 Material 祖先……
// 此处统一补一层透明 Material（复用 session_list_section.dart 成熟模式）。
final body = Material(
  type: MaterialType.transparency,
  child: widget.body,
);
```

- `reserveTopStrip` 双分支共用同一 `body`；顶部安全行置于 `Material` 之外，
  水波绘制限定在 body 区域内；
- 过渡期 import `material_ui` 的 `Material/MaterialType`（B7 摘除依赖时换 miuix 表面容器）；
- 条带 `IconButton` 经截图实证不受影响（顶栏按钮正常渲染），不改动。

## 4. 验证

| 项 | 结果 |
| --- | --- |
| `dart analyze` | **0 问题** |
| `flutter build windows --debug` | ✅ 30.2s（编前按约定自动结束残留 `winwin.exe`，无 DLL 锁死中断） |
| `flutter build windows --release` | ✅ 77.5s |
| 实机 | Release 产物已自启（PID 14332），待用户复验：视频/专栏/空间/会话页输入框与点击水波 |

## 5. GitHub commit 提交记录

- 改动前快照：工作区干净，无新 stash（`refs/snapshots/latest = 0c449584`）
- 代码提交：`9da1ce4`（已推送 `9992bff..9da1ce4`）
- 回滚基准：`git reset --hard 9992bff`

## 6. 遗留与踩坑

- **遗留**：`MiuixPopupMenu` 等 Overlay 弹层内容与页面 body 是 `Overlay` 下的兄弟关系，
  看不到 body 层 `Material`；当前弹层内无 Material 系控件暂无风险，B6 后续若往弹层加输入框需单独包 `Material`。
- **踩坑**：本轮确立构建工作流约定——双编译前自动结束锁 DLL 的残留进程，完成后自动启动本轮产物
  （已记入项目记忆，并回填至进度追踪口径节）。

## 7. 总结

红屏根因在骨架层而不在各页，已单点根治并全量排查同类站点；双分支构建通过，
补丁 `9da1ce4` 已上线。B5 回归至此收口，后续可回 B6-2（Icons→AppIcons）。
