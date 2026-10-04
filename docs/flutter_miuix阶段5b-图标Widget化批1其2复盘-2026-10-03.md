# flutter_miuix 阶段5b（图标 Widget 化 批1 其二）复盘 — 2026-10-03

> 五要素结构。范围：AppEmptyState / GlassControlButton / AppListItem 三部件。

## 一、分析根因 / 现状取证

- `AppEmptyState`：`IconData icon`（默认 `Icons.search_rounded`），内部
  `Icon(icon, 32, tint)`——字形数据化、尺寸/颜色部件内固定；10 处调用点
  （fav×3 / history×2 / toview×2 / download / msg_feed / detail 默认）。
- `GlassControlButton`：`IconData icon`，内部经 ContrastIcon 渲染；**当前无调用点**。
- `AppListItem`：`IconData icon`，M3 分支 `Icon(icon, tint)`、miuix 分支
  `Icon(icon, tint, 22)`；3 处调用点（about×2 / setting）。

## 二、设计修复 / 实现

| 部件 | 实现 |
|---|---|
| AppEmptyState | `icon` → `Widget?`（null 时内置搜索图标）；渲染改 `IconTheme(size 32 + tint)` 注入颜色——`iconColor`/错误色语义与既有无色图标调用点全部保持；AppErrorState 与 10 处调用点改传 `Icon(...)`（const 语境保持） |
| GlassControlButton | `icon` → `Widget`；内部改 `IconTheme(size/iconColor)` 包装（签名对齐；无调用点） |
| AppListItem | `icon` → `Widget`；M3 `leading` 与 miuix `startAction` 均改 `IconTheme(tint[/22])` 包装；3 处调用点改传 `Icon(...)` |

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **全库 0 issues** |
| `flutter test` | **129/129 通过**（两处测试调用点同步转换） |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证（待做）

- [ ] 1. 空状态页（收藏夹/历史/稍后再看/离线缓存/消息/评论区）：图标尺寸与
      颜色（含错误态 error 色）不变。
- [ ] 2. 设置页分类列表与关于页条目：图标着色（选中 primary / 未选中
      onSurfaceVariant）不变。

## 四、本轮总结

- 改动面：12 文件（+36/−27）。
- **批1 完成**：dyn_action_bar、video_action_row、AppEmptyState、
  GlassControlButton、AppListItem（AppIcons/AppIcon/ContrastIcon 等**原语**按
  设计不迁移）。
- 下一批（批2 页面）：whisper/view、setting_page、bangumi_detail_page、
  live_room_page、detail_page、player_panel（2 处）、profile_horizontal_section、
  user_agreement_page。

## 五、GitHub commit 提交记录

- 本轮提交：`87a5825a8105f48ec47645ca557bcecd157be6ca`（[feat](miuix): 阶段5b—图标 Widget 化批1（其二），12 文件 / +36 −27；按全局开发规定补记）。
- 本 `[docs]` 提交随后推送。
