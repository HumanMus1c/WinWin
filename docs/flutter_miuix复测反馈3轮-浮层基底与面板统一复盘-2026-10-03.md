# flutter_miuix 复测反馈3轮（浮层文本基底 / 半透明行底 / 面板统一）复盘 — 2026-10-03

> 五要素结构。触发：复测 3 条（浮层双下划线+行底遮挡半透明+对角线展开；Toast 同划线；会话菜单同划线+统一面板）。

## 一、分析根因

1. **文本"黄绿双下划线"**（弹层条目 / Toast 文本）：自绘浮层（Overlay 与根部宿主）
   不在 Material 子树内，`Text` 继承的是 `WidgetsApp` 的默认"错误文本样式"
   （双下划线 + 亮色）；`MiuixDropdownImpl` 等按内容色 **merge** 文本样式时保留了
   decoration → 出现"彩色文字 + 双下划线"。上游弹层组件内部包了透明 `Material`
   （见其 `_MiuixHostedEntry` 注释），自绘壳漏了这一步。
2. **弹层半透明"被行底遮挡"**：行配色默认 `containerColor` 为不透明，逐行盖住
   面板的 88% 半透明底 → 观感不透明。
3. **弹幕样式面板**与**表情面板**：两者视觉语言相同但各写一份（12 圆角 / blur16 /
   0xD9 灰底 / 1px 描边 / 标题行），且**弹幕样式面板没有入场动画**（表情面板已带
   "贴按钮对角锚点缩放"的对角线展开）。

## 二、设计修复 / 实现

| 项 | 实现 |
|---|---|
| 文本基底 | `MiuixPopupMenu` 弹层与 `_MiuixToastCard` 统一包 `DefaultTextStyle`（`bodyMedium` + `decoration: none`），一次性消除双划线（M3 路径不受影响） |
| 半透明行底 | 弹层行配色改为 `containerColor: transparent` + `selectedContainerColor: α0.60`（其余取 `MiuixDropdownDefaults.dropdownColors`）→ 面板半透明透出 |
| 对角线展开 | 弹层展开由位移改为**以贴触发器一角为原点缩放**（下展→右上；上翻→右下；`easeOutCubic` 180ms） |
| 面板统一 | 新增共用 **`MiuixOverlayPanel`**（`common/widgets/miuix_overlay_panel.dart`）：12 圆角 / blur16 / 半透明底 `kMiuixSurfaceAlpha` / 1px 描边 / 标题行（图标+标题+分隔线）/ padding 16；**表情面板**（`emote_picker`）与**弹幕样式面板**（`send_danmaku_panel` inline 浮层）改为复用该壳 |
| 补全过渡 | 弹幕样式面板补上表情面板同款**对角线展开**入场动画（`SingleTickerProviderStateMixin` + 180ms `easeOutCubic`，锚点右下角） |

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **128/128 通过** |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证（待做）

- [ ] 1. 会话三点菜单 / 播放器画质·音轨·倍速：无绿色双下划线；面板半透明透出；
      展开为对角线缩放（无回弹）。
- [ ] 2. Toast：文本无下划线；上浮渐显/渐隐；反色 + 半透明。
- [ ] 3. 播放器内联输入条「弹幕样式」面板：与表情面板观感一致（圆角/毛玻璃/
      标题行/间距），且带对角线展开动画；点击外部/Esc 关闭不变。
- [ ] 4. 评论输入栏 / 直播条「表情」面板：样式与之前一致（现走共用壳）。

## 四、本轮总结

- 改动面：5 文件（+248/−216，净减重复实现）。
- 决策记录：① "统一面板"以共用壳 `MiuixOverlayPanel` 落地（样式单一来源，
  后续调整只改一处）；② 半透明统一仍走 `kMiuixSurfaceAlpha`（面板 0xD9→0.88
  统一值）；③ 对角线展开仅入场（与表情面板现状一致），关闭保持即时。
- 队列：4c-2 视频卡片右键/三点菜单（`showVideoContextMenu`）；live_room 三菜单；
  4f 图标 IconData 直参 Widget 化。

## 五、GitHub commit 提交记录

- 本轮提交：`80f9b513f2eeb756f10d9148f4a454ea008a418f`（[fix](miuix): 浮层文本基底/半透明行底/对角线展开；弹幕样式与表情面板统一共用壳，5 文件 / +248 −216；按全局开发规定补记）。
- 本 `[docs]` 提交随后推送。
