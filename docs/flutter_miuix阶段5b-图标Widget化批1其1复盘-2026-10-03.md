# flutter_miuix 阶段5b（图标 Widget 化 批1 其一）复盘 — 2026-10-03

> 五要素结构。范围：`dyn_action_bar` 与 `video_action_row` 的图标参数 Widget 化。
> 前置纪律（用户指令，本轮起强制）：只有 MD3 的控件**先补 flutter_miuix 分支 →
> 测试无异常 → 再脱离 MD3**；全项目不再引用 MD3 后才统一移除 MD3 库与样式。

## 一、分析根因 / 现状取证

- `dyn_action_bar._buildButton`：参数 `IconData icon`，内部
  `Icon(icon, size: widget.iconSize, color: color)` —— 图标字形"按风格分发"
  被数据化，尺寸/颜色部件内写死；3 个调用点（转发/评论/点赞）。
- `video_action_row._ActionButton`：参数 `IconData icon`，内部
  `Icon(icon, size: 24, color: 激活色)`；6 个调用点（点赞/投币/收藏/点踩/分享/稍后看）。

## 二、设计修复 / 实现

- 两部件签名 `IconData icon` → `Widget icon`；内部直接渲染传入组件（进度环
  包裹逻辑不变）。
- 调用点改传 `AppIcon(AppIcons.xxx(context), size: …, color: …)`：尺寸沿用原
  部件值（iconSize / 24）；颜色沿用原状态色（激活 biliPink、非激活
  onSurfaceVariant 等，与内部文本色表达式一致）。
- `AppIcons.*Of` API 与测试契约不动。

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **全库 0 issues**（既有 6 条 info 亦已消失） |
| `flutter test` | **129/129 通过** |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证（待做）

- [ ] 1. 动态卡片操作栏（转发/评论/点赞）：图标与计数、激活配色、点击行为正常。
- [ ] 2. 视频页互动行（点赞/投币/收藏/点踩/分享/稍后看）：图标尺寸/激活色不变；
      长按三连进度环正常。

## 四、本轮总结

- 改动面：2 文件（+59/−13）。
- 批1 进度：已完成 dyn_action_bar、video_action_row；待办 `app_empty_state`、
  `glass_contrast_widgets`（2 处）、`app_components`（1 处），随后进入批2 页面。

## 五、GitHub commit 提交记录

- 本轮提交：`41227522b46d76f0a6a0068dc6b2f2e936d4e1bf`（[feat](miuix): 阶段5b—图标 Widget 化批1（其一），2 文件 / +59 −13；按全局开发规定补记）。
- 本 `[docs]` 提交随后推送。
