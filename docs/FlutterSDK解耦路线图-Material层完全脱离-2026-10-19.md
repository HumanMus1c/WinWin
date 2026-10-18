# Flutter SDK 解耦路线图 — 完全脱离 Material 层（分析 + 方案）

- 日期：2026-10-19
- 起点 HEAD：`7f53cc1`（Phase 5 下载系统批次2 复盘回填后）
- 快照：`refs/snapshots/latest` = `7f53cc19b6436b44f2ed67a18623b5dff59e0506`（工作树干净，快照=HEAD）
- 文档类型：**路线图 / 分析文档（不含任何代码改动）**，待 CVO 确认口径与路径后按 §7 分期实施
- **进展（2026-10-19）**：§8 **Q2/Q5 已由 CVO 拍板**（82 字形走"Miuix 矢量为主、Cupertino 为辅"，现在实施）；**Phase A 已落地**——见 `docs/PhaseA-图标载体退役复盘-2026-10-19.md`。Q1（口径）/Q3（fork flutter_miuix）/Q4（B7 门槛改语义）仍待确认。
- 关联：`docs/B7封板-material_ui库级退役收官-2026-10-18.md`、`docs/MD3库级退役进度追踪-2026-10-07.md`、`test/theme/material_ui_absence_test.dart`
- 结论来源：本仓库源码/SDK/依赖缓存静态取证 + 线上官方议题与 pub.dev（见 §9）

---

## 0. 目标澄清（必读，先一句话结论）

**一句话结论**：Flutter 应用在物理上**无法"删除 Flutter SDK"**——`package:flutter/widgets`、`package:flutter/rendering`、`dart:ui` 是应用运行时本体，删除即应用不存在。

任务真正可达成、且与项目既有 B7 方向一致的可执行靶标是：**彻底脱离 Flutter SDK 内置的 Material 设计子系统**，即三条不变量：

- （a）**不再打包/渲染 SDK 的 `MaterialIcons` 字体**（由 `pubspec.yaml` 的 `uses-material-design: true` 捆绑）；
- （b）**不再经由应用自建桥接向 SDK `package:flutter/material.dart` 索取任何类型**（当前桥面 = `lib/core/shell/miuix_compat.dart`）；
- （c）**不再依赖 SDK 传递引入的 `material_color_utilities`**。

> 本文件全程按此口径分析；"这是否就是你要的靶标"列为待确认项 **§8-Q1**。

---

## 1. 三问结论速览

| # | 问题 | 结论 | 可行性 | 主要成本 |
| --- | --- | --- | --- | --- |
| **1** | 82 个 `MaterialIcons` 字形 → Cupertino 同/近义替换 | **可做**，但**首选不是 Cupertino，而是 Miuix 矢量**（Cupertino 语义覆盖不全，82 项中约 8 项无理想对应） | 高 | 扩 `_miuixVectorByGlyph` 映射 + 改 `AppIcons` 语义方法 + 摘 `uses-material-design` |
| **2** | flutter_miuix 能否不桥接 `flutter/material.dart`？ | **应用侧"完全不再桥接"不可行**（会破 MiuixTextField）；但当前桥面极小（1 文件）。根治法 = fork flutter_miuix 替换其 69 文件 material 依赖 | 中 | 选项分级见 §3.2；根治成本高 |
| **3** | Flutter 是否将淘汰 `material_color_utilities`？有无替代库？ | **无官方淘汰计划**；它是"色彩引擎库"非设计系统组件，随 Material 一并拆分进 `material_ui` 生态。**且 flutter_miuix 自身直接依赖它 → 只要 flutter_miuix 在就不可独立移除**。市面"替代库"（flex_seed_scheme / m3e_color_scheme）**仍是它的封装，不是替代** | 低（当前） | 仅当同时脱离 Material 且 flutter_miuix 改自研配色后才有意义 |

---

## 2. 子题一：82 个 `MaterialIcons` 字形替换

### 2.1 现状与范围（硬事实）

