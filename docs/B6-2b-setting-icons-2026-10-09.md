# B6-2b 复盘：setting 簇 Icon→AppIcon 统一（2026-10-09）

## 1. 现象描述

用户已实机复测 B6-2a 产物（21:07 启动的 Release）。复测后拉取全部日志面：
`.sandbox/*.log` 仍停留在 2026-08-16（监控脚本旧落盘）；全盘查找
`.winwin_logs.json`（catcher NDJSON 崩溃落盘）与 `logs/runtime.log` 均不存在——
说明复测运行全程零 catcher 上报、无崩溃。`dart analyze` 零问题。
结论：B6-2a 实机干净，可以继续推进 B6-2 主体。

## 2. 根因

B6-2（`Icons.` → AppIcons，全库 71 处 `Icon(Icons.)`）的最大同类簇在
`lib/pages/setting`（36 处命中，2 处已是 `AppIcon`，待转 34 处）：
`about_page` 空态行、`setting_page` 左侧导航、`models/` 四文件全部设置行
`leading` 槽位仍用裸 `Icon`，不经过 `AppIcon` 的 IconTheme 继承与
字形→Miuix 矢量映射。各文件早已混用 `AppIcon(AppIcons.xxx())`，
槽位类型均为 `Widget`，具备零风险批量转换条件。

## 3. 修复方案

B6-2b：setting 簇 34 处 `Icon(Icons.*)` → `AppIcon(Icons.*)`，零字形变化：

- `about_page.dart` 2 处（`icon: const Icon` → `icon: AppIcon`）
- `setting_page.dart` 4 处（左侧导航 `_items`，与同列表 `AppIcon(AppIcons.info())` 对齐）
- `models/play_settings.dart` 4 处、`extra_settings.dart` 8 处、
  `models/video_settings.dart` 8 处、`models/style_settings.dart` 8 处
  （`leading:` 槽位；`const Icon` 一律去 const，与 B6-2a 口径一致）

转换后 `lib/pages/setting` 内 `Icon(Icons.)` 残留归零（`AppIcon(Icons.)`
直参字形与语义方法缺口留 B6-2 主批）。

## 4. 验证与回滚

- 快照：改前工作区干净，`stash create` 为空属预期，快照指针沿用
  `refs/snapshots/latest = 0c449584`；本轮 6 文件 34 行，回滚
  `git checkout -- lib/pages/setting` 即可。
- `dart analyze`：No issues found（去 const 无连带 const 上下文破裂）。
- `flutter build windows --debug` 通过（34.7s）；
  `flutter build windows --release` 通过（79.1s）。
  双编译前已结束残留 `winwin.exe`（防 WebView2Loader.dll 锁）。
- 提交推送：`（待回填 hash）`。

## 5. 遗留与踩坑

- 遗留：全库剩余约 33 处 `Icon(Icons.)`（login 9、onboarding 3、toview/history/
  download 等散点）+ 全量 `AppIcon(Icons.)` 直参字形归一 + 语义方法缺口，
  待 B6-2c/主批收尾。
- 踩坑：`git log --oneline` 在首次调用时输出被截断为空，属终端翻页假象，
  重跑即正常；判空前应重跑一次确认。

## 6. 总结

实机复测零崩溃确认后，B6-2b 一次性收敛 setting 簇 34 处裸 Icon（该目录残留归零），
静态检查与双分支构建全过，为 B6-2 收尾（login/onboarding 等散点 33 处）扫清大头；
全库 `Icon(Icons.)` 由 71 → 约 33。
