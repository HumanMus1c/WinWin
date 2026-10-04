# flutter_miuix 阶段5d-L1 批次1（菜单 M3 冻结分支移除）复盘 — 2026-10-04

> 五要素结构。前置决策（用户）：OS4 玻璃**暂不启用**（加载能力已证实
> loaded=6 error=none，保持关闭）；启动 L1（逐文件脱离 M3）。

## 一、分析根因 / 现状取证

- 退役纪律：控件已具备 flutter_miuix 分支并经多轮实机验证 → 本轮"脱离"：
  删除 M3 冻结分支，使弹层壳成为唯一实现。
- 范围（批次1）：会话「更多」、播放器画质/音轨/倍速、live_room 三个菜单
  （共 7 处 if/else 双分支 + 深色 MenuAnchor 老实现）。

## 二、设计修复 / 实现

| 位置 | 实现 |
|---|---|
| 会话更多菜单 | 删 if/else 门控与 M3 MenuAnchor；清理 InheritedUiStyle/UiStyle 导入 |
| 播放器×3 | 删三处 if/else 与 M3 深色 MenuAnchor；删 `_darkMenuStyle`/`_darkMenuItemStyle`；清理 AppLogger/ InheritedUiStyle/UiStyle 导入 |
| live_room×3 | 删三处 if/else（含嵌套 `if (_streamLines.isNotEmpty)` 门槛）与 M3 MenuAnchor；删 `_menuStyle`/`_menuItemStyle`；清理主题态导入 |

- M3 冻结分支删除后**观感与行为不变**（miuix 分支本就为唯一实际使用路径）。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **全库 0 issues** |
| `flutter test` | **130/130 通过** |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |
| 代码量 | **净 −574 行**（3 文件） |

### 实机验证（待做）

- [ ] 1. 会话「更多」、播放器三菜单、直播间三菜单：功能与观感与删除前一致。

## 四、本轮总结

- L1 批次1 完成；**余量**：用户空间/登录/视频卡片右键菜单（M3 分支）、
  毛玻璃底栏/SimpleScaffold、面板类（弹幕样式/表情/字体弹窗的残留门控）、
  **AppComponents（最大头，约 10 个组件的双分支）**——按批次继续。
- 决策记录：玻璃保持关闭（探针保留，便于后续启用评估）。

## 五、GitHub commit 提交记录

- 本轮提交：`bf0401304e3e4ae7d7250b303837b1c0360409bd`（[refactor](miuix): 阶段5d-L1 批次1，3 文件 / +14 −574；按全局开发规定补记）。
- 本 `[docs]` 提交随后推送。