- **唯一消费面** = `lib/theme/app_glyphs.g.dart`（82 个 `static const IconData xxx = IconData(0x…, fontFamily: 'MaterialIcons')`，由 `tools/app_glyphs_import.py` 生成）。
- **引用面** = `lib/theme/app_icons.dart`（`grep -c AppGlyphs` = **105** 处；全 `lib` 合计 **108** 处）。其中：
  - **~70 处**为 `AppIcons.*` 语义方法直接 `return AppGlyphs.x;`（迁移主战场，见下表"用途"列）；
  - **22 处**已在 `_miuixVectorByGlyph` 映射表内（`AppGlyphs.x → MiuixIcons.extended/os4.byName(...)`），**运行时已走 Miuix 矢量、不渲染 MaterialIcons 字体**。
- **全 `lib` 内 SDK `Icons.` 直接使用 = 0**（已核，排除 `AppIcons/MiuixIcons/CupertinoIcons`）。
- 项目**未使用** `MiuixDatePicker` / `MiuixNumberPicker`（已核）。
- 因此：**`uses-material-design: true` 的运行时收益，仅剩本项目这 82 个字形的实际渲染点**。

> ⚠️ 关键细节：`AppIcon`（`lib/theme/app_icons.dart`）渲染时**优先**走 `miuixVectorForGlyph(icon)`；命中 Miuix 矢量 → `MiuixIcon(vector:)`（**纯矢量、无需字体**）；未命中 → 回退 `Icon(icon, fontFamily:'MaterialIcons')`（**需要 SDK 字体**）。故"去掉 MaterialIcons 字体"= 把这 82 个**全部**覆盖到矢量或 Cupertino 字体。

### 2.2 两条替换路径与建议

| 路径 | 字形来源 | 是否 SDK 资产 | 覆盖度 | 何时用 |
| --- | --- | --- | --- | --- |
| **A. CupertinoIcons** | `cupertino_icons: ^1.0.8`（`fontPackage: 'cupertino_icons'`，字体 `CupertinoIcons.ttf`） | **否**（独立包资产，非 SDK） | 1322 个字形，但**语义覆盖不全**（见下表约 8 项无理想对应） | 有干净语义对应时 |
| **B. Miuix 矢量** | flutter_miuix `MiuixIcons.extended`（156×5 字重）+ `.os4`（176×5）+ 项目自建矢量 | **否**（`MiuixVectorIcon` 为矢量路径，**不需要任何字体**） | 极高（数百矢量图标 + 已有的 BDC/Web/BiliSite 路径表） | **默认首选** |

**建议：B 为主、A 为辅。** 理由：（1）Cupertino 语义缺口需靠自建补，等于回到 B；（2）`AppIcon` 已内建"矢量优先"解析链，扩映射表即自动生效，改动面最小；（3）矢量无需字体，是"完全脱离字体依赖"最彻底的形态。

### 2.3 全量 82 行映射表

> 列说明：**用途**取自 `app_icons.dart` 的语义方法引用点；**Cupertino 候选**已逐一核对 `cupertino_ui-1.0.0/lib/src/icons.dart` 名称表（1322 个），未核到者标"—（无）"；**Miuix 矢量**列"已映射"指 `_miuixVectorByGlyph` 现存条目。

