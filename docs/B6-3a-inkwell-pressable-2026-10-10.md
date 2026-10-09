# B6-3a 复盘：InkWell 全量 Miuix 化（MiuixPressable）— 2026-10-10

## 1. 现象描述

B6-2（图标批）收官后，`lib` 内仍有 71 处 Material `InkWell`（29 文件）：
其水波/高亮绘制依赖最近的 `Material` 祖先（B5 回归时曾因骨架缺 Material 整页
红屏，收口-3 才补齐），是 B7 摘除 `material_ui` 依赖的下一批清退对象。
替换目标为 flutter_miuix 原生的 `MiuixPressable`（扁平按压 + 半透明 overlay
弹簧动画 + squircle 圆角，包内对应 Kotlin `MiuixIndication`）。
项目内已有先例：`medal_widget.dart`、`app_components.dart` 的按压反馈。

## 2. 根因

`InkWell` 属 material_ui 控件家族；Miuix 口径的按压反馈为 **无涟漪、
按压/悬停 overlay 渐变 + 稳定下沉反馈**，两者机制不同。迁移不是风格微调，
而是依赖收敛的必要路径（B7 后 `InkWell` 符号不可用）。

## 3. 修复方案（零布局变化；按压反馈换为 Miuix 口径）

- **65 处标准站点（22 文件）机械转换**：`InkWell(` → `MiuixPressable(`，
  顶层参数 `onTap:` → `onPressed:`；`borderRadius` / `onLongPress` / `child`
  原样保留。转换器为括号平衡 + 字符串/注释感知脚本，嵌套参数零误伤；
  各文件自动补 `import 'package:flutter_miuix/miuix.dart' show MiuixPressable;`
  （已存在 `show` 列表则合并）。
- **6 处含右键菜单站点**（`demo_mask`×2、`video_card_h/v`、`fav_page`、
  `toview_page`）：`onSecondaryTapDown/Up` 在 `MiuixPressable` 无对应参数，
  采用外提结构——外层 `GestureDetector(onSecondaryTapDown/Up, child: ...)`
  专收右键手势，内层 `MiuixPressable` 承担主键按压与长按；
  主键 Tap 手势与右键手势天然分属两个识别器，互不抢占。
- 修脚本两处边界产物：6 处 `),,` 双逗号（尾随逗号段切分边界）；
  4 文件补 `show MiuixPressable` 导入。

## 4. 验证与回滚

- 快照：`d69d26d8`（`refs/snapshots/latest`，本批改前全量工作区）。
- `dart analyze` 零问题（首轮 11 error：6×`),,` + 5×缺导入，全部按上消除）。
- `flutter test` **164/164 全绿**。
- `flutter build windows --debug` / `--release` 双通过、0 警告
  （kernel_blob 01:19:53 / app.so 01:21:49），编译前已清残留 `winwin.exe`，
  构建后按约定自启 Release（PID 44336）。
- 残留复核：`InkWell` 全库 0 处（仅注释 2 行）；闸门指标维持 **133**。
- 提交推送：`（本批回填）`（代码+复盘+进度表同批）。

## 5. 遗留与踩坑

- 遗留：B6-3 另一半 `IconButton`（58 处/30 文件）→ B6-3b；
  其中 `IconButton.filled/filledTonal/styleFrom/padding/constraints/color`
  站点约 14 处需逐点映射（背景色、命中区尺寸、颜色外提）。
- 踩坑：① 有括号平衡扫描时索引必须锚定 `(`（`m + 'InkWell'.length`），
  差一位会把「第一个配对括号」当成调用结束，产出截断结构；
  ② Dart 尾随逗号风格会让顶层参数切分的**最后一片是纯空白**，
  若直接当"子件"补逗号会产出 `),,`；③ `onSecondaryTap*` 站点不可直接替换，
  `GestureDetector` 外提是零语义损失的等效结构；④ 后台运行的
  `flutter build` 日志可能捕获为空——验证以 `data\app.so` /
  `data\flutter_assets\kernel_blob.bin` 时间戳与自启进程为准。

## 6. 总结

B6-3a 完成：71 处 `InkWell` 全量 Miuix 化（65 机械 + 6 右键外提），
26 文件 +183/−144；按压反馈统一为 Miuix 口径，Material 祖先依赖进一步降低；
双分支构建与 164 项测试全绿；下一批 B6-3b（IconButton）。

## 7. 测试验证指导（本轮产物，PID 44336）

- **视频卡片**（首页/搜索/动态/收藏/稍后再看等）：单击进入播放正常；
  **右键**弹出视频菜单正常；长按（触屏）同样弹菜单；按压出现 Miuix 扁平
  overlay（原水波涟漪消失属预期迁移口径）。
- **动态/评论/消息**：动态卡片、表情面板、动态动作栏、会话行点击反馈正常。
- **成员空间/个人页**：横向卡片、合集卡点击正常。
- **画中画相关**：画廊左箭头、演示模式卡片点击正常。
- **预期结果**：布局零变化（无尺寸跳动）；点击/长按/右键功能齐全；
  如遇某处点击无响应或圆角/水波异常即为回退项。
- **日志**：复测后核对 `D:\Documents\.winwin_logs.json` 与
  `D:\Documents\logs\runtime.log` 有无新增条目。
