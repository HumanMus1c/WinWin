# protobuf 适配与 CI 门槛放宽复盘（附：首个正式发布、tag 创建时机与 icon_sheet 跨环境修复）

> 日期：2026-10-06 ｜ 类型：依赖兼容修复 + CI 标杆调整 + 首个正式发布 + 测试跨环境健壮化
> 快照基准：`refs/snapshots/latest = 29bfaf2710a3c27e8adf49684e4f2a3fbcce5337`
> 关联：`docs/依赖探测CI恢复与发布链路首跑复盘-2026-10-06.md`、`docs/云端CI失败根因与处置复盘-2026-10-04.md`、`docs/版本号管理规范-2026-10-06.md`

## 一、分析根因

### 1.1 protobuf 6.1.0 弃用 `create()`（跨包引用暴露）

- **现象（同一根因、两条复现路径）**：
  1. 2026-10-04 云端 CI 失败根因链（历史）：包源漂移 → 重解析升级 `protobuf 6.0.0 → 6.1.0` → `rpc.pb.dart:49`（`$0.Any.create`）触发 `deprecated_member_use` → 严格 analyze（info 亦致命）失败；
  2. 今日探测 CI 首跑红灯（`37489939484`）：gate 升级 37 包 → 同一条 info → 红灯。
- **根因**：protobuf 6.1.0 弃用生成类的 `create()` 静态工厂（推荐构造函数 `Any() / Any.new`）；本仓 `rpc.pb.dart` 为旧版生成物，`$0.Any.create` 属**跨包**引用（同文件内的自引用被 `ignore_for_file: deprecated_member_use_from_same_package` 豁免，仅此跨包一处暴露）。
- **附带事实**：全项目仅此 1 处（`git grep` 确认）；该文件**当前无任何调用方**（零风险替换基础）。

### 1.2 CI 门槛过严（info 亦致命）

- `flutter analyze` 默认 `--fatal-infos=on` / `--fatal-warnings=on`（本机 `--help` 核实）→ 上游弃用类 **info** 提示会让"升级验证"长期红灯（狼来了效应）。

### 1.3 icon_sheet_test 跨环境失败（CI 二跑新发现）

- **现象**（`37508655391`）：全量升级环境下 `test/tools/icon_sheet_test.dart` 失败——
  `A RenderFlex overflowed by 26 pixels on the bottom`（约束 `w=752, h≤552`，即 800×600 默认视口减 24×2 padding）。
- **根因链**：测试的字体重硬编码路径加载——
  `'D:/flutter/bin/cache/artifacts/material_fonts/…'`（CI 上 SDK 在 `C:\hostedtoolcache\…`）、
  `'C:/Users/SilverT1ger/AppData/Local/Pub/Cache/…'`（CI 无此用户路径）、
  `'C:/Windows/Fonts/simhei.ttf'`（**Windows Server runner 无 simhei**）→ 字体静默回退 → 度量更大 → 默认 600 高视口下**临界溢出 26px**。
- **为何在"升级后"才暴露**：该套测试**首次在云端跑到**（旧 CI 在 analyze 步骤即挂、探测 CI 首跑也在 analyze 被拦）——属**环境差异**问题，由"全量升级环境 + CI 无字体"两个条件共同触发。

## 二、设计修复计划

1. **移植上游新版生成物**（遵循"优先复用上游"）：PiliPlus 同文件已运行于 protobuf 6.1.0（新生成风格：`$_createMessage` / 构造函数直用），diff 仅 ~18 行纯生成器差异 → **整体移植** + lock 升级 `6.0.0 → 6.1.0`（仅 1 项依赖变更）。
2. **CI 门槛放宽**：`flutter analyze --no-fatal-infos`（info 放行；warning / error 仍硬拦）。
3. **首个正式发布**：草稿 `v0.1.0+26100601` 转正。
4. **icon_sheet 跨环境健壮化**：
   - 字体候选链动态化（`FLUTTER_ROOT` / `PUB_CACHE` 环境变量 + pub 缓存动态定位 + SheetCJK 四候选 simhei→msyh→simsun→Deng），加载结果 `debugPrint` 可诊断；
   - 渲染画布加高（`setSurfaceSize(800×1024)`，**宽度不变** → 既有布局与产物尺寸不变），消除字体度量差异的临界溢出。

## 三、修复效果验证

| 项 | 结果 |
| --- | --- |
| `dart analyze`（protobuf 6.1.0 + 新版文件） | ✅ No issues found（弃用消除） |
| `flutter test`（本地 ×3 次，含全量升级环境） | ✅ 136 全绿 |
| Windows debug / release 双编译 | ✅ 48.8s / 70.6s，0 警告 0 错误 |
| 替换风险控制 | ✅ 文件无调用方（git grep 确认）；与上游结构同源（diff 18 行） |
| 首个正式发布 | ✅ `v0.1.0+26100601` 转正（Latest） |
| CI 二跑修复（icon_sheet） | ✅ 缺字体**模拟**场景通过（诊断输出 + 无溢出）；正常字体产物**零 diff** |
| 云端复验（force dispatch） | ✅ **全绿**（`37510585800`）：probe 48s → gate 17m43s（36 包升级 → analyze ✓ → test ✓ → Debug 构建 ✓ → artifact `WinWin_windows_x64_debug_0.1.0+26100601.zip`） |