| # | 常量 | 码点 | 用途（引用点） | Cupertino 候选 | Miuix 矢量现状 | 备注 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | `account_box` | 0xe042 | 账号输入字段 `accountField()` | `person_crop_circle` | 未映射 | |
| 2 | `alternate_email_rounded` | 0xf55f | @我 `atMe()` | `at_badge_plus` | 未映射 | |
| 3 | `arrow_downward` | 0xe097 | 排序·降序 `sortArrow(descending)` | `arrow_down` | 未映射 | |
| 4 | `arrow_drop_down` | 0xe098 | 下拉箭头 `countryArrow()/dropdownArrow()` | `chevron_down` | 未映射 | |
| 5 | `arrow_upward` | 0xe0a0 | 排序·升序 `sortArrow` | `arrow_up` | 未映射 | |
| 6 | `article_outlined` | 0xee93 | 运行日志 `runLog()` | `doc_text` | 未映射 | |
| 7 | `aspect_ratio` | 0xe0a3 | 画面比例 `aspectRatio()` | `rectangle` | 未映射 | |
| 8 | `balance_outlined` | 0xf05c1 | 免责声明 `clauseDisclaimer()` | `exclamationmark_bubble` | 未映射 | 天平语义缺失，用提示语替代 |
| 9 | `bolt` | 0xe0ee | 徽章闪电 `badgeBolt()` | `bolt_fill` | 未映射 | |
| 10 | `bolt_rounded` | 0xf5ca | 官方/认证闪电 | `bolt_fill` | 未映射 | |
| 11 | `brightness_6_outlined` | 0xeef9 | 主题模式 `themeMode()` | `circle_lefthalf_fill` | **已映射 `theme`** | |
| 12 | `broken_image_outlined` | 0xeeff | 图片损坏 `imageBroken()` | `exclamationmark_triangle` | 未映射 | |
| 13 | `bug_report_outlined` | 0xef04 | 反馈 `clauseFeedback()` | `exclamationmark_bubble` | 未映射 | |
| 14 | `campaign_outlined` | 0xef27 | 系统通知 `sysNotice()` | `bell` | 未映射 | 喇叭无对应，用铃铛 |
| 15 | `check_circle` | 0xe159 | 选中态 `selectState(selected)` | `checkmark_circle_fill` | 未映射 | |
| 16 | `chevron_left` | 0xe15e | 图集上一张 `galleryPrev()` | `chevron_left` | **已映射 `chevronBackward`** | |
| 17 | `cloud_off_outlined` | 0xef61 | 离线/加载失败 `spaceOffline()/loadFailed()` | `wifi_slash` | 未映射 | 无"云断线"；icloud 族在 cupertino_ui 不存在 |
| 18 | `cloud_outlined` | 0xef62 | CDN 节点 `cdnNode()` | `cloud` | 未映射 | |
| 19 | `code` | 0xe176 | 关于代码 `aboutCode()` | `chevron_left_slash_chevron_right` | 未映射 | |
| 20 | `comment_outlined` | 0xef6e | 弹幕输入 `danmakuInput()` | `chat_bubble_text` | **已映射 `os4.messages`** | |
| 21 | `contrast` | 0xf04d8 | 纯黑模式 `pureBlack()` | `circle_lefthalf_fill` | 未映射 | |
| 22 | `cookie_outlined` | 0xf05d3 | Cookie 字段 `cookieField()` | —（无 cookie 语义） | 未映射 | **建议自建矢量**（曲奇） |
| 23 | `delete_sweep` | 0xe1bc | 清空全部 `clearAll()` | `trash_slash` | 未映射 | |
| 24 | `donut_large_rounded` | 0xf6d5 | 托盘图标 `trayIcon()` | —（无 donut） | 未映射 | **建议自建矢量** |
| 25 | `download_done_outlined` | 0xeff0 | 下载完成 `downloadEmpty()` | `checkmark_circle` | **已映射 `download`** | |
| 26 | `download_for_offline_outlined` | 0xeff1 | 离线空 `offlineEmpty()` | `arrow_down_to_line` | **已映射** | |
| 27 | `equalizer_outlined` | 0xf024 | 响度均衡 `loudnessEqualizer()` | `slider_horizontal_3` | **已映射 `tune`** | |
| 28 | `explore_outlined` | 0xf037 | 应用推荐 `appRecommend()` | `compass` | 未映射 | |
| 29 | `extension_outlined` | 0xf03f | 扩展设置 `extraSetting()` | `square_grid_2x2` | 未映射 | |
| 30 | `file_upload_outlined` | 0xf05d | 字体导入 `fontImport()` | `arrow_up_to_line` | **已映射 `uploadCloud`** | |
| 31 | `flash_on_outlined` | 0xf080 | 硬件加速 `hardwareAccel()` | `bolt_fill` | 未映射 | |
| 32 | `folder_off_outlined` | 0xf0601 | 文件夹空 `folderEmpty()` | `folder` | **已映射 `folder`** | |
| 33 | `font_download_outlined` | 0xf096 | 应用字体 `appFont()` | `textformat` | 未映射 | |
| 34 | `hd_outlined` | 0xf0e1 | 1080P `p1080()` | `tv` | 未映射 | |
| 35 | `heart_broken_outlined` | 0xf060f | 心碎 `heartBroken()` | `heart_slash` | 未映射 | |
| 36 | `history_toggle_off` | 0xe316 | 暂停历史/历史空 `pauseHistory()/historyEmpty()` | `clock` | **已映射 `recent`** | |
| 37 | `http` | 0xe32d | HTTP2 `http2()` | `arrow_up_arrow_down` | 未映射 | 无 http 语义 |
| 38 | `keyboard_outlined` | 0xf144 | 键盘控制 `keyboardControl()` | `keyboard` | 未映射 | |
| 39 | `local_fire_department` | 0xe392 | 热度 `hotness()` | `flame_fill` | 未映射 | |
| 40 | `login` | 0xe3b2 | 登录提交 `loginSubmit()` | `arrow_right_square` | 未映射 | |
| 41 | `logout` | 0xe3b3 | 退出登录 `logout()` | `arrow_right` | 未映射 | rect.portrait+arrow 命名在 cupertino_ui 不存在 |
| 42 | `memory` | 0xe3db | 解码模式 `decodeMode()` | `square_grid_2x2` | 未映射 | 无 CPU 语义，**建议自建** |
| 43 | `merge` | 0xf053b | 合并弹幕 `mergeDanmaku()` | `arrow_merge` | **已映射 `merge`** | |
| 44 | `minimize` | 0xe3e8 | 最小化到托盘 `minimizeToTray()` | `minus` | **已映射 `remove`** | |
| 45 | `motion_photos_auto_outlined` | 0xf1eb | 自动播放 `autoplay()` | `play_circle` | 未映射 | |
| 46 | `music_video_outlined` | 0xf1fd | 默认音质 `defaultAudioQuality()` | `music_note` | **已映射 `music`** | |
| 47 | `notifications_none_rounded` | 0xf0027 | 空通知 `emptyNotice()` | `bell` | **已映射 `os4.notifications`** | |
| 48 | `offline_bolt` | 0xe454 | 官方闪电 `officialBolt()` | `bolt` | 未映射 | |
| 49 | `password` | 0xe47a | 密码字段 `passwordField()` | `lock_fill` | 未映射 | |
| 50 | `photo_camera_outlined` | 0xf29b | 截图按钮 `screenshotButton()` | `camera` | **已映射 `screenCapture`** | |
| 51 | `play_arrow_rounded` | 0xf00a0 | 播放 `playEpisode()/livePlay()` | `play_fill` | **已映射 `play`** | |
| 52 | `play_circle_outline` | 0xe4ce | 播放圈 `playCircleOutline()` | `play_circle` | 未映射 | |
| 53 | `playlist_play` | 0xe4d4 | 播放全部 `playAll()` | `music_note_list` | **已映射 `playlist`** | |
| 54 | `qr_code_2` | 0xe4f6 | 二维码占位 `qrPlaceholder()` | `qrcode` | **已映射 `scan`** | |
| 55 | `radio_button_unchecked` | 0xe504 | 未选中 `selectState` | `circle` | 未映射 | |
| 56 | `repeat` | 0xe51f | 循环 `loopMode(round:true)` | `repeat` | 未映射 | |
| 57 | `report_outlined` | 0xf30f | 举报 `reportAbuse()` | `exclamationmark_bubble` | **已映射 `report`** | |
| 58 | `restore` | 0xe534 | 字体恢复 `fontRestore()` | `arrow_counterclockwise` | 未映射 | |
| 59 | `search_off` | 0xe568 | 搜索空 `searchEmpty()` | `search` | **已映射 `search`** | |
| 60 | `security` | 0xe569 | SSL 绕过 `sslBypass()` | `checkmark_shield` | 未映射 | |
| 61 | `sensors` | 0xe576 | 传感器开 `sensorsState(active)` | `personalhotspot` | 未映射 | antenna_radiowaves 在 cupertino_ui 不存在 |
| 62 | `sensors_off` | 0xe577 | 传感器关 | `wifi_slash` | 未映射 | |
| 63 | `sensors_off_outlined` | 0xf359 | 循环关 `loopMode(round:false)` | `repeat_1` | 未映射 | |
| 64 | `sentiment_satisfied_alt_outlined` | 0xf35d | 表情入口 `emoteEntry()` | —（无 emoji 语义） | 未映射 | **建议自建矢量**（笑脸） |
| 65 | `shopping_bag_outlined` | 0xf37d | 商品入口 `goodsEntry()` | `bag` | 未映射 | |
| 66 | `slideshow` | 0xe5c0 | 演示模式 `demoMode()` | `rectangle_stack` | 未映射 | |
| 67 | `sms_outlined` | 0xf3ad | 短信验证码 `smsCodeField()` | `chat_bubble_text` | **已映射 `os4.messages`** | |
| 68 | `source_outlined` | 0xf3b7 | 开源 `openSource()` | `chevron_left_slash_chevron_right` | 未映射 | |
| 69 | `storage` | 0xe609 | 缓冲大小 `bufferSize()` | `archivebox` | 未映射 | |
| 70 | `style_outlined` | 0xf3f6 | 外观 `appearance()` | `paintbrush_fill` | **已映射 `theme`** | |
| 71 | `subscriptions_outlined` | 0xf3fb | 关注空 `followEmpty()` | `rectangle_stack` | 未映射 | |
| 72 | `subtitles_outlined` | 0xf3fd | 弹幕数 `danmakuCount()` | `captions_bubble` | 未映射 | 与 BDC 同码点截胡记录见 `app_icons.dart:783` |
| 73 | `swap_horiz` | 0xe625 | 切换账号 `switchAccount()` | `arrow_left_arrow_right` | **已映射 `replace`** | |
| 74 | `text_fields` | 0xe649 | 字号 `fontSize()` | `textformat` | 未映射 | |
| 75 | `touch_app_outlined` | 0xf453 | 触摸动作 `touchAction()` | `hand_point_left` | 未映射 | |
| 76 | `verified_user_outlined` | 0xf47d | 认证用户 `verifiedUser()` | `checkmark_seal` | 未映射 | |
| 77 | `video_settings_outlined` | 0xf489 | 视频设置 `videoSetting()` | `videocam` | 未映射 | |
| 78 | `videocam_off_outlined` | 0xf48b | 视频关 `videoOff()` | `videocam` | 未映射 | videocam_slash 在 cupertino_ui 不存在 |
| 79 | `volunteer_activism_outlined` | 0xf4a9 | 开源致谢 `clauseOpenSource()` | `hand_raised` | 未映射 | hands.sparkles 在 cupertino_ui 不存在 |
| 80 | `vpn_key` | 0xe6c7 | 系统代理 `systemProxy()` | —（`key` 不存在） | 未映射 | **建议自建矢量**（钥匙） |
| 81 | `window` | 0xe6f0 | 原生标题栏 `nativeTitleBar()` | `uiwindow_split_2x1` | 未映射 | |
| 82 | `zoom_in_outlined` | 0xf4dc | UI 缩放 `uiScale()` | —（magnifyingglass 不存在） | 未映射 | **建议自建矢量**（放大镜），或用 `search` 近似 |

