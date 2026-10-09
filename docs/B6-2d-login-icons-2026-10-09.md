# B6-2d 复盘：login 9 处 Icon→AppIcon 统一（2026-10-09）

## 1. 现象描述

用户已实机复测 B6-2c 产物。复测后拉取全部日志面：`.sandbox/*.log` 仍停留在
2026-08-16（监控脚本旧落盘，无 fresh 内容）；全盘查找 `.winwin_logs.json`
（catcher NDJSON 崩溃落盘）与 `logs/runtime.log` 均不存在——连续三轮复测
零 catcher 上报、无崩溃。`dart analyze` 零问题，工作区干净。B6-2 仅剩
`login_page.dart` 9 处裸 `Icon(Icons.)`，收官即走 B6-2d。

## 2. 根因

B6-2a（4 处）→ B6-2b（34 处）→ B6-2c（20 处）后，全库裸 `Icon(Icons.)`
仅剩 login 单文件 9 处：账号/密码/验证码/ Cookie 四个 `AppTextField prefix`
槽位（4 处）+ 三个登录按钮行内图标（3 处）+ 区号下拉箭头（1 处）+
扫码失败占位图（1 处）。`login_page.dart` 头部早已导入 `app_icons.dart`
（第 17 行），同文件内已混用 `AppIcon(AppIcons.call/send/refresh)`，
`AppTextField.prefix` 类型为 `Widget?`，全部槽位零风险；`AppIcon` 为 const
构造，`const Row`/`const SizedBox` 上下文内的隐式 const 不被破坏。

## 3. 修复方案

B6-2d：单文件 9 处 `Icon(Icons.*)` → `AppIcon(Icons.*)`，零字形变化：

- 324 `account_box`、333 `password`、647 `sms_outlined`、995 `cookie_outlined`
 （`prefix:` 槽位，仅部件名替换，`const` 保留）
- 360/676/1012 三处 `Icons.login`（按钮行内，`replaceAll` 一次收敛，
  仍满足外层 `const Row` 隐式 const）
- 634 `arrow_drop_down`（区号行，`const` 保留）、845 `qr_code_2`
 （扫码 errorBuilder 占位图）

替换写法：`const Icon(Icons.` → `const AppIcon(Icons.`、
`Icon(Icons.login` → `AppIcon(Icons.login`（replaceAll）、
`child: Icon(Icons.` → `child: AppIcon(Icons.`。

## 4. 验证与回滚

- 快照：改前工作区干净，快照指针沿用 `0c449584`；本轮单文件 9 行，
  回滚 `git checkout -- lib/pages/login/login_page.dart` 即可。
- 精确核验：`rg --pcre2 "(?<![A-Za-z])Icon\(Icons\." lib` 零命中
  （`AppIcon(` 子串已用 PCRE2 反查排除）；`AppAppIcon` 串改检查为零；
  `git diff --stat` 为 1 文件 +9/−9；`dart analyze` 零问题。
- `flutter build windows --debug` 通过（29.0s）；
  `flutter build windows --release` 通过（77.7s）。
  双编译前已结束残留 `winwin.exe`（防 WebView2Loader.dll 锁）。
- 提交推送：`（本提交，推送后由 docs 订正提交回填）`。

## 5. 遗留与踩坑

- 遗留：裸 `Icon(Icons.)` 全库归零，B6-2 裸→AppIcon 阶段收官；
  下一步是 `AppIcon(Icons.)` 直参 71 处字形归一 + `AppIcons` 语义方法缺口
  （account/password/login/sms/qr/cookie 等登录语义尚无专属方法）。
- 踩坑：`rg "Icon\(Icons\."` 会同时命中 `AppIcon(Icons.`（71 处虚高），
  残留统计必须用 PCRE2 `(?<![A-Za-z])Icon\(Icons\.`；
  PowerShell 5.1 无 `head`，输出截断用 `Select-Object -First/-Last`。

## 6. 总结

B6-2d 收敛 login 单文件 9 处高风险裸 Icon（prefix 槽位+登录链路），
全库裸 `Icon(Icons.)` 由 9 → 0，B6-2 阶段闭环；静态检查与双分支构建全过。

## 7. 测试验证指导（本轮产物）

- **登录页四 Tab**：密码登录（账号/密码前缀图标+登录按钮图标）、
  短信登录（区号箭头+验证码前缀+获取验证码按钮+登录按钮）、
  扫码登录（断网/过期占位二维码图标+刷新按钮）、Cookie 登录
  （Cookie 前缀+登录按钮）——逐一目视，图标应与上一版一致，零视觉变化。
- **输入行为**：各输入框聚焦/输入/显密切换正常，无布局挤压、无红屏；
  prefix 图标不应挤占输入区（AppIcon 已做 widthFactor 收缩对齐）。
- **预期**：任何图标缺失/错位/输入区被挤没即回退。
- **日志**：复测后复查 `.winwin_logs.json` 是否生成，新增条目发回分析。
