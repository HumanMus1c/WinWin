# flutter_miuix 复测反馈2轮（Toast 宿主 / 菜单弹层壳）复盘 — 2026-10-03

> 五要素结构。触发：复测 3 条（Toast 动画与观感 / 经验条确认 / 弹层回弹与半透明统一）。
> 并行记录：GitHub 5xx 故障期间 4c-1（`c299142`+`7f46573`）本地暂存，随本轮一并推送成功。

## 一、分析根因

1. **Toast 观感**：
   - "横向分展渐显渐隐"来自 `material_ui` 的 `SnackBar` 进场过渡（新版 M3 分展），
     无法在 SnackBar 层面覆写 → 需脱离 SnackBar 自绘；
   - 4a 的 miuix 卡沿用 MD3 反色深卡 + 无半透明 → 观感与原版无差（复测误判"未替换"）。
2. **弹层回弹（flutter_miuix 菜单）**：源码取证——窗口下拉的展开/收起用
   `MiuixListPopupDefaults.fractionAnimationSpec`（dampingRatio 0.82）弹簧，且：
   该常量为 `static const`（无运行时覆盖）、facade 无弹簧/时长参数、该路径不读取
   `MediaQuery.disableAnimations`；面板底色同样不可定制（无 surfaceBuilder 透出）。
   ⇒ "禁用回弹 + 统一半透明"在现有上游组件上不可达，需自研弹层壳。
3. **经验条**：用户确认符合要求（本轮无改动）。

## 二、设计修复 / 实现

| 项 | 实现 |
|---|---|
| Toast 通道 | miuix 分支改由 **MiuixToastHost**（挂 `MaterialApp.builder` 根部）渲染；`showToast/showAppSnackBar` 经全局 `miuixToastRequest` 直达宿主——完全去 context 依赖 |
| Toast 动画 | 整卡 **上浮渐显**（+24px → 0，220ms）/**上浮渐隐**（0 → −24px，180ms，easeOutCubic）；`leaving` 方向感知 |
| Toast 材质 | **反色**（亮色主题暗卡 `inverseSurface`、暗色主题亮卡）× `kMiuixSurfaceAlpha`（0.88）半透明；squircle 16 + 阴影 |
| Toast 机制 | 宽度自适应（按实际文本样式测量）/ 点击关闭 / 单条最新优先（新请求重上浮）；`StackFit.expand` 保证命中区铺满 |
| 统一不透明度 | **`kMiuixSurfaceAlpha = 0.88`**（miuix_theme_bridge.dart，Toast/弹层共用集中调整点） |
| 菜单弹层壳 | 新增 **`MiuixPopupMenu`**（common/widgets）：fade + 轻微上浮（180/140ms，无回弹）；面板 `surfaceContainer × kMiuixSurfaceAlpha`；复用官方 `MiuixDropdownEntriesPopupContent`（选中态/分组分隔线原生）；外点/Esc/单组选择收起、多组保持、下方不足自动翻转 |
| 接入点 | 会话更多菜单 + 播放器画质/音轨/倍速（4 处；M3 分支逐字保留） |

## 三、修复效果验证

| 项 | 结果 |
|---|---|
| `dart analyze` | **0 错误 0 警告**（6 条既有 info） |
| `flutter test` | **128/128 通过**（Toast 两条改宿主机制断言"不再有 SnackBar"；新增 MiuixPopupMenu 用例） |
| 双构建 | `windows --debug` ✅ / `--release` ✅，0 警告 0 错误 |

### 实机验证（待做）

- [ ] 1. Toast：任意提示 → 整卡上浮渐显、上浮渐隐；亮色主题=暗卡、暗色主题=亮卡；
      卡面半透明；点击关闭。
- [ ] 2. 会话更多菜单 / 播放器画质·音轨·倍速：展开无强烈回弹（平稳淡入上浮）、
      面板半透明（与 Toast 同一不透明度常量）。
- [ ] 3. 音轨菜单：多组选择后保持展开；外点/Esc 收起；下方空间不足时向上展开。
- [ ] 4. 切回 M3 风格：Toast 仍为 SnackBar 通道、菜单仍为原深色 MenuAnchor（冻结路径）。

## 四、本轮总结

- 改动面：7 文件（+518/−136）。
- 决策记录：① 上游弹簧/面板色不可定制（取证见上）→ 用户要求优先，自研弹层壳
  （条目渲染仍用官方组件，非造轮子）；② "统一不透明度"以单一常量集中管理，
  后续调值只改 `kMiuixSurfaceAlpha`。
- 已知差异：自研壳无上游的"弹性回弹"手感（本意即禁用）；菜单定位为右缘对齐 +
  下方 6px（等价 MiuixPopupAlign.end）。
- 队列：4c-2 视频卡片右键/三点菜单；live_room 三处菜单；4f 图标直参 Widget 化。

## 五、GitHub commit 提交记录

- 本轮提交：`77d96e1c35733b72941a57e90fb7cc4783c0fa52`（[feat](miuix): 复测反馈2轮—Toast 自绘宿主（上浮/反色/半透明）＋菜单弹层壳（无回弹+统一半透明），7 文件 / +518 −136；按全局开发规定补记）。
- 故障补推：`c299142`（4c-1 播放器菜单）+ `7f46573`（4c-1 复盘）——GitHub 502/504 期间本地暂存，随本轮推送一并到达 `origin/main`。
- 本 `[docs]` 提交随后推送。
