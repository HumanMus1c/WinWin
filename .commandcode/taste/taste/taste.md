# Taste
- When an attempted fix reintroduces an older regression, expects it to be rolled back immediately to the last known-good state instead of being iterated on in place; experimental changes are not kept just because they partially helped. Confidence: 0.7
- Prefers root-cause analysis grounded in recent git commit history and the project's `docs/` development documents before writing any code; asks for an explicit development plan rather than immediate edits. Confidence: 0.8
- Prefers an evidence-first workflow: add structured runtime logging/tracing and run an A/B variant matrix to get objective data before touching fragile logic — especially in code with a history of fix-then-revert cycles. Confidence: 0.75
- When trading off in a fix, prioritizes correctness (e.g. deterministic synchronization) over speed, accepting slight added latency. Confidence: 0.6
- Runs `dart analyze` expecting 0 error / 0 warning, and builds both `--debug` and `--release` Windows configs, reported separately; dislikes temporary-directory builds. Confidence: 0.7
- Treats a pre-change snapshot (`git stash create` → `refs/snapshots/latest`) as a mandatory step for every change — a stated global rule, not optional — and calls it out when it's skipped. Confidence: 0.85
- Uses bracketed conventional commit messages: `[type](scope): 中文描述`. Confidence: 0.7
- Maintains a per-fix document under `docs/` covering five elements: root cause / fix plan / verification / summary / commit records. Confidence: 0.7
- Does not weaken security settings to work around failures (e.g. never disables SSL/TLS certificate verification for a failing `git push`); prefers to keep retrying and report the blocker. Confidence: 0.6
- Communicates in Chinese and expects replies in Chinese. Confidence: 0.9
- Wants to be able to build/run the app himself: asks for exact, copy-pasteable Debug/Release compile-and-run commands (build output paths, `flutter run -d windows`) instead of relying solely on the agent to drive builds. Confidence: 0.5
- Prefers to drive end-to-end verification himself by manually interacting with the running app; asks for automated test drivers (e.g. scripted auto-seek) to be turned off while keeping the underlying logging/observability fully in place. Confidence: 0.65
- Expects the feasibility of candidate solutions to be re-evaluated against the latest releases/changelogs of the relevant libraries and dependencies before committing to an approach. Confidence: 0.7
- Consults comparable open-source projects (e.g. PiliPlus) as reference implementations and expects their approach to be investigated with concrete source evidence before picking a design. Confidence: 0.55
- Prefers to port/replace with a proven, mature implementation (e.g. switching the player core to mpv/media_kit, as PiliPlus does) over continuing to pile custom patches on an in-house approach once it keeps failing. Confidence: 0.6
- Once several successive fix attempts have failed, expects the agent to stop patching and instead lay out the remaining candidate solutions with their costs/risks and wait for the user to pick the direction (approval before acting, snapshot first). Confidence: 0.5
- When a format/library-based - Expects a newly added switch / code path to be confirmed as actually active from runtime logs before being told a fix is in place and asked to test again; a fix that was reported as live but never took effect (unparsed config flag) erodes trust and is called out as the "same old problem". Confidence: 0.5
approach fails, expects the actual capability of the bundled runtime to be verified empirically (e.g. scanning the shipped binary/DLL for compiled demuxer/library symbols) to pin down the true root cause, rather than assuming the format is supported. Confidence: 0.55