**统计**：**已映射 Miuix 矢量 = 22 项**（#11/16/20/25/26/27/30/32/36/43/44/46/47/50/51/53/54/57/59/67/70/73）；**待迁移 = 60 项**；其中 Cupertino **无理想对应、建议自建矢量 ≈ 8 项**（#22 cookie、#24 donut、#42 memory、#64 笑脸、#80 vpn_key、#82 放大镜，及 #19/#68 代码类语义较弱）。

### 2.4 迁移步骤（建议，按 §2.2 走 B 主）

1. **扩映射**：把表中"未映射"60 项逐步补进 `_miuixVectorByGlyph`（优先用 `MiuixIcons.extended/os4.byName(...)`；确无者自建矢量路径，纳入项目既有 `app_icons_art.dart` 体系）。
2. **改语义方法**：`lib/theme/app_icons.dart` §9/§10/§11 的 `AppGlyphs.x` 直参返回值改为 Miuix 矢量（保持 `AppIcons.*` 方法**不可 const** 的既有约定）。
3. **收敛生成物**：`lib/theme/app_glyphs.g.dart` **软删除** → `scratch/deleted-2026-10-19/`；同步停用/归档 `tools/app_glyphs_import.py`。
4. **摘 flag**：`pubspec.yaml` 移除 `uses-material-design: true`（须确认 flutter_miuix 的 datepicker 分支在项目内**永不触达**）。
5. **加门槛测试**：`lib/**` 零 `AppGlyphs.` 字面引用 + `pubspec.yaml` 无 `uses-material-design` 真值，锁定终态防回退。

