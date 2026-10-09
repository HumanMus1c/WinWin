# B6-2f 复盘：直参收尾 35 处 · B6-2 图标批收官（2026-10-10）

## 1. 现象描述

B6-2a~2d 把全库裸 `Icon(Icons.)` 清零、B6-2e 收敛 setting 簇后，全库仍剩
35 处 `AppIcon(Icons.xxx)` 直参（login 9 / profile 4 / onboarding 3 /
whisper 系 4 / follow·pgc·收藏·历史·下载·搜索·动态·画廊等散点 15），
字形决策仍散落调用点，B7 摘除依赖前必须收敛到 `AppIcons` 语义方法。

## 2. 根因

同 B6-2e：直参把"用什么字形"的决策留在调用点，后续美术替换无法单点切换；
`AppIcons` 第 1~9 节缺 login/profile/whisper/空态语义区。另本批涉及多处
`const` 上下文（`const Row` / `const SizedBox` / `const List`），
而静态方法调用非 const 表达式，需 analyze 驱动拆除。

## 3. 修复方案（零字形变化）

- `app_icons.dart` 新增第 10 节 **27 个**通用语义方法（1:1 原字形）：
  loginSubmit / accountField / passwordField / smsCodeField / qrPlaceholder /
  cookieField / countryArrow / switchAccount / logout / offlineEmpty /
  historyEmpty / clauseOpenSource / clauseDisclaimer / clauseFeedback /
  atMe / sysNotice / emptyNotice / reportAbuse / folderEmpty / playAll /
  clearAll / searchEmpty / spaceOffline / playEpisode / downloadEmpty /
  goodsEntry / galleryPrev。
- 20 文件 **35 处** `AppIcon(Icons.x)` → `AppIcon(AppIcons.y())`
  （含 follow/pgc 两处未登录态「登录」按钮收尾，复用 `loginSubmit()`）。
- 修 7 处 `const_eval_method_invocation`：login 3 处登录按钮行 `const Row`
  与扫码占位 `errorBuilder` 的 `const SizedBox` 去 const；
  onboarding 顶层 `const List<_Clause>` → `final`（元素为部件构造链）。

## 4. 验证与回滚

- 快照：`013cdd9f`（`refs/snapshots/latest`，含本批改前全量工作区）；
  回滚可 `git checkout -- <file>` 或以快照 `git stash apply`。
- `dart analyze` 零问题（批次中途残留 7 error，全部按上消除）；
  `flutter test` **164/164 全绿**；
  `flutter build windows --debug` 与 `--release` 双通过、0 警告
  （编译前已清残留 `winwin.exe`，构建后已自启 Release 产物）。
- 残留复核：`AppIcon(Icons.` 全库仅剩 `app_icons.dart` 内注释 1 行，
  **裸 `Icon(Icons.)` 与直参双双归零**；闸门指标维持 **133**。
- 提交推送：`（本批回填）`（代码+复盘+进度表同批）。

## 5. 遗留与踩坑

- 遗留：B6-2 图标批收官（a~f）。下一步 B6-3（`InkWell`/`IconButton` →
  MiuixPressable / MiuixIconButton，现测 28+28 文件）；B1b 仍暂缓。
- 踩坑：① `const` 上下文残留不会被字形迁移脚本覆盖，必须 analyze 全量
  驱动逐点拆除（分两段执行的批次尤其要重跑全量分析）；
  ② `const List` 顶层列表元素若含部件构造链，需降 `final`，否则整表失败；
  ③ Windows 构建产物判定：`winwin.exe`（C++ 壳）不随 Dart 改动更新，
  应以 Release 的 `data\app.so` / Debug 的 `data\flutter_assets\kernel_blob.bin`
  时间戳为准。

## 6. 总结

B6-2 全批收官：全库裸 `Icon(Icons.)` 0 处、`AppIcon(Icons.)` 直参 0 处，
图标字形决策全部收敛到 `AppIcons` 语义方法（现共 113 个静态方法）；
双分支构建与 164 项测试全绿；下一批进 B6-3。

## 7. 测试验证指导（本轮产物）

- **登录页**：密码/短信/扫码/Cookie 四 Tab 全切一遍：prefix 图标
  （账号/密码/验证码/Cookie）、区号箭头、3 处登录按钮图标、扫码失败占位图
  与上一版一致。
- **未登录空态**：关注页（登录后查看关注动态）、追番页（登录后查看我的追番）
  的「登录」按钮图标正常。
- **空态散点**：收藏夹/搜索无结果/历史/稍后再看/下载/消息流/空间加载失败——
  图标与上一版一致。
- **条款页**：设置→关于→开源协议，三条目图标正常。
- **预期结果**：零视觉变化；任何图标缺失/错位/挤压即回退。
- **日志**：复测后核对 `D:\Documents\.winwin_logs.json` 与
  `D:\Documents\logs\runtime.log` 有无新增条目（重点：login 四 Tab 切换、
  未登录空态点击、画廊左箭头）。
