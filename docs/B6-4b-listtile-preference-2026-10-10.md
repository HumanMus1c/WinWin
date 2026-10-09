# B6-4b 复盘：ListTile / SwitchListTile 偏好化 — 2026-10-10

## 1. 现象描述

B6-4a（Card 批）后，`lib` 内仍有 Material `ListTile` **16 处**（8 文件）
与 `SwitchListTile` **1 处**：画廊操作表 3、弹幕屏蔽规则行 1、搜索
骨架/热榜/建议 3、消息流通知行 5（@我/赞我/回复我/赞详情/系统消息）、
会话列表行 2、会话设置 2 + 免打扰开关 1。B7 摘除依赖前须全部迁移。

## 2. 根因

`ListTile`/`SwitchListTile` 属 material_ui 家族（自带 Material 祖先与 ink
反馈）。迁移目标为 flutter_miuix 原生偏好行：`MiuixBasicComponent`
（title/summary/startAction/endActions/content/onClick）与
`MiuixSwitchPreference`。

## 3. 修复方案（逐站映射）

- **简单行**（画廊×3、搜索建议、热榜、搜索骨架、弹幕屏蔽、会话设置×2）
  → `MiuixBasicComponent`：`leading`→`startAction`、`title`→`title`（String）、
  `contentPadding`→`insideMargin`、`dense/contentPadding: zero`→
  `insideMargin: EdgeInsets.zero`、`onTap`→`onClick`。
- **富行**（msg_feed×5、会话行×2）→ `MiuixBasicComponent` +
  `content: [标题部件, 副标题部件]` **逐字保留原部件与样式**；
  `trailing`→`endActions: [..]`；`onTap`→`onClick`；
  含 `onLongPress` 的 4 站外包 `GestureDetector(onLongPress:)`
  （长按/点按手势分离，同 B6-3a 右键站手法）；
  会话行原有 `onSecondaryTapUp` 外包保持不动。
- **SwitchListTile**（消息免打扰）→ `MiuixSwitchPreference`
  （`enabled: !_busy` 表达禁用，替代 `onChanged: null`）。
- **红字行**（举报/删除会话）→ `titleColor: MiuixBasicComponentColors`
  （error/error），图标色保留在下放部件上。

## 4. 验证与回滚

- 快照：`ff0a6d80`（`refs/snapshots/latest`）兜底。
- `dart analyze` 零问题（首轮 19 处缺导入，脚本合并 `show` 列表后归零）；
  `flutter test` **164/164 全绿**；
  双分支构建通过（kernel 01:45:00 / app.so 01:46:18），构建后已自启 Release
  （PID 16428）。
- 残留复核：`ListTile` 0 处、`SwitchListTile` 0 处；闸门指标维持 **133**。
- 提交推送：`（本批回填）`（代码+复盘+进度表同批）。

## 5. 遗留与踩坑

- 遗留：B6-5（`Divider` 20 文件 + `Material(` 14 文件收尾）→ B6-6（`Colors.`）。
- 踩坑：① `MiuixBasicComponent` 无 `onLongPress` 参数——长按必须外包
  `GestureDetector`（与内层 onClick 手势天然分离）；
  ② `title/summary` 仅接受 String——富文本（Text.rich/条件样式）行必须走
  `content:` 列表，否则样式丢失；
  ③ 禁用语义：`MiuixSwitchPreference(enabled:)` / `MiuixBasicComponent` 的
  `onClick: null`；
  ④ 跨组件替换后 `show` 导入列表需 analyzer 驱动补齐（本轮 19 处）。

## 6. 总结

B6-4 全批收官：`ListTile` 16 处 + `SwitchListTile` 1 处共 **17 处行组件**
偏好化（11 文件 +288/−268）；静态检查、164 项测试、双分支构建全绿；
B6 仅剩 B6-5（Divider/Material 收尾）与 B6-6（Colors→Token）。

## 7. 测试验证指导（本轮产物）

- **画廊操作表**：保存到本地/复制直链/关闭预览三行，点击行为与弹层一致。
- **搜索**：搜索页热榜行（序号+推荐理由）、建议行、加载骨架列表观感。
- **消息中心**：@我/赞我/回复我/赞详情/系统消息行——头像、富文本标题、
  内容、时间；**长按弹删除确认**正常；点头像进空间（@我/回复我）。
- **会话列表**：行点击进会话；**右键弹更多选项**；置顶/免打扰标旗、
  未读红点、时间与三点按钮。
- **会话设置**：免打扰开关可切换（忙碌时禁用）；举报/删除会话两行红字与
  点击行为。
- **预期结果**：行高/间距因偏好行口径可能轻微变化（已是 Miuix 行样式）；
  功能齐全无失灵；异常即回退。
- **日志**：复测后核对 `D:\Documents\.winwin_logs.json` 与
  `D:\Documents\logs\runtime.log` 有无新增条目。
