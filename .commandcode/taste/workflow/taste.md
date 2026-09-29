# Workflow preferences

- Takes a pre-change git snapshot before making changes (project convention: `git add -A; git stash create` → `git update-ref refs/snapshots/latest`), one snapshot per change round, so each round has an independent rollback point restored via `git reset --hard <SHA>`. Confidence: 0.7
- Verifies changes with a full `dart analyze` targeting 0 error / 0 warning and no newly introduced issues, plus both `flutter build windows --debug` and `--release`, before committing. Confidence: 0.6
- Writes a retrospective ("复盘") markdown doc into `docs/` for each change, structured by five elements (根因 / 方案 / 验证 / 总结 / 提交与回滚) with rollback SHAs and a manual on-device verification checklist. Confidence: 0.6
- Batches git pushes: commits locally throughout the work, then pushes to `origin/main` once at the end of the session ("推送按惯例在会话末尾统一执行"). Confidence: 0.6
- For multi-round work, records a plan file under `~/.commandcode/plans` and surfaces it in the Plans panel, and tracks steps with a todo list (P0 → P1 → P2 sequencing). Confidence: 0.5
- Executes approved changes step by step, in priority order, returning to the user for confirmation before starting. Confidence: 0.5