---

## 3. 子题二：flutter_miuix 与 SDK `material.dart` 的耦合分析

### 3.1 量化取证（`flutter_miuix-1.3.0`）

| 观测项 | 值 | 说明 |
| --- | --- | --- |
| import `package:flutter/material.dart` 的文件 | **69 / 69**（`lib/` 全量） | 结构性依赖 |
| 库自有组件 | `MiuixScaffold` / `MiuixIconButton` / `MiuixTooltip` / `MiuixTextField` / `MiuixIcon` … | 组件**全部自研**，非套壳 SDK |
| SDK 组件**实例化** | `Scaffold(` / `IconButton(` / `TextField(` / `Tooltip(` / `Material(` / `ThemeData(` = **全 0** | 无直接复用 SDK 控件 |
| SDK material **符号** | `Colors.` **100**、`Theme.of(` **98**、`ColorScheme` **28**、`MaterialType` **6**、`MaterialLocalizations` **1** | 依赖集中在**类型/主题常量** |
| 自身 pubspec 依赖 | `material_color_utilities ^0.13.0`、`dynamic_color ^1.9.0`、`uses-material-design: true` | 自带 MCU + 动态色 |
| 库内 SDK `Icons.` | **3**（`miuix_date_picker.dart`：`chevron_left`/`chevron_right`/`arrow_drop_down`） | 仅日期选择器 |
| 库内 `material_ui` 引用 | **0** | 尚未随官方拆分迁移 |

