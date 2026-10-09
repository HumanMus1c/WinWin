# 项目开发规范与智能体全局规则 (AGENTS.md)

## 核心规则 1：改动前必须打持久化 Snapshot（快照）
- **前置强制要求**：在对任何代码、配置或项目文件执行创建、编辑、重构或替换操作前，**必须首先执行全量暂存与快照持久化流程**，严禁只在内存中创建游离对象。
- **快照标准执行指令**：
  ```bash
  git add -A; git stash create | ForEach-Object { git update-ref refs/snapshots/latest $_; git stash store -m "snapshot_$(Get-Date -Format 'yyyyMMdd_HHmmss')" $_; $_ }; git reset
  ```
  1. `git add -A`：确保所有修改文件及**未跟踪的新建文件（Untracked Files）**均被完整纳入快照。
  2. `git stash create`：生成快照 Commit 对象 Hash。
  3. `git update-ref refs/snapshots/latest <hash>`：显式更新快照引用指针。
  4. `git stash store -m "snapshot_..." <hash>`：存入 Git Stash 历史列表，确保在 `git stash list` 中清晰可见。
  5. `git reset`：恢复工作区修改状态，准备开始执行代码编辑。
- **执行透明度**：在执行任何代码修改指令前，必须在回答或计划中明确注明当前快照状态、Hash 以及对应的 `refs/snapshots/latest` / `stash@{0}`。
- **快速回滚保障**：若后续修改出现逻辑偏差、编译错误或用户要求还原，可基于快照 Hash 或 `git stash apply/pop` 秒级精准回滚到改动前状态。

## 核心规则 2：Flutter 开发、热重载与 Windows 双分支编译构建规范
- 在修改任何 Dart / Flutter 代码后，检查应用运行状态并主动触发热重载或反馈运行状态。
- 执行代码改动后**严禁仅做 `dart analyze` 静态分析**，**必须依次完成以下三项完整验证**：
  1. 静态检查：运行 `dart analyze`，确保零编译错误和零警告；
  2. Windows Debug 分支编译验证：运行 `flutter build windows --debug`，确保 Debug 产物生成成功；
  3. Windows Release 分支编译验证：运行 `flutter build windows --release`，确保 Release 产物生成成功。
- 只有上述静态分析与 Windows 双模式构建全部通过后，方可进入代码提交与推送流程。

## 核心规则 3：改动完成后必须全量提交并推送到 GitHub (git commit & git push)
- **后置强制要求**：每次完成代码编辑、重构或任务修复并通过静态分析后，**必须将当前工作区改动全量提交并立即推送到 GitHub 远程仓库（`origin/main`）**。
- **标准提交推送流程**：
  ```bash
  git add -A
  git commit -m "<清晰的语义化提交信息>"
  git push origin main
  ```
- 确保用户在 GitHub 仓库网页端与 commit 记录中随时可见每一次改动的最新提交。

## 核心规则 4：优先复用与移植成熟实现，严禁盲目造轮子
- **检索与移植绝对优先原则**：在承接任何功能开发、逻辑修复、协议对接、播放器控制或策略重构任务时，**必须首先深度检索本地关联项目（如 PiliPlus、BiliPai）以及全网权威开源实现**，寻找可直接移植、参考或适配的成熟代码方案。
- **杜绝低效凭空发明**：
  1. **本地检索优先**：先扫描本地相关参考库（如 `D:\Documents\GitHub\PiliPlus`、`D:\Documents\GitHub\BiliPai` 等）是否已有成熟的算法、数据模型、API 参数及异常兜底逻辑。
  2. **全网检索补充**：若本地未覆盖，利用工具或权威源检索官方与第三方开源社区经过验证的成熟方案。
  3. **充分吸收与适配**：在现有优秀架构基础上进行直接移植、接口对齐并针对当前平台（如 Windows / Flutter）做必要的边界修复与健壮性增强。
- **原创编写门槛约束**：**只有在本地参考库与全网深度检索后，确认 100% 完全不存在任何可参考、可借鉴或可移植的成熟代码时**，才允许从零构建全新的自研实现。

## 核心规则 5：构建验证工作流（Windows 双分支）
- 每次进入双分支编译（`flutter build windows --debug/--release`）前，**自动结束占用 `WebView2Loader.dll` 的残留 `winwin.exe` 进程**（免手动处理 DLL 锁死）。
- 构建全部完成后，**自动启动本轮最后一次成功构建的产物**（debug 或 release 的 `winwin.exe`），供用户直接实机验证。

## 核心规则 6：文档纪律（改动与文档同批闭环）
- 每次代码改动必须同步落实到文档：新建/追补复盘（现象/定因/方案/验证/提交回滚五要素 + 遗留与踩坑 + 总结）+ `docs/MD3库级退役进度追踪-2026-10-07.md` 进度表回填，与代码**同批提交推送**，不拖欠。
- **复盘缺档即视为任务未闭环**。

## 项目概况与环境要点
- WinWin = Bilibili 第三方 Flutter Windows 客户端；播放内核 **fvp/mdk**（非 media_kit）；上游参考 PiliPlus / BiliPai。
- **运行时日志真实路径**：`D:\Documents\.winwin_logs.json`（catcher NDJSON 崩溃落盘）与 `D:\Documents\logs\runtime.log`；`getApplicationDocumentsDirectory()` 在本机重定向到 `D:\Documents`，排查日志勿查 `C:\Users\...\Documents`（2026-10-09 三轮误判的根因）。
- **Git 提交信息**：经 UTF-8 临时文件 + `git commit -F` 写入（PowerShell 5.1 管道会破坏中文）；`git push` 偶发 443 超时，重试即可。
- **UI 图标约定（B6-2 起）**：全库裸 `Icon(Icons.)` 已归零；新增/修改一律使用 `AppIcon(AppIcons.语义方法())`；语义方法为运行时映射，**不能加 `const`**。

## MD3 退役进度与中断点（2026-10-09 23:45 快照 · 过渡信息）
- 主线：MD3 `material_ui` 全库退役 → `flutter_miuix`（ChuxinNeko/flutter_miuix）。段位：L0/B1~B5 ✅ → B6-1~B6-2e ✅ → **B6-2f 进行中** → B6-3 InkWell/IconButton → B6-4 Card/ListTile → B6-5 Divider/Material → B6-6 Colors→Token → B7 摘除依赖封板；B1b 测试宿主统一暂缓。
- 闸门指标：`lib` 内 `import material_ui` 文件数 **133**（起始 137，B7 前归零）。
- **中断点**：B6-2f（35 处直参转语义）已完成约 33 处但**未提交（工作区 18 文件）**；剩 2 处：`lib/pages/follow/view.dart:270`、`lib/pages/pgc/view.dart:602`（`AppIcon(Icons.login)`）；未跑 analyze/test/双编译。
- 进度与复盘细节以 `docs/MD3库级退役进度追踪-2026-10-07.md` 及 `docs/B6-2*.md` 为准。


