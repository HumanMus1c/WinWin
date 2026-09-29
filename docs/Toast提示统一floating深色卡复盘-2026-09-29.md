# Toast 提示统一为 floating 深色反色卡 复盘（2026-09-29）

## 一、现象与根因

**现象**：全应用错误/提示消息（如“请求错误：…”及各类操作反馈）均显示为屏幕底部**全宽黑色长条**，
无圆角、样式陈旧；无法手动关闭；宽屏下长文本横贯整个窗口。

**取证**：
- `lib/theme/app_theme.dart` 四套主题（M3 / Miuix × 浅 / 深）**均未配置 `snackBarTheme`**；
- 业务代码 `showSnackBar(SnackBar(content: Text(...)))` 共 **104 处**、散布 **31 个业务文件**，全部使用默认样式；
- 无 `SnackBarAction` / `MaterialBanner`，无任何非默认样式参数。

**根因链**：SnackBar 未主题化 → 渲染为 Flutter M2 式默认形态（`behavior=fixed`、全宽、贴底、无圆角）→
观感老化且不可点击关闭；提示调用分散在各页手写，无统一入口，样式无法收敛。

## 二、修复方案（关键决策）

选型来源：`toast_styles_demo.html` 中方案①的「floating · 深色反色卡」（官方 SnackBar 机制的主题化形态，零第三方依赖）。

1. **统一入口**（`lib/core/app_messenger.dart`）：
   - 新增 `showToast(context, message, {duration})`；`showAppSnackBar`（无 context 版）复用同一构建；
   - 行为：最新优先（`hideCurrentSnackBar` + `showSnackBar`）；默认 4s；
   - **点击关闭**：`SnackBar.padding` 归零 + content 外包 `GestureDetector(opaque)`，点击卡片任意处即关闭。
     取舍说明：SnackBar 官方无 onTap 能力，点击关闭无法纯主题实现，必须统一构建 content，因此本轮同时完成调用点收敛；
   - 限宽：content 加 `maxWidth: 520`，桌面宽屏长文本自动换行、不再整条横贯。
2. **主题化样式**（`lib/theme/app_theme.dart`）：四套主题各加 `snackBarTheme`：
   - `behavior: floating`、`elevation: 6`、`insetPadding (16,0,16,16)`；
   - 圆角沿用各自体系：M3 → 11（0.9 缩放）/ Miuix → 14（1.15 缩放）；
   - 反色配色（M3 inverse 语义、取项目暖色板）：
     - 浅色主题：卡底 `#221919`（md3LightOnSurface）/ 文字 `#FFF8F7`（md3LightSurface）；
     - 深色主题：卡底 `#F0DEDE`（md3DarkOnSurface）/ 文字 `#1A1111`（md3DarkSurface）；
     - Miuix 同逻辑取 `miuixLight* / miuixDark*` 对应值。
3. **调用点收敛**：104 处旧式调用全量替换为 `showToast(...)`：
   - 16 处本地 `_toast` 方法仅改方法体（其调用方零改动）；
   - 保留各点原有 `duration`（1s / 2s / 默认 4s）与 `mounted` 守卫；
   - 31 个文件补充 `import 'package:winwin/core/app_messenger.dart';`。
4. **遮蔽修复**：`lib/pages/video/detail_page.dart` 类内存在实例方法 `showToast(String)`
   （VideoInteractionMixin 接口），类内非限定调用会被实例成员遮蔽，改用库前缀 `app_messenger.showToast(...)`。

## 三、修复效果验证

**静态分析**：`flutter analyze lib` 替换过程中曾报 3 error（上述遮蔽问题）→ 修复后 **0 error / 0 warning**。
剩余 6 条 info 均为既有 lint（`account_service.dart`、`keyword_filter_policy.dart`、
`home_feed_anonymizer_policy.dart`、`login_page.dart:275/511`），与本次改动无关（未触碰行，改动前即存在）。

**Windows 双配置编译**：
- debug：`flutter build windows --debug` → √ Built `build\windows\x64\runner\Debug\winwin.exe`（20.6s），0 错误 0 警告；
- release：`flutter build windows --release` → √ Built `build\windows\x64\runner\Release\winwin.exe`（20.0s），0 错误 0 警告；
- 产物 `data\` 目录时间戳均已刷新（19:31 / 19:32），确认实际增量编译而非缓存复用。

**实机验证（待做；操作后请回发截图）**：
- [ ] 视频卡片右键 → 复制 BV 号：应出现底部居中深色圆角卡，点击卡片立即关闭
- [ ] 断网后刷新首页：应出现“请求错误”长文本卡（≤520 宽、自动换行）、点击可关闭
- [ ] 视频页点赞/收藏：2s 短提示卡正常显示与消退
- [ ] 切换深色主题后再触发任意提示：应为暖白反色卡（#F0DEDE 系）
- [ ] 设置中切换 Miuix 风格后再触发：同款浮层、圆角略大（14）
- [ ] 连续触发两条提示：新提示平滑顶掉旧的（最新优先）

## 四、本轮修复总结

**改动面**：33 个 lib 文件（核心 2：`app_messenger.dart` / `app_theme.dart`；业务 31）+ 本文档；
diff 规模 `+277 / -372`（净减 95 行，散布样板收敛为单行调用）。

**行为预期**：全应用提示统一为 floating 深色反色卡（浅色主题深卡、深色主题自动反转浅卡）；
新增点击任意处关闭；连发提示最新优先；各点位原有显示时长保留；网络错误全局入口自动同款。

**遗留项**：HTML demo 中的“悬停暂停”未实现（官方 SnackBar 不原生支持，如需可后续自研 overlay）；
不支持多条堆叠（SnackBar 单条语义，现为最新优先替换）。

## 五、GitHub 提交与回滚

- **修复提交**：`6989db9`（`[fix](toast): 全量统一为 floating 深色反色卡提示 + 点击关闭`），
  已推送 origin/main（`c12f52c..6989db9`）；
- **改动前快照**：`fa4480f6`（`refs/snapshots/latest` / `stash@{0}`，含改动前工作区全量，按项目规定打）；
- **回滚基准**：`git reset --hard c12f52c`（本修复提交前），或 `git revert 6989db9`；
- 本文档的提交 hash 见仓库 git 历史。
