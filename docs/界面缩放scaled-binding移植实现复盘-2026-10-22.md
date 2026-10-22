# 界面缩放 · scaled-binding 方案移植实现复盘

> 日期：2026-10-22　｜　作者：小通（@office，deepseek-v4.1-flash）　｜　触发：CVO 指令「按上游 scaled-binding 方案移植实现『界面缩放』」
> 关联文档：`docs/上游PiliPlus界面缩放实现调查-2026-10-22.md`（方案来源）、`docs/界面缩放方案A失效与回退复盘-2026-10-22.md`（被本方案取代）、`docs/设置接线-批次2-外观热生效复盘-2026-10-22.md`
> 上游参考：PiliPlus `lib/common/widgets/scale_app.dart` + `lib/main.dart:_builder`

---

## 一、现象

「界面缩放」设置项自批次 2 引入方案 A（`Transform.scale` 整树绘制缩放）后实机失效：右键/更多菜单弹层严重偏离触发原点、窗口控件漂出窗口、页面底部入口不可见。`03c6401` 已止血回退（移除 Transform、隐藏假开关），使 UI 恢复可用，但「界面缩放」功能处于**停用**状态。

CVO 要求：按上游 PiliPlus 的 **scaled-binding** 方案**重新实现**该功能（而非此前的整树 `Transform`）。

## 二、问题根因

（沿用调查文档结论，此处只作定因闭环）

- 方案 A 的 `Transform.scale` **只改「绘制」、改不动「坐标空间」**；而 Miuix 弹层以 `box.localToGlobal`（含缩放的根坐标）当作 Overlay 的**窗口空间**坐标定位（见 MiuixPopupPositionProvider 注释），自绘标题栏亦按窗口空间布局 ⇒ 两者相差 `uiScale` 倍 ⇒ 弹层偏移、控件漂移。
- 上游 PiliPlus 从**渲染层**根治：`ScaledWidgetsFlutterBinding` 覆写 `RenderView.devicePixelRatio = 原 dpr × scale`，逻辑尺寸随之变化，整棵树（含 `Overlay`/弹层/自绘控件）**共享同一坐标空间**；并**同步指针数据转换**（`onPointerDataPacket` 用缩放后 DPR）保证命中测试一致；再于 `App.builder` 内以**同比例**同步 `MediaQuery`（`size/scale` 且 `dpr*scale`）使观感空间与渲染空间对齐。

## 三、方案（实现）

**移植上游三层结构，零第三方依赖（去 `scaled_app`，自实现核心）：**

1. **新增 Binding**：`lib/core/shell/scaled_widgets_flutter_binding.dart`
   - 继承 `WidgetsFlutterBinding`，覆写 `createViewConfigurationFor(RenderView)`：`devicePixelRatioScaled = view.devicePixelRatio × _scaleFactor`，`logicalConstraints = physicalConstraints / devicePixelRatioScaled`；
   - 覆写 `initInstances()`：接管 `platformDispatcher.onPointerDataPacket`，经 `PointerEventConverter.expand(packet.data, _devicePixelRatioForView)` 用缩放后 DPR 转换指针（命中测试/手势坐标一致）；
   - `set scaleFactor(...)` → `handleMetricsChanged()`（**热生效**）；补 `unlocked()`/`cancelPointer()`/指针队列以对齐 `GestureBinding`；提供 `ensureInitialized({scaleFactor})` 与 `maybeInstance` 安全取用。

2. **启动接线**：`lib/main.dart`
   - `WidgetsFlutterBinding.ensureInitialized()` → `ScaledWidgetsFlutterBinding.ensureInitialized()`（必须早于任何 Binding 使用与 `runApp`）。

3. **MediaQuery 同比例同步**：`lib/core/shell/app_shell.dart`
   - 移除失效注释；`uiScale != 1.0` 时 `MediaQuery.copyWith`：`size / uiScale`、`padding / uiScale`、`viewInsets / uiScale`、`viewPadding / uiScale`、`devicePixelRatio * uiScale`，并保留 `textScaler`；`uiScale == 1.0` 时仅施加 `textScaler`（零开销短路）。

4. **热生效单点**：`lib/pages/setting/appearance_notifier.dart`
   - `setUiScale(value)` **同时**更新 `uiScale` 通知器（驱动 AppShell 重算 MediaQuery）与 `ScaledWidgetsFlutterBinding.scaleFactor`（驱动渲染层 DPR）；
   - `refresh()` 改为经 `setUiScale` 恢复（bootstrap 后即应用持久化值）。

