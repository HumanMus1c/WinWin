# flutter_miuix 阶段4c-1（播放器深色菜单）复盘 — 2026-10-03

> 五要素结构。范围：播放器控制条三处菜单（画质 / 音轨 / 倍速）Miuix 化。

## 一、分析根因 / 现状取证

- 三处菜单均为 `MenuAnchor + MenuItemButton`（自绘深色 `_darkMenuStyle`，
  0xE61A1A1A 底 + white12 描边），选中态靠手写着色（biliBlue 加粗 / 勾选图标）。
- 目标组件选型（源码核对）：
  - `MiuixWindowIconDropdownMenu.entries`：触发器包裹式（`child:`）+ 原生揭示
    动效 + `MiuixDropdownItem.selected` 原生选中态 + 多 `MiuixDropdownEntry`
    分组分隔线——与"触发器是控制条小 chip"的形态吻合；
  - `MiuixWindowListPopup` 为声明式（show/anchorBounds）API，不适合本形态，
    留作右键菜单（位置锚点）改造用（下一批）。
- 触发器注意点：`HoverContainer` 内层 GestureDetector 会抢占点按——miuix 分支
  必须去 `onTap`（组件自带展开手势），仅保留 hover 视觉。

## 二、设计修复 / 实现

| 菜单 | miuix 分支实现 |
|---|---|
| 画质 | 单条目组：`MiuixDropdownItem(text, selected: i==current, onClick: switchQuality)` |
| 音轨 | 组1=音轨列表（selected=active）；组2=disabled 组标题「音频响度均衡」；组3=三条响度均衡（selected=currentNorm，onClick 内 `setAudioNormalize` + `setState`） |
| 倍速 | 单条目组：`'${v}x'`，selected == speed，onClick setPlaybackSpeed |

- 三个触发器结构（Tooltip>HoverContainer>ContrastText / codec+均衡角标）逐字保留，
  仅去 onTap；`backgroundColor: transparent + minHeight/minWidth: 0 + cornerRadius: 6`
  保持控制条紧凑形态；探测日志迁移 `onExpandedChange`。
- **M3 分支逐字保留**（深色 MenuAnchor，按冻结策略不动）。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info；player_panel 单文件 0 issues） |
| `flutter test` | **127/127 通过** |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证（待做）

- [ ] 1. 播放器控制条：点「画质/倍速」展开 Miuix 下拉——原生动效、当前项选中态。
- [ ] 2. 点「音轨（如 AAC）」：音轨组与响度均衡分组分隔线；三条均衡项切换生效、
      角标「均衡」随开关出现。
- [ ] 3. 菜单收起（点击项/外侧/Esc）无异常；切回 M3 风格路径无回归（原深色菜单）。

## 四、本轮总结

- 改动面：1 文件（player_panel.dart，+203）；M3 路径零改动。
- 已知差异：菜单配色跟随应用主题（Miuix 规范：浅色模式下菜单为浅色，含在深色
  播放器上）——若偏好"始终深色"，后续可经 `dropdownColors` 强制深色（待实机反馈）。
- 队列：视频卡片右键/三点菜单（MiuixWindowListPopup 声明式 API，需 Overlay
  生命周期封装以保持 `showVideoContextMenu` 的 await 语义）；live_room 三处菜单
  （同形态，机械转换）；4f 图标直参 Widget 化。

## 五、GitHub commit 提交记录

- 4c-1 提交：`c299142d29a42920044d1bfd15652cda814acfcb`（[feat](miuix): 阶段4c-1 播放器三处深色菜单 Miuix 化（画质/音轨/倍速），1 文件 / +203；按全局开发规定补记）。
- 本 `[docs]` 提交随同推送 `origin/main`。
