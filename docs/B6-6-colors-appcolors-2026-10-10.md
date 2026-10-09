# B6-6 复盘：Colors → AppColors 常量口（绝对色收敛）— 2026-10-10

## 1. 现象描述

B6-5 后 `lib` 内仍有 **438 处**（56 文件，大小写敏感口径）对 material_ui
`Colors` 类常量的直接引用：`white` 236 / `black` 90 / `transparent` 49 /
`red` 19 / `grey` 11 / 其余彩色与白黑透明度族（white60~24、black87~26）约 33。
B7 摘除依赖前须移出 Material Colors。

## 2. 根因与设计取舍

- 438 处中约 **86%** 是 white/black/transparent 及透明度族——它们本质是
  **媒体绝对色**（覆盖在视频/图片之上的文字、遮罩、徽标，固定白黑、
  不随主题），机械映射到主题 Token 反而是错的；其余彩色（red/amber/orange/
  grey…）含语义倾向，但逐点语义映射（红→`cs.error` 等）需要设计走查与
  视觉回归，不宜与"依赖收敛"混在一批。
- 结论：建 **项目常量口 `AppColors`**（取值与 Flutter `Colors` 对应项
  **逐位一致**，由 SDK `colors.dart` 解析生成）→ 全量机械替换 →
  **零视觉变化**；语义精修列为后续独立批次（单点收口后，精修只改调用点）。

## 3. 修复方案

- 新增 `lib/theme/app_colors.dart`：`abstract final class AppColors`，35 个
  const（transparent / black / white + white60·54·38·30·24 + black87·54·38·26
  + red / redAccent / grey / grey600 / orange / orange700·800 / orangeAccent
  / amber / amber600·700 / amberAccent / pink / pink600 / green / greenAccent
  / blue / blue600）——白黑透明度族与所需主色/shadé 全部由 SDK 解析取得。
- 脚本全量替换 **443 处 / 56 文件**：词边界防护（不误伤 `baseColors.` /
  `AppColors` 类子串）、注释行跳过、`Colors.amber.shade600` → `AppColors.amber600`
  形态归一、每文件自动补 `import 'package:winwin/theme/app_colors.dart';`。

## 4. 验证与回滚

- 快照：`7196065b`（`refs/snapshots/latest`）。
- `dart analyze` 零问题（首轮 73：10 个白黑透明度族 getter 缺失——并入库后
  归零；另修正一次文件头编码事故）；
  `flutter test` **164/164 全绿**；
  双分支构建通过（kernel 01:58:51 / app.so 02:00:18），构建后已自启 Release
  （PID 18152）。
- 残留复核：lib 内真实 `Colors.`（词边界）**0 处**；`AppColors` 覆盖 56 文件；
  闸门指标维持 **133**（Colors 不动 import 计数，摘 import 属 B7）。
- 提交推送：`5291b68`（代码+复盘+进度表同批，已推 `origin/main`）。

## 5. 遗留与踩坑

- 遗留：**B6 收官复测与阶段汇总**；语义精修（红→error 等）与 B7
  （摘 import + "残留=0"门槛测试）为后续批次。
- 踩坑：① PowerShell 统计默认**大小写不敏感**——`\bColors\.` 会混入
  `colors.xxx` 令牌导致计数虚高（一度误记 761/775；真实 438）；
  ② `Colors.` 会以子串命中 `AppColors.` / `baseColors.` / `LevelColors.` /
  `muiColors.` ——必须词边界防护（`(?<![\w$.])`）；
  ③ PS 5.1 `Get-Content` 默认 ANSI 读无 BOM 的 UTF-8 中文文件会**二次编码
  毁坏**内容——涉及无 BOM 中文文件的读写须走 .NET API 或重新生成。

## 6. 总结

438 处 `Colors.` 引用全部收敛到项目 `AppColors` 常量口（56 文件
+487/−431，另新增 35 项常量文件），**逐位零视觉变化**；B6-6 完成，
B6（控件与色字清扫）全线收官。

## 7. 测试验证指导（本轮产物）

- **全局观感巡查**（预期逐位零变化）：播放器面板/弹幕/直播（白黑透明度族
  密集区）、视频卡与徽标、红色语义按钮（下载/删除等）、番剧/动态/成员页彩色点缀。
- **三主题抽查**：浅色/深色/纯黑各页抽查（绝对色本不随主题，重点看
  亮度对比是否与上一版一致）。
- **日志**：复测后核对 `D:\Documents\.winwin_logs.json` 与
  `D:\Documents\logs\runtime.log` 有无新增条目。
