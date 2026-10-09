# B6-5 复盘：Divider/VerticalDivider → Miuix 分隔线 + Material( 收尾 — 2026-10-10

## 1. 现象描述

B6-4 后 `lib` 内仍有 Material `Divider` 32 处（21 文件）、
`VerticalDivider` 3 处，及 `Material(` 16 处（多数为透明祖先提供者）。
B7 摘除依赖前须迁移分隔线并收尾 `Material(` 用法。

## 2. 根因

flutter_miuix 1.3.0 **实含** `MiuixHorizontalDivider` / `MiuixVerticalDivider`
（默认 0.75px、`dividerLine` = 桥接 `outlineVariant`）——此前 B6 盘点
"包内无 MiuixDivider"的结论作废，按最新包勘误；`Material(` 中多数是
透明祖先（转场期必需，B7 随 import 切换统一处置），少数为表面/冗余用途。

## 3. 修复方案

- **32 处 Divider**（脚本 25 + 手工 7）→ `MiuixHorizontalDivider`：
  - `height: 1` 系（含 thickness 0.5/0.3 变体）→ 直换（无额外间距）；
  - `height: Style.xl/lg`（带间距隔离段）→
    `SizedBox(height: .., child: Center(child: MiuixHorizontalDivider()))` 保间距语义；
  - `const Divider()`（默认 16 高）→ 同款 SizedBox(16) 包壳；
  - `outlineVariant@0.2/0.3` 自定义色 → 以 `color` 参数保留。
- **3 处 VerticalDivider**（设置转开关行 / 番剧详情两栏 / 番剧播放两栏）→
  `MiuixVerticalDivider(thickness: 1, color: ..)`（`SizedBox(height: 25)` 包壳保留）。
- **Material( 收尾（5 处）**：
  - 表面用途 3 处（聊天分享卡/视频卡、视频详情话题芯片）→
    `Container(color:)` / `Container(decoration: BoxDecoration(..))` 精确等价；
  - 冗余透明祖先 2 处（会话列表页、会话段落页——原为 ListTile hover
    高亮泄漏而设）→ 随 B6-4b 行组件退役**移除**（ListView/CustomScrollView
    自带视口裁剪，注释同步清理）。

## 4. 验证与回滚

- 快照：`b6e89b17`（`refs/snapshots/latest`）。
- `dart analyze` 零问题（首轮 5 处缺导入，脚本补齐 show 列表）；
  `flutter test` **164/164 全绿**；
  双分支构建通过（kernel 01:52:18 / app.so 01:53:35），构建后已自启 Release
  （PID 43080）。
- 残留复核：`Divider`/`VerticalDivider` 0 处；`Material(` 剩 11 处
  （透明祖先 9 + 桥接 2，B7 处置）；闸门指标维持 **133**。
- 提交推送：`（本批回填）`（代码+复盘+进度表同批）。

## 5. 遗留与踩坑

- 遗留：**B6-6**（`Colors.` 761 处 → Token），随后 B6 收官复测。
- 踩坑：① 包内分隔线组件以最新包源为准（旧盘点勘误）；
  ② 间距型 Divider 必须 SizedBox+Center 等价替换，否则布局塌缩；
  ③ 移除冗余 `Material` 祖先层前须核对子级类型与裁剪语义
  （ListView/CustomScrollView 自带裁剪 → 可安全移除）。

## 6. 总结

B6-5 完成：分隔线 35 处全量 Miuix 化 + Material( 五项收尾（22 文件 +58/−74）；
静态检查、164 项测试、双分支构建全绿；B6 仅剩 B6-6（Colors→Token）。

## 7. 测试验证指导（本轮产物）

- **分隔线观感**：登录页/关于页/设置各页/弹幕·字幕设置/播放器面板/私信
  会话列表与段落——细线（0.75px 口径）替代原 1px 线；带间距的分隔段
  （番剧选集/播放页/视频详情/弹幕设置）间距不变。
- **竖线**：番剧详情左右两栏、番剧播放页两栏、设置「弹幕设置」行内竖线。
- **聊天分享卡/视频卡、话题芯片**：底色与圆角与上一版一致（精确等价）。
- **会话列表滚动/悬停**：滚动过程行悬停无高亮泄漏残留（原透明 Material
  裁剪层已移除，ListView 自身裁剪生效）。
- **预期结果**：线更细但位置/间距不变；其余零视觉变化；异常即回退。
- **日志**：复测后核对 `D:\Documents\.winwin_logs.json` 与
  `D:\Documents\logs\runtime.log` 有无新增条目。