### 3.1 云端运行全景（本轮全部运行）

| 运行 | 结果 |
| --- | --- |
| Release 首跑 `37486172828` | 构建链全绿（含版本纪律门禁 ✓），倒在上传产物（archive:false 单文件约束）→ 修复 `37af1d7` |
| Release 重跑 `37489927567` | ✅ 全绿 13m28s；tag + 草稿 Release（3 assets）创建 |
| CI 首跑 `37489939484` | probe ✓ 1m42s → gate：37 包升级 → analyze 报 1 条 protobuf info → 红灯（§1.1） |
| 转正触发的 Release 重建 `37508455991` | ✅ 14m44s；assets 已刷新（18:16Z）；见 §3.2 机制发现 |
| CI 二跑 `37508655391` | probe ✓ 51s（**快照变化检测生效**：protobuf 条目变化触发）→ gate：analyze ✓（放宽生效）→ test 135/1（icon_sheet，§1.3）→ 修复 `bb5f555` |

### 3.2 重要发现：草稿 Release 的 tag 创建时机（流程注意）

- **证据**：转正（`18:04:17Z`）后 2 秒出现 push 事件——`ref=v0.1.0+26100601`、`headSha=7511df4`（main 当前 HEAD）、`actor=HumanMus1c`；并立即触发了一次额外的 Release 工作流（`37508455991`，14m44s 完成，assets 刷新为 7511df4 构建）。
- **机制**：**GitHub 草稿 Release 关联的"新 tag"在草稿期间并不创建**（API 仅显示 tag_name；`git ls-remote` 查不到）；**转正时才创建 tag，且指向 `target_commitish`（此处为 main 分支）的"当时最新提交"**——而非草稿创建时的提交（`cdb1eb3`）。tag 创建动作随即触发 `push: tags: v*` → 额外 Release 构建。
- **流程建议（应写入版本号管理规范）**：正式发布优先走「**本地创建 tag**（固定指向发版提交）→ `git push origin <tag>` → 工作流构建 + 草稿 → 转正」路径——tag 由我们创建时该问题不存在；若走 dispatch 路径，**转正前须确认 main HEAD == 发版提交**。

### 3.3 icon_sheet 修复验证细节（§1.3 的修复侧）

| 验证 | 结果 |
| --- | --- |
| 正常字体（全量升级环境）跑 `test/tools/icon_sheet_test.dart` | ✅ 通过；诊断输出 `字体 SheetCJK ← C:/Windows/Fonts/simhei.ttf` |
| 产物零扰动 | ✅ `docs/icon-sheets/` 在本机组装渲染下**零 diff**（宽度不变设计达成） |
| 缺字体**模拟**（候选指向不存在路径） | ✅ 打印 `字体 SheetCJK 未找到…将使用回退度量`，测试**依然通过**（视口余量兜底） |
| 全套件回归（还原 lock 后） | ✅ 136 全绿；`dart analyze` 0 问题 |

## 四、本轮修复总结

- **改动面**：`lib/grpc/bilibili/rpc.pb.dart`（移植上游新版）、`pubspec.lock`（protobuf 6.1.0）、`.github/workflows/windows-x64-ci.yml`（analyze 门槛放宽）、`test/tools/icon_sheet_test.dart`（跨环境健壮化）。
- **行为预期**：任何"重解析 / 全量 upgrade"路径不再触发 `create` 弃用；CI 对 info 级提示放行、warning / error 保持硬拦；icon_sheet 生成器在无中文字体 / 异构 SDK 路径的 CI 环境也可跑通且不扰动产物。
- **遗留**：
  - ☐ 版本号管理规范补「tag 创建时机与发布路径」注意节（§3.2）；
  - ☐ 探测信号语义注记：`resolvable`（探测）可能比 `pub upgrade`（gate 实际升级，约束内）更激进——宽触发 + 保守执行，属设计预期，建议写入规范；
  - ☐ 云端复验结果回填（补记 C）。

## 五、提交与回滚

- **改动前快照**：`29bfaf2710a3c27e8adf49684e4f2a3fbcce5337`（`refs/snapshots/latest`）。
- **GitHub 提交记录**：
  - `efd9303` —— `[fix](grpc): 移植上游新版 rpc.pb.dart + protobuf 6.1.0——消除 create 弃用，升级兼容闭环`
  - `7511df4` —— `[ci](deps): 静态分析门槛放宽——info 不拦（--no-fatal-infos），warning / error 仍为门禁`
  - `bb5f555` —— `[fix](test): icon_sheet 生成器跨环境健壮化——字体候选链动态化 + 渲染视口高度余量`
  - 本复盘提交 `efcf282`；云端复验结果（全绿）已回填 §3；[docs] 补记提交 hash 见 git log（按全局开发规定补记）
