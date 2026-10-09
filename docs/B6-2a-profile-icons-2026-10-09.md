# B6-2a 复盘：profile 区 Icon→AppIcon 统一（2026-10-09）

## 1. 现象描述

`.sandbox/stdout.log`（2026-08-16 落盘）中唯一的 Flutter 侧高频报错是
`ListTile background color or ink splashes may be invisible`（60 次去重计数）；
`stderr.log` 仅为无害的 accessibility_bridge AXTree 噪声。
经核查，日志已过期（早于 9992bff/9da1ce4 两轮修复），当前 `dart analyze` 零问题，
无新增崩溃。继续推进的事项是 B6-2（`Icons.` → AppIcons，全库 71 处 `Icon(Icons.)`）。

## 2. 根因

- 旧日志的 ListTile 遮挡警告源头有二：画廊弹窗三行操作（已在 9992bff 中补视口内
  透明 Material）与 `Dismissible` 红色滑动底色（宿主为自带 Material 的 `Dialog`，
  无红屏风险）。其余 14 处 ListTile 系站点均直挂 `AppScaffold(Material)` /
  原生 `Scaffold` / `Dialog`，无 DecoratedBox 包裹——旧告警已无残留。
- B6-2 的直接障碍：profile 区 4 处仍用裸 `Icon(Icons.)`（离线缓存空态、
  历史空态、账号切换、退出登录），不经过 `AppIcon` 的 IconTheme 继承与
  字形→Miuix 矢量映射，未来无法享受统一的字形归一。

## 3. 修复方案

B6-2a 先导批（零字形变化，仅统一部件，风险最低；完整语义方法
如 switchAccount/logout 待后续 B6-2 主批新增）：

- `lib/ui/profile/widgets/profile_sections.dart:109`：
  `Icon(Icons.download_for_offline_outlined)` → `AppIcon(...)`
- `lib/ui/profile/widgets/profile_sections.dart:384`：
  `Icon(Icons.history_toggle_off)` → `AppIcon(...)`
- `lib/ui/profile/profile_page.dart:625`：
  `Icon(Icons.swap_horiz, color: cs.primary)` → `AppIcon(...)`
- `lib/ui/profile/profile_page.dart:641`：
  `const Icon(Icons.logout, color: Colors.red)` → `AppIcon(...)`（去 const，
  因 AppIcon 为运行时映射部件）

字形保持 Material 原样（`AppIcon` 无映射时回退 `Icon`），视觉零漂移；
已有先例：`style_settings.dart:331` 早已用 `AppIcon(Icons.file_upload_outlined)`。

## 4. 验证与回滚

- 快照：工作区改前干净（`git status` 空），`git stash create` 返回空是预期行为；
  快照指针保持 `refs/snapshots/latest = 0c449584`（`stash@{0} snapshot_20261009_favbg`），
  本轮改动仅 2 文件 4 行，回滚可用 `git checkout -- <file>` 秒级还原。
- `dart analyze`：No issues found。
- `flutter build windows --debug` 通过（28.2s）；
  `flutter build windows --release` 通过（71.5s）。
  双编译前已按工作流约定结束残留 `winwin.exe`（防 WebView2Loader.dll 锁）。
- 提交推送：`a7c0684`（`git add -A; git commit; git push origin main`）。

## 5. 遗留与踩坑

- 遗留：全库仍有约 67 处 `Icon(Icons.)`（setting/models 下 20+ 处为大头）与
  `AppIcon(Icons.)` 直参字形（B 类字形归一未完成）；语义方法缺口
  （swap_horiz/logout/download_for_offline/history_toggle_off 等）待 B6-2 主批补齐。
- 踩坑1：Windows PowerShell 5.1 无 `head`，日志截取改用 `Select-Object -First/-Last`。
- 踩坑2：`python3` 不可用（应用商店跳转），改用 `python`；`Select-String` 在含 CJK
  的 docs 路径下工作正常，但 `read` 表格行可直接用于精确编辑。
- 踩坑3：工作区干净时 `git stash create` 输出为空，后续 `update-ref/stash store`
  会失败——属预期，直接沿用既有快照指针并在复盘注明即可。

## 6. 总结

本轮为日志分析驱动的 B6-2a 先导收敛：确认旧 ListTile 告警已在前两轮修复中消除、
无新增运行时错误后，将 profile 区 4 处裸 Icon 统一为 AppIcon（零视觉变化），
静态检查与 Windows 双分支构建全过，为 B6-2 主批（语义图标补齐 + setting/models
大头迁移）铺平道路。
