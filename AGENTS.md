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

## 核心规则 2：Flutter 开发与热重载规范
- 在修改任何 Dart / Flutter 代码后，检查应用运行状态并主动触发热重载或反馈运行状态。
- 执行代码改动后必须运行 `dart analyze` 进行静态检查，确保零编译错误和零警告。
