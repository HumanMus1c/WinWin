# B6-2c 复盘：散点 20 处 Icon→AppIcon 统一（2026-10-09）

## 1. 现象描述

用户已实机复测 B6-2b 产物（PID 43244，复测后进程仍在）。复测后全盘查找
`.winwin_logs.json` 与 `logs/runtime.log` 依然不存在——连续两轮复测零 catcher
上报。`dart analyze` 零问题，工作区干净。继续推进 B6-2 收尾。

## 2. 根因

全库裸 `Icon(Icons.)` 经 B6-2a（4 处）、B6-2b（34 处）后剩余 29 处：
`login_page.dart` 9 处（含 `InputDecoration.prefix` 槽位，属关键登录链路，
风险高于普通展示位）+ 散布 15 文件的 20 处展示位（空态图、导航项、
`leading`、画廊按钮、条款列表等）。15 文件全部已导入 `app_icons.dart`，
且同文件内早已混用 `AppIcon`，槽位均为 `Widget`，可批量转换；
login 单独留 B6-2d 做登录链路专项验证。

## 3. 修复方案

B6-2c：15 文件 20 处 `Icon(Icons.*)` → `AppIcon(Icons.*)`，零字形变化：

- bangumi_detail 806、live/view 435、follow/view 270、pgc/view 602（登录态空态）、
  history 295、toview 332/342、download 207、msg_feed 212（`icon:` 槽位）
- gallery_viewer 474（`icon:`）、fav_page 208/533/543（空态+播放列表）
- session_settings 158（`leading:` 红色举报行）、dynamics/view 1915（Row 尾裸 Icon）、
  search_panel 720（空态裸 Icon）、member_space 3377（Error 裸 Icon）、
  user_agreement 154/160/166（`const List<_Clause>` 内裸 Icon，外层 const 保留，
  仅部件名替换）

替换写法：`const Icon(Icons.` → `AppIcon(Icons.`、
` Icon(Icons.` → ` AppIcon(Icons.`（前导空格限定，避免误伤 `AppIcon(` 内子串）。

## 4. 验证与回滚

- 快照：改前干净，快照指针沿用 `0c449584`；本轮 15 文件各 1~3 行，
  回滚可按文件 `git checkout -- <file>`。
- 精确核验：`Icon(Icons.` 排除 `AppIcon(` 后残留仅 login 9 处；
  `AppAppIcon` 串改检查为零；`dart analyze` 零问题。
- `flutter build windows --debug` 通过（30.8s）；
  `flutter build windows --release` 通过（77.6s）。
  双编译前已结束残留 `winwin.exe`。
- 提交推送：`ec96a8b`（代码+复盘+进度表同批）。

## 5. 遗留与踩坑

- 遗留：裸 `Icon(Icons.)` 仅剩 `login_page.dart` 9 处 → B6-2d（含 prefix 槽位，
  需登录链路专项复测）；之后是 `AppIcon(Icons.)` 直参字形归一 + 语义方法缺口。
- 踩坑：`Select-String -Path lib` 不递归，目录级内容搜索必须用
  `Get-ChildItem -Recurse | Select-String`；且 `Icon(Icons.` 正则会同时命中
  `AppIcon(Icons.`，残留统计必须加 `Where-Object -notmatch 'AppIcon\('` 过滤。

## 6. 总结

B6-2c 收敛 15 文件 20 处散点裸 Icon，全库裸 `Icon(Icons.)` 由 29 → 9（仅 login），
静态检查与双分支构建全过；login 高风险 9 处留 B6-2d 单独处理。

## 7. 测试验证指导（本轮产物）

- **空态页**：搜索无结果页（放大镜空态）、会员空间加载失败页（云朵空态）、
  历史/稍后再看空态、收藏空态、下载空态——图标应与上一版一致。
- **导航与行**：直播/关注/放映厅未登录态图标、私信设置举报行红色图标、
  番剧详情播放按钮、动态商品袋图标、画廊左箭头——逐一目视，无红叉缺图。
- **条款页**：设置→关于→开源协议，三条款图标（爱心/天平/虫子）正常。
- **预期**：零视觉变化；任何图标缺失/错位/布局挤压即回退。
- **日志**：复测后复查 `.winwin_logs.json` 是否生成，新增条目发回分析。