> 结论方向：flutter_miuix 是**深度依赖 SDK material 的"类型与主题"**（`Colors`/`Theme.of`/`ColorScheme`），但**不依赖 SDK 的"控件"**。

### 3.2 能否"不再桥接 `flutter/material.dart`"？——分级选项

| 选项 | 做法 | 可行性 | 评价 |
| --- | --- | --- | --- |
| **1** | 应用侧直接拆掉 `MiuixCompat` 桥 | **不可行** | 破 `MiuixTextField`（SDK TextField 需 Material 祖先 + ThemeData + MaterialLocalizations，release 缺失→空断言崩溃渲染大灰块，历史坑已记录） |
| **2（务实）** | 保留桥，但桥面从 SDK `material.dart` 迁到 `material_ui` 包 | **可行**，但**与 B7 门槛冲突**（§6） | 需等官方 Nov 2026 弃用窗口 |
| **3（根治）** | **fork flutter_miuix**，把 69 文件的 `package:flutter/material.dart` 替换为项目自建最小 shim（`Colors`/`Theme.of`/`ColorScheme`/`MaterialType`/`IconTheme`/`DefaultTextStyle` 子集） | **可行但成本高** | 一次性工程量：69 文件 + 需镜像 100+98+28 符号面；维护分叉 |
| **4（现状结论）** | 维持现状 | **当前可接受** | 应用侧桥面**仅 1 文件**（`miuix_compat.dart`）+ 本地化 delegates；`lib` 除 compat 外 **0** 直接依赖 |

**子题二分结论**：**应用侧"完全不再桥接 SDK material"不可行**（选项 1 违背 flutter_miuix 的硬需求）；**根治法只有选项 3（fork）**，属中高成本立项。当前真实"必须解决"的问题不是"拆桥"，而是**"SDK material 被官方弃用后，flutter_miuix 的材料来源改为 `material_ui` 包，届时与 B7 门槛冲突"**——该冲突的处置见 §6。

### 3.3 上游 Miuix 分析

上游 `compose-miuix-ui/miuix` 为 **Kotlin / Compose Multiplatform** 实现（Android/桌面 Compose），**与 Flutter 无直接代码复用关系**；`flutter_miuix` 是第三方（ChuxinNeko）做的独立 1:1 移植。其"依赖 SDK material"属**移植期复用选择**，并非上游强制。故"完全使用上游 Miuix 以摆脱 material"在 Flutter 技术栈上**不成立**——上游根本不产出 Flutter 代码。

