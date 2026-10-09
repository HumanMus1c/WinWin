# B6-2e 复盘：setting 簇 36 处直参→语义方法（2026-10-09）

## 1. 现象描述

B6-2a~2d 把全库裸 `Icon(Icons.)` 清零，但留下 71 处 `AppIcon(Icons.xxx)`
直参——字形仍散落在调用点，B7 摘除依赖前必须收敛到 `AppIcons` 语义方法。
本批取最大同类簇：`lib/pages/setting` 6 文件 36 处（约 34 个独立字形）。

## 2. 根因

直参把"用什么字形"的决策留在 25 个调用文件里；后续美术替换
（如 login/sms 等语义已有 BDC/官网矢量层）无法单点切换。
`AppIcons` 已有第 1~8 节语义区，缺第 9 节"设置面语义"。

## 3. 修复方案（零字形变化）

- `app_icons.dart` 新增第 9 节 34 个语义方法（appearance/touchAction/
  videoSetting/extraSetting/aboutCode/openSource/appFont/themeMode/
  pureBlack/fontSize/uiScale/nativeTitleBar/trayIcon/minimizeToTray/
  fontImport/fontRestore/hardwareAccel/p1080/defaultAudioQuality/
  loudnessEqualizer/cdnNode/decodeMode/bufferSize/autoplay/
  screenshotButton/keyboardControl/http2/systemProxy/sslBypass/
  appRecommend/mergeDanmaku/runLog/pauseHistory/demoMode），
  一律返回原字形。
- 6 文件 36 处 `AppIcon(Icons.x)` → `AppIcon(AppIcons.y())`。
- 12 处 `const SwitchModel(` 去 const（方法调用非 const 表达式，
  analyze `const_eval_method_invocation` 驱动，逐一确认）；
  3 文件（extra/play/video_settings）`material_ui` 导入因无残留引用而删除
  ——闸门指标 136→133（预期，属依赖收敛正向）。

## 4. 验证与回滚

- 快照：改前干净，指针沿用 `0c449584`；回滚逐文件 checkout。
- `dart analyze` 零问题（首轮 12 error + 3 warning，全部按上消除）；
  `flutter test` 全量全绿；`flutter build windows --debug`（31.7s）/
  `--release`（78.8s）双通过；编译前已清残留进程。
- setting 簇 `AppIcon(Icons.` 残留归零；全库直参 71→35。
- 提交推送：`958f989`（代码+复盘+进度表同批）。

## 5. 遗留与踩坑

- 遗留：直参剩 35 处（login 9/profile 4/onboarding 3/whisper 系 6/
  历史/收藏/下载/搜索等散点）→ B6-2f；B1b（test 统一 harness：
  17 文件 import material、约 40 处 MaterialApp、无共享 harness）
  为纯 test 基建，与 lib 退役无依赖，建议 B6 之后单批处理。
- 踩坑：`const` 上下文中无关键字的构造调用是隐式 const，
  但静态方法调用永不为 const——凡 `const Model(leading: AppIcon(...))`
  迁移语义方法时必须同步去 const，靠 analyze 兜底。
- rg 在 PowerShell 下 glob 用 `--glob` 而非 shell 通配；
  `Select-Object -First` 不带数字会按缺参报错。

## 6. 总结

B6-2e 完成 setting 簇语义收敛（36 处，零字形变化），附带摘掉 3 个
material_ui 引用；B6-2（图标）仅剩 B6-2f 35 处直参。

## 7. 测试验证指导（本轮产物）

- **设置四页**：外观/播放器/音视频/其它、关于页，全部行图标与上一版一致；
  重点看去 const 的 12 个 Switch 行（纯黑/托盘/最小化/硬解/1080P/代理/
  日志/历史暂停等）开关可点、状态持久化正常。
- **字体对话框**：外观→应用字体→导入/恢复按钮图标正常。
- **预期**：零视觉变化；任何图标缺失/开关失灵即回退。
- **日志**：复测后核对 `D:\Documents\.winwin_logs.json` 有无新增条目。
