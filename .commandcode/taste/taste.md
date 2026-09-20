# Taste

## Workflow
- Prefers root-cause analysis grounded in recent git commit history and the project's `docs/` development documents before writing any code; asks for an explicit development plan rather than immediate edits. Confidence: 0.8
- Prefers an evidence-first workflow: add structured runtime logging/tracing and run an A/B variant matrix to get objective data before touching fragile logic — especially in code with a history of fix-then-revert cycles. Confidence: 0.75
- When trading off in a fix, prioritizes correctness (e.g. deterministic synchronization) over speed, accepting slight added latency. Confidence: 0.6

## Tooling & process
- Runs `dart analyze` expecting 0 error / 0 warning, and builds both `--debug` and `--release` Windows configs, reported separately; dislikes temporary-directory builds. Confidence: 0.7
- Takes a pre-change snapshot (`git stash create` → `refs/snapshots/latest`) to enable precise, revocable rollback. Confidence: 0.6
- Uses bracketed conventional commit messages: `[type](scope): 中文描述`. Confidence: 0.7
- Maintains a per-fix document under `docs/` covering five elements: root cause / fix plan / verification / summary / commit records. Confidence: 0.7

## Communication
- Communicates in Chinese and expects replies in Chinese. Confidence: 0.9