---

## 4. 子题三：`material_color_utilities` 前景与替代

### 4.1 定位

`material_color_utilities`（MCU）= Google 的 **HCT 色彩科学 + 动态配色算法引擎**（`DynamicScheme`/`MaterialDynamicColors`/`CorePalette` 等），是**算法库**，不是设计系统/UI 组件库。

### 4.2 依赖链（双向取证）

- **SDK 侧**：`D:\flutter\packages\flutter\pubspec.yaml` 钉 `material_color_utilities: 0.13.0`；仅被 `lib/src/material/color_scheme.dart`（`ColorScheme.fromSeed` 内部 `MaterialDynamicColors.*`）消费。
- **项目侧**：`pubspec.lock` 记为 `dependency: transitive`（应用代码不直接用）。
- **🔑 关键**：**flutter_miuix 自身 pubspec 直接依赖 `material_color_utilities: ^0.13.0`**（用于从 seed 色生成整套米 UI 调色板，对应 Kotlin 侧 `com.materialkolor`）。
  → **只要 flutter_miuix 在依赖树中，MCU 就在；应用无法"独立移除"它。**

### 4.3 是否淘汰 / 替代

- **无官方弃用计划**（检索未发现任何 deprecation 声明）。它随 Material 设计系统一并**拆分进 `material_ui` 包生态**（是 `material_ui` 的依赖，而非被删）。
- **"替代库"实为封装**：`flex_seed_scheme`、`m3e_color_scheme` 等**底层仍是 MCU**（它们的 API 就是 MCU 的高级封装），**不构成替代**。唯一真替代 = 本项目自研 HCT/调色板。

**子题三结论**：MCU **不可独立去除**；其"去留"完全绑定于两件事——(i) 是否彻底脱离 Material（§2/§3），(ii) flutter_miuix 是否改用自研配色。当前**建议保留、不投入**（收益极小）。

---

## 5. 与项目现状的交叉核对（硬事实汇总）

1. `lib` 内 SDK `Icons.` 直接使用 = **0**；SDK material 导入 **仅 `lib/core/shell/miuix_compat.dart` 1 个文件**。
2. 项目**未使用** `MiuixDatePicker` / `MiuixNumberPicker` → flutter_miuix 内 3 处 SDK `Icons.`（date picker）在**运行时不触达**。
3. 即便如此，`uses-material-design: true` 仍会**捆绑 SDK MaterialIcons 字体**进产物 → **目标 (a) 的唯一实质阻塞 = 本项目 82 个字形**（§2）。
4. `material_ui_absence_test.dart`（B7 门槛）锁定"应用零 `material_ui` 导入 + pubspec 零声明"——与官方"回归 `material_ui`"方向存在**潜在冲突**（§6）。

---

## 6. 战略冲突：B7 门槛 ⟷ 官方弃用路线

- **B7 封板**（2026-10-18）：应用侧 `material_ui` 归零，**门槛测试锁定**（`test/theme/material_ui_absence_test.dart`）。
- **Flutter 官方方向**：SDK 内 Material/Cupertino → 拆为独立包 **`material_ui` / `cupertino_ui`**（1.0.0 随 Flutter 3.47 发布，为 SDK 代码的零行为副本）；贡献于 **2026-04-07 冻结**；**2026-11 stable 正式标记弃用**，其后删除；`flutter_localizations` 的 Material/Cupertino delegates 亦迁入这两包（`GlobalMaterialLocalizations.delegates` 现打包三件套以兼容）。
- **冲突点**：**未来 flutter_miuix 的更新几乎必然改为依赖 `material_ui`**（否则其 69 文件在 SDK material 删除后无法编译）。届时本项目面临二选一：
  - **(a)** 改 B7 门槛语义为"**应用侧零 Material 消费**"（`lib` 除 compat 桥外零 material 导入），允许依赖树出现过渡期的 `material_ui`；
  - **(b)** **锁定 flutter_miuix 版本 / fork** 掉其 material 依赖（= §3.2 选项 3）。
- **建议**：把 B7 门槛**升级语义**为"应用侧零 Material 消费"，而非"全仓零 `material_ui` 字样"。理由：门槛若锁死"全仓零 material_ui"，将与官方前进方向正面冲突，且会锁住 flutter_miuix 升级能力。

