# flutter_miuix 阶段4c-2（右键菜单与 live_room 菜单）复盘 — 2026-10-03

> 五要素结构。范围：视频卡片右键/三点菜单（复用共用壳）+ live_room 三菜单接入。

## 一、分析根因 / 现状取证

- **视频卡片右键/三点菜单**（`showVideoContextMenu`）：MD3 `showMenu` + `PopupMenuItem`
  （图标 + 文本），非 Miuix 观感；动作列表 `VideoCustomAction.icon` 本就是 Widget ✓。
- **live_room 三菜单**：`MenuAnchor + MenuItemButton`（深色主题，单选列表形态），
  与播放器三菜单同族，可同口径接入 `MiuixPopupMenu`。

## 二、设计修复 / 实现

| 项 | 实现 |
|---|---|
| 右键菜单（miuix 分支） | 自绘浮层：`MiuixOverlayPanel`（标题「更多操作」）+ 公开的 `MiuixPopupMenuRow`（hover/按压/130ms 后关闭）+ 对角线展开（topLeft 锚点）；点击外部/Esc 收起（EscapeLayerRegistry）；**保持 await→动作语义**（关闭后回调所选动作）；M3 分支保留 `showMenu`（冻结） |
| 行组件公开化 | `MiuixPopupMenuRow` 公开 + 新增 `leading` 图标位（右键菜单条目=图标+文本；菜单壳内部不传 leading） |
| live_room 三菜单 | miuix 分支 → `MiuixPopupMenu`：画质清晰度 / 推流线路·CDN / 画面比例（标题取既有 Tooltip）；`itemTextStyle` 12 对齐控制条；触发器 HoverContainer（无 onTap，点击由弹层壳接管）；M3 分支原样保留 |

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **128/128 通过** |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证（待做）

- [ ] 1. 视频卡片右键 / 三点菜单：共用壳观感（半透明 + 标题「更多操作」）、
      hover/按压/延迟关闭、对角展开；选择后动作正确执行（各条目逐一验证）。
- [ ] 2. 直播间控制条：画质清晰度 / 推流线路 / 画面比例三个菜单（标题、条目
      字号、选中态、切换生效）。
- [ ] 3. 点击外部/Esc 收起；切回 M3 风格两处均无回归（原 MenuAnchor/showMenu）。

## 四、本轮总结

- 改动面：3 文件（+449/−107）。
- 决策记录：右键菜单直接复用「共用壳 + 行组件」而非重建一套——本轮之后所有
  自绘浮层均为同一材质/交互来源。
- 队列：**4f 图标 IconData 直参 Widget 化**（14 部件 / ≈50 调用点，逐部件小步，
  下一批开始）；4g 玻璃启用评估（探测日志已积累）。

## 五、GitHub commit 提交记录

- 本轮提交：`54fa1a46b5751111ba10239a07d6fbacc83786de`（[feat](miuix): 阶段4c-2—视频卡片右键菜单复用共用壳；live_room 三菜单接入弹层壳，3 文件 / +449 −107；按全局开发规定补记）。
- 本 `[docs]` 提交随后推送。
