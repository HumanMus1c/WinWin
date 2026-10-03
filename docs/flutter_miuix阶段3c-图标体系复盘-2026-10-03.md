# flutter_miuix 分阶段替换 · 阶段3c（图标体系）复盘 — 2026-10-03

> 五要素结构：分析根因 / 设计修复计划 / 修复效果验证 / 本轮总结 / 提交记录。
> 大指令：完全化替换。关联：阶段3 计划、3a/3b 复盘。

---

## 一、分析根因（背景与盘点）

1. **图标体系现状**：`app_icons.dart` 54 个语义 ×2 形态（`xxxOf(UiStyle)` / `xxx(context)` 共
   108 帮助函数），miuix 分支全部映射 `CupertinoIcons.*`；lib 内 104 个 context 调用点、
   测试 134 行断言锁定 Cupertino 字形。调用形态三类：
   a) `Icon(AppIcons.…, size/color)` 包裹 38 处；
   b) **IconData 直参**（传入自有部件的 `IconData icon:` 签名）≈50 处（14 个部件）；
   c) 三个收敛点：`AppBackButton` / `ActionIconTheme`（系统返回/关闭）/ `NavDestinationIcon`。
2. **对照 flutter_miuix**：`MiuixIcons` = basic 7 + extended 156×5 字重（`byName` 查询）
   + OS4 176；覆盖**通用 UI 语义**（设置/搜索/返回/更多/刷新/收藏/消息/箭头类等），
   **无**播放器与品牌专属语义（弹幕/字幕/章节/点赞点踩投币/全屏/画中画/铃声/人像等）。

## 二、设计修复计划

- **`AppIcon` 部件**（`app_icons.dart` 新增）：`AppIcon(IconData, {size, color, shadows})`；
  Miuix 风格且命中映射且无 shadows → `MiuixIcon(vector) `（等价 [Icon] 调用形态，机械替换）；
  其余（M3 / 未映射 / 带 shadows 的媒体叠加对比度场景）回退 `Icon`。
- **映射表 35 键**（Cupertino 字形 → Miuix 矢量）：
  chevron_back→chevronBackward、house(+fill)→home、clock(+fill)→recent、chat_bubble_2(+fill)→
  messages、star(+fill)→favorites/favoritesFill、share、reply、chevron_down/up→expandMore/Less、
  chevron_forward→chevronForward、search、clear、ellipsis→more、settings、refresh、
  arrow_down_to_line→download、delete、slider_horizontal_3→tune、checkmark→ok、
  play/play_fill→play、pause/pause_fill→pause、forward_fill→forward、lock(+fill)→lock、
  speaker_3_fill→volumeUp、speaker_slash_fill→volumeOff、pin_fill→pin、pin_slash_fill→unpin、
  slash_circle→blocklist。
- **未覆盖（保留 Cupertino，记录 ≠ 遗漏）**：动态(铃铛)、我的(人像)、点赞/点踩/投币、
  稍后再看、重播、快退、音量下、全屏/网页全屏/画中画、弹幕开关/发送/弹幕数/字幕/章节、
  免打扰(铃铛)、单选框、告警、播放数、日历、时长(time 语义已由 clock→recent 覆盖) 等。
- **转换范围**：38 处 `Icon(AppIcons.…)` 全部升级 + 三个收敛点；**IconData 直参 ≈50 处**
  （`icon:` 签名 `IconData`，需部件签名 Widget 化）列为 3c 后续小步（逐步做，逐部件验证）。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info 与基线一致） |
| `flutter test` | **116/116 通过**（新增 2 例：映射表初始化安全——byName 全非空；AppIcon miuix/M3/未映射三态；app_icons_test 两个组件断言改为 Miuix 矢量） |
| 双构建 | `windows --debug` ✅ / `--release` ✅，均 0 警告 0 错误 |

### 实机验证（待做 — 用户操作）

- [ ] 1. Miuix 风格下导航（底栏/侧栏）图标为 Miuix 矢量（首页/历史/消息）；动态/我的仍为 Cupertino（无对应）。
- [ ] 2. 全局返回按钮与系统关闭按钮为 Miuix 矢量；视频页叠加返回按钮阴影保持（shadows 回退路径）。
- [ ] 3. 设置/搜索/更多/收藏/刷新/删除/播放/暂停/音量等按钮为 Miuix 矢量且着色正常。
- [ ] 4. 播放器深链图标（弹幕/字幕/全屏等）保持原 Cupertino 字形（预期）。
- [ ] 5. 切换回 Material 3：全部恢复 M3 字形（零变化）。

## 四、本轮总结

- **改动面**：17 文件（+172/−50）：`app_icons.dart`（AppIcon+映射表）、`app_theme.dart`、
  `frosted_bottom_bar.dart`、`select_dialog.dart`、`session_more_menu_button.dart`、
  弹幕/字幕面板、`search_page.dart`、`member_space_page.dart`、`player_panel.dart`、
  `detail_page.dart`、`bangumi_player_page.dart`、`bangumi_detail_page.dart`、
  `dynamics/detail_page.dart`、`live_room_page.dart` + 2 测试。
- **行为预期**：Miuix 风格下通用语义图标升级为 Miuix 矢量；M3 零变化；无对应语义保留原字形。
- **遗留**：IconData 直参 ≈50 处 Widget 化（后续小步）；3d 刷新与玻璃探测。

## 五、GitHub commit 提交记录

- 3c 提交：`fec260385edba52911fc30348146a34a3e437f6c`（[feat](miuix): 阶段3c 图标体系接入 Miuix 矢量图标，17 文件 / +172 −50）。
- 本 `[docs]` 提交随同推送 `origin/main`（状态事后补记）。
- 快照 / 回滚基准：`debdedbd488ca514ea64b97f8d7d60a2a9cdebae`（本轮统一基准）。