---

## 7. 分期路线图（建议 · 待 §8 确认后执行）

| 阶段 | 内容 | 风险 | 验收 |
| --- | --- | --- | --- |
| **A**（低，本主题第一批） | 82 字形 → Miuix 矢量/Cupertino；停 `uses-material-design` | 低 | `lib` 零 `AppGlyphs.`；产物零 MaterialIcons 渲染；`dart analyze` 0 错 0 警；debug+release 双编译；门槛测试绿 |
| **B**（中） | 桥面治理：`miuix_compat.dart` 依赖面文档化 + 探针测试；**PoC fork flutter_miuix** 评估选项 3 | 中 | PoC 明确 69 文件 shim 可行性与工作量 |
| **C**（前瞻） | 随官方 **2026-11 弃用窗口**决策 §6 的 (a)/(b)；同步 `flutter_localizations` → `material_ui`/`cupertino_ui` delegates | 中 | 门槛语义定稿；依赖树可编译 |
| **D**（探索，低优先） | 配色引擎自研化以移除 MCU | 低 | 仅在 A/B/C 完成后评估 |

> 注：本主题为**文档-only**，按 dev-workflow-spec §2 **豁免双编译**；但 §7-A 若落地为代码批，则按 §2 正常走双编译 + §1 快照 + §3 提交推送 + §4 复盘。

---

## 8. 待 CVO 确认的开放问题

- **Q1 口径确认**：目标是否为"脱离 Material 子系统"（§0 的三条不变量），而非字面"删除 Flutter SDK"？
- **Q2 82 字形首选路径**：B（Miuix 矢量）为主 / A（Cupertino）为主 / 混合？（本文**建议 B 主、A 辅**）
- **Q3 是否接受 fork flutter_miuix**（§3.2 选项 3）作为根治手段立项？
- **Q4 B7 门槛是否改语义**为"应用侧零 Material 消费"（§6）？
- **Q5 是否现在就动 Phase A**，还是遵守"方案定稿前不改动项目任何文件"（`user-preferences.md` 项目冻结约定）？

---

## 9. 参考与来源

**本仓库 / 本机（静态取证）**
- `pubspec.yaml`（无 `material_ui`；`cupertino_icons ^1.0.8` / `cupertino_ui 1.0.0` / `flutter_miuix 1.3.0`；`uses-material-design: true`）
- `pubspec.lock`（`material_color_utilities 0.13.0` transitive）
- `lib/theme/app_glyphs.g.dart`（82 字形）、`lib/theme/app_icons.dart`（105 引用 + `_miuixVectorByGlyph`）
- `lib/core/shell/miuix_compat.dart`（SDK material 桥）、`test/theme/material_ui_absence_test.dart`（B7 门槛）
- `C:\Users\SilverT1ger\AppData\Local\Pub\Cache\hosted\pub.dev\flutter_miuix-1.3.0`（69 文件 material 依赖；pubspec `material_color_utilities`/`dynamic_color`；datepicker 3 处 `Icons.`）
- `…\cupertino_ui-1.0.0\lib\src\icons.dart`（1322 个 CupertinoIcons 名称表，本表逐一核对）
- `D:\flutter\packages\flutter\pubspec.yaml`（L19 `material_color_utilities 0.13.0`）、`lib/src/material/color_scheme.dart`（L14 import MCU）

**线上**
- flutter/flutter 议题 **#101479**（Material/Cupertino 拆包总跟踪）、**#172932**（relocation）、**#172942**（deprecate/remove）、**#184093**（删除时间线）
- pub.dev `material_ui` / `cupertino_ui` **1.0.0**（随 Flutter 3.47，SDK 代码零行为副本）；迁移 `dart fix --apply --code=migrate_design_widgets`
- pub.dev `m3e_color_scheme`（迁移说明：v1.0.0 起改用独立 `material_ui` 包；仍依赖 MCU）
- api.flutter.dev `ColorScheme.fromSeed`（内部 `MaterialDynamicColors`，即 MCU）

---

*本文件为分析/方案稿，未改动任何代码。实施须经 CVO 对 §8 的确认后，按 §7 分期执行。*