5. **恢复设置项**：`lib/pages/setting/models/style_settings.dart`
   - 取消注释并重写「界面缩放」项：范围**对齐上游 0.5–2.0**（`divisions: 30`，`decimals: 2`），`onTap` 写存储 + `AppearanceNotifier.setUiScale` + 提示「已生效」。

## 四、验证

- `dart analyze lib` → **No issues found**（0 error / 0 warning）。
- `flutter build windows --debug` → **√ Built build\windows\x64\runner\Debug\winwin.exe**。
- `flutter build windows --release` → **√ Built build\windows\x64\runner\Release\winwin.exe**。
- 产物新鲜度对账：`Release/data/app.so` 时间戳 `2026-10-22 10:19:41`（本轮 Dart 产物已更新，非旧 exe 假象）。
- 已启动 Release 产物（PID 见下），供 CVO 实机验证。
- **实机 UI 验证（待 CVO 复跑）**：
  1. 设置 → 外观：拖「界面缩放」至 0.7x / 1.3x / 2.0x → 界面整体**即时**缩放（不重启）；
  2. **弹层锚定**：右键视频卡片「更多操作」、消息中心「更多选项」→ 弹层仍锚定右键/触发位置、就近对角展开、不越界（**方案 A 的关键失效点，本方案必须归位**）；
  3. **窗口控件**：自绘标题栏按钮位置正常、不漂出窗口；
  4. **底部入口**：「我的」页面滚动到底，「切换账户 / 设置」入口可见可点；
  5. **命中精度**：缩放后点击按钮/列表滚动/输入框光标定位准确（指针坐标与渲染一致）；
  6. 设为 1.0x 回退 → 一切如初。

## 五、提交与回滚

- 代码提交：见本轮 commit（hash 回填至本节末尾，**按全局开发规定补记**）。
- 快照基准：本次开工前工作区 clean，`refs/snapshots/latest` 无新快照（无未跟踪改动可存）；回滚锚点为父提交 `53a1260`。
- 回滚命令：`git revert <本轮提交>`（恢复「界面缩放」为停用态）或 `git reset --hard 53a1260`（回到本轮实现前）。
- 推送：会话末尾统一 `git push origin main`。

## 六、遗留与踩坑

1. **与方案 A 的架构差异**：本方案**不再**用 `Transform`/`MediaQuery.size` 单点缩放，改为「Binding 改真实 DPR + MediaQuery 同比例同步」——两者必须**同源同比例**（`size/scale` 且 `dpr*scale`），只更其一会复现方案 A 的坐标错配。
2. **SDK 版本耦合**：`createViewConfigurationFor` / `PointerEventConverter.expand` / `ViewConfiguration` 签名随 Flutter 演进，升级 SDK 需复核（上游即依此适配）。当前 SDK 满足。
3. **桌面 padding 语义**：Windows 下 `padding/viewPadding` 均为 0，除 `uiScale` 后仍为 0，无副作用；上游的 `tmpPadding`（gallery 全屏预览用）WinWin 未移植，不涉及。
4. **极端值待实机确认**：0.5x / 2.0x 下的布局溢出、滚动范围、输入法候选框定位需 CVO 实机核对（回归方案 A 遗留项 4）。
5. **`window_manager` 无冲突**：缩放只改 Flutter 内部 DPR，不动物理窗口尺寸，与全屏/窗口尺寸逻辑正交。
6. **沙箱编译环境**：`flutter build windows` 因宿主 shell 缺 `ProgramFiles(x86)` 报环境变量缺失（非代码问题），补齐 `env` 即通过（沿用既有解法）。

## 七、总结

「界面缩放」已按 CVO 指令**移植上游 scaled-binding 方案**并恢复启用：在 **Binding 层**把渲染 `devicePixelRatio × uiScale`（真实缩放整棵树，含 `Overlay`/Miuix 弹层/自绘标题栏），**同步指针数据转换**保证命中一致，并在 `AppShell` 内**同比例同步 `MediaQuery`**——从坐标空间层面根治了方案 A「只缩放绘制、弹层与窗口控件漂移」的结构性缺陷，且天然支持**热生效**。零第三方依赖（自实现核心），`dart analyze` 0 issue、Debug/Release 双编译通过、已启动产物待 CVO 实机复跑（重点：弹层锚定 + 命中精度）。方案 A 复盘所给「需改 Windows runner 做原生 DPI 缩放」的结论**已由本方案在 Flutter Binding 层等效实现**，runner 层无需改动。