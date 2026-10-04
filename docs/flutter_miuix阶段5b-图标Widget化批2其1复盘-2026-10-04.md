# flutter_miuix 阶段5b（图标 Widget 化 批2 其一）复盘 — 2026-10-03/04

> 五要素结构。范围：whisper `_EntryItem`、setting `_SettingEntry`、user_agreement
> `_Clause`、ProfileEmptyCard 四部件 + 其调用点。

## 一、分析根因 / 现状取证

- `_EntryItem`（消息页顶部圆形入口）：`IconData` + 内部 `Icon(color, 24)`；4 调用点。
- `_SettingEntry`（设置分类数据模型）：`IconData`；5 个条目 + 分类行调用点。
- `_Clause`（用户协议条款数据）：位置参数 `IconData`；3 条 const 列表 + 行渲染
  `Icon(20, primary)`。
- `ProfileEmptyCard`：`IconData` + 内部 `Icon(28, outline)`；10 调用点。
- 核对排除：detail_page / bangumi / live_room 三处 `final IconData icon;` 实为
  **方法内局部变量**（跟随状态计算），非部件签名，按设计不动。

## 二、设计修复 / 实现

| 部件 | 实现 |
|---|---|
| `_EntryItem` | `icon` → `Widget`；渲染 `IconTheme(color, size 24)` 注入（颜色语义保持） |
| `_SettingEntry` | `icon` → `Widget`；5 条目改 `Icon(...)`（const 保持）；分类行还原 `item.icon` |
| `_Clause` | `icon` → `Widget`；3 条款改 `Icon(...)`；行渲染 `IconTheme(20, primary)` |
| `ProfileEmptyCard` | `icon` → `Widget`；渲染 `IconTheme(28, outline)`；10 调用点改 `Icon(...)` |

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **全库 0 issues** |
| `flutter test` | **129/129 通过** |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证（待做）

- [ ] 1. 消息页四个圆形入口（回复/艾特/点赞/系统）：图标颜色与尺寸不变。
- [ ] 2. 设置页分类列表与关于页：选中/未选中图标着色不变。
- [ ] 3. 用户协议页三条条款图标（primary 20px）。
- [ ] 4. 我的页各处空卡（离线缓存/收藏/历史/稍后再看）：图标 28px outline 色。

## 四、本轮总结

- 改动面：5 文件（+39/−30）。
- **批2 剩余**：player_panel 控制条按钮（`_iconButton`/`_PlayerBarIconButton`，
  8 调用点）——需在 Widget 化同时保留 hover 提亮与字形阴影（设计：IconTheme
  注入动态色 + 评估 AppIcon 增加 shadows 支持），留待下一小批。
- 数据模型类（`_SettingEntry`/`_Clause`）随包转换为 Widget，const 列表保持。

## 五、GitHub commit 提交记录

- 本轮提交：`a4d878b4e3b0b24e4db439792594561d315c5ff0`（[feat](miuix): 阶段5b—图标 Widget 化批2（其一），5 文件 / +39 −30；按全局开发规定补记）。
- 本 `[docs]` 提交随后推送。
