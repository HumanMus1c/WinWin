# WinWin

> 小破站桌面端 ( ゜- ゜)つロ 干杯~

WinWin 是使用 **Flutter** 构建的 Windows 桌面应用，**以 PiliPlus 为基础进行桌面化改造与改进而来**：替换了播放内核（fvp / libmdk），并持续改进视觉设计——当前前端已切换为 **flutter_miuix（Miuix）** 组件体系，支持 Material 3 与 Miuix 双风格热切换（后续将以 Miuix 为主要维护风格，并可能引入液态玻璃风格）。功能覆盖视频 / 番剧 / 直播播放、弹幕、评论互动、动态与消息、搜索与个人空间。

项目早期在界面设计上参考过 **BiliPai** 的前端设计，并移植了其中若干可跨平台的策略与交互逻辑；接口细节参考 **bilibili-API-collect** 的公开文档。完整来源与致谢见下。

---

## 一、上游项目与致谢（来源声明）

### 1.1 主要来源

**（1）PiliPlus — 基础与直接复用来源（主）**
[bggRGjQaUbCoE/PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)

WinWin 是 PiliPlus 在 Windows 桌面方向的改进分支，大量基础模块以其对应实现为蓝本复用/裁剪（源码文件头均保留「移植自 / 对标 / 参考」注释）。主要涉及：

- 基础设施：`constants`、`http/api`、`id_utils`（BV↔AV 等）、`wbi_sign`（WBI 签名）、`danmaku_utils` 等；
- 网络层：统一请求封装（buvid 激活 / UA / 超时对齐）、登录、视频、直播、动态等 11+ HTTP 模块；
- 账户与存储：账号管理 / CookieJar / 登录守卫、Hive 存储键与偏好骨架；
- 弹幕：段弹幕 HTTP、弹幕屏蔽规则同步；
- 播放器：播放控制与交互以 PiliPlus 方案为骨架（**内核替换为 fvp/mdk，缘由见第二章**）、选流、音量归一（loudnorm）；
- 界面：`MainLayout` 三槽位布局、`SimpleScaffold`、视频卡片体系、`PBadge`、`NetworkImgLayer`、下拉刷新、瀑布流与滚动联动设计；
- 错误文案与重试：`error_msg`、`dio_error_message`。

**（2）BiliPai — 早期前端设计参考 + 策略与逻辑移植（Kotlin → Dart）**
[jay3-yy/BiliPai](https://github.com/jay3-yy/BiliPai)

BiliPai 为 Android 原生（Kotlin + Jetpack Compose）项目。WinWin 早期在界面设计上参考其前端设计；其后端策略与纯逻辑被逐条移植为 Dart（文件头注明 `Ported from BiliPai`）：

- 播放策略：`VideoLoadPolicy`、`NetworkFallbackPolicy`、`PlaybackHeartbeatPolicy`、`StreamSelectionPolicy`、`PlaybackSpeedPolicy`；
- 内容安全与体验：评论反诈、首页推荐匿名化、弹幕指令 / 类型过滤 / 关键词过滤策略；
- 空降助手：`SponsorBlockUseCase` 移植；
- 下载策略族与 JSON 规则插件引擎（路线图中）；
- 其它：重试策略、PlayUrl 缓存、B 站 URL 解析、Feed 分页合并、启动任务编排、配置加载守卫、日志收集与脱敏设计等。

> 注：当前前端实现已切换为 flutter_miuix（Miuix）体系，BiliPai 主要作为策略与早期设计参考存在。

**（3）bilibili-API-collect — API 文档参考**
[SocialSisterYi/bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)（CC BY-NC 4.0）

- WBI 签名、APP 签名、视频流地址、点赞 / 投币 / 弹幕 / 评论等接口文档；
- `lib/grpc/` 的 gRPC 协议定义参照其 `grpc_api` 整理生成；
- 注：该仓库已于 2026 年初归档停更。谨向其作者与长期贡献者致谢。

**（4）BilibiliSponsorBlock — 空降助手数据与 API**
[hanydd/BilibiliSponsorBlock](https://github.com/hanydd/BilibiliSponsorBlock)（WinWin 经 bsbsb.top 镜像查询段落数据）。

**（5）flutter_miuix — Miuix 风格组件库**
[ChuxinNeko/flutter_miuix](https://github.com/ChuxinNeko/flutter_miuix)（Apache-2.0，由 [compose-miuix-ui/miuix](https://github.com/compose-miuix-ui/miuix) 移植）。

**（6）fvp / libmdk — 播放内核**
[wang-bin/fvp](https://github.com/wang-bin/fvp)（BSD-3-Clause）基于 [wang-bin/mdk-sdk](https://github.com/wang-bin/mdk-sdk)（libmdk，对开源项目与 Flutter 用户免费）：硬件解码、D3D11 渲染、多格式支持。

### 1.2 上游的上游（一并致敬）

- PiliPlus 的上游：[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)、[guozhigq/pilipala](https://github.com/guozhigq/pilipala)；
- BiliPai 参考生态（Jetpack Compose、Media3、DanmakuRenderEngine 等）与本项目同源的 PiliPlus / bilibili-API-collect / BilibiliSponsorBlock，均一并致谢。

### 1.3 上游许可证一览

| 上游项目 | 许可证 | 与 WinWin 的关系 |
| --- | --- | --- |
| PiliPlus | GNU GPL v3.0 | 基础与直接复用来源（主） |
| BiliPai | GNU GPL v3.0 | 策略移植 + 早期设计参考 |
| PiliPala / PiliPalaX | GNU GPL v3.0 | PiliPlus 的上游 |
| bilibili-API-collect | CC BY-NC 4.0（文档） | 接口文档参考 |
| flutter_miuix | Apache License 2.0 | 运行时组件库 |
| fvp | BSD-3-Clause | 播放插件 |
| libmdk | 自定义许可（开源 / Flutter 免费） | 播放内核 |

### 1.4 使用的开源库（直接依赖）

| 类别 | 依赖 | 用途 |
| --- | --- | --- |
| 框架 | [Flutter](https://flutter.dev) | 应用框架 |
| 状态 / 路由 | [get](https://pub.dev/packages/get) | 状态管理与路由 |
| 网络 | [dio](https://pub.dev/packages/dio) · [http2](https://pub.dev/packages/http2) · [cookie_jar](https://pub.dev/packages/cookie_jar) · [web_socket_channel](https://pub.dev/packages/web_socket_channel) · [brotli](https://pub.dev/packages/brotli) · [protobuf](https://pub.dev/packages/protobuf) | HTTP / HTTP2 / Cookie / 直播弹幕 WebSocket / 压缩解包 / 协议序列化 |
| 播放 | [fvp](https://pub.dev/packages/fvp) | DASH 播放 / 硬件解码 |
| 存储 | [hive_ce](https://pub.dev/packages/hive_ce) | 本地键值存储 |
| UI | [material_ui](https://pub.dev/packages/material_ui) · [cupertino_ui](https://pub.dev/packages/cupertino_ui) · [flutter_miuix](https://pub.dev/packages/flutter_miuix) · [flutter_staggered_grid_view](https://pub.dev/packages/flutter_staggered_grid_view) · [cached_network_image_ce](https://pub.dev/packages/cached_network_image_ce) | 双风格组件 / 瀑布流 / 图片缓存 |
| 桌面集成 | [window_manager](https://pub.dev/packages/window_manager) · [screen_retriever](https://pub.dev/packages/screen_retriever) | 窗口管理 / 屏幕信息 |
| 登录 | [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview) | 风控验证 WebView |
| 日志 | [logger](https://pub.dev/packages/logger) · [catcher_2](https://pub.dev/packages/catcher_2) | 结构化日志 / 崩溃捕获 |
| 工具 | [crypto](https://pub.dev/packages/crypto) · [uuid](https://pub.dev/packages/uuid) · [fixnum](https://pub.dev/packages/fixnum) · [intl](https://pub.dev/packages/intl) · [collection](https://pub.dev/packages/collection) · [file_picker](https://pub.dev/packages/file_picker) | 加密 / ID / 数值 / 国际化 / 文件选择 |

> 版本以 `pubspec.yaml` 为准；各库版权归原作者所有，使用请遵循其各自许可证。

---

## 二、与上游的差异、优缺点

### 2.1 主要差异

- **来源与定位**：以 PiliPlus 为基础进行 Windows 桌面化改造；早期界面设计参考 BiliPai 前端设计，现前端实现已切换为 flutter_miuix（Miuix）体系；
- **播放内核替换**：media_kit（libmpv 系）→ **fvp / libmdk**。缘由：media_kit 捆绑的 libmpv 二进制停更于 2023-09、Dart 层维护迟滞；fvp/mdk 维护活跃（按月发版）、默认硬件解码、**原生外挂音轨**（`setMedia(url, audio)`）对 B 站 DASH 分离音视频流支持更干净，且趁播放器代码量小时迁移成本最低；
- **平台适配**：针对桌面适配侧边栏导航、窗口标题栏沉浸、伪 PiP、键鼠交互；
- **UI 体系（演进中）**：Material 3 与 Miuix 双风格运行时热切换（历史 iOS 风格已单向并入 Miuix）；后续规划以 Miuix 为主要维护风格（逐步移除 Material 3），并可能引入液态玻璃（Liquid Glass）风格；
- **网络实现**：以 HTTP 方案替代完整 gRPC 栈（桌面单用户场景收益有限）；
- **BiliPai 策略吸收**：将其 Kotlin 策略与交互逻辑逐条移植为 Dart 并做桌面化边界修复；
- **自有修复积累**：凭据加密落盘（上游为明文 Hive）、Seek 音画同步、缓冲冻结死锁、播放期内存增长、弱网容错、音频响度对齐、历史续播、番剧片尾跳过、风控弹窗承载、崩溃报告处理等（详见 `docs/` 复盘文档）。

### 2.2 优点

- 桌面端体验完整：播放 / 弹幕 / 评论 / 动态 / 直播 / 消息 / 搜索 / 收藏 / 历史 / 稍后再看 / 番剧 / 专栏；
- 双风格热切换 + 设计 Token 化，自适应组件集中分发、可测试（后续聚焦 Miuix）；
- 大量边界问题经过系统性复盘修复，稳定性与容错较强；
- 登录方式齐全：扫码 / 短信 / 密码 / Cookie 导入（含风控验证窗口）。

### 2.3 不足与局限

- 仅面向 Windows，其他平台未适配；
- 下载系统与插件系统尚未完成（路线图中）；
- 部分增强未完成：超分（Anime4K / FSR）、SponsorBlock 提交 / 投票等；
- 依赖系统 WebView2 与显卡解码能力，个别环境需实测验证；
- 相对上游裁剪了桌面场景不需要的模块（如部分 gRPC / 移动端专属实现）。

---

## 三、构建

```bash
# 环境：Windows 10/11 + Flutter 3.44+ (stable) + Visual Studio 2022（Desktop development with C++）
flutter pub get
flutter build windows --release    # 产物：build\windows\x64\runner\Release\
```

## 四、免责声明

- 本项目为个人兴趣开发，仅供学习与技术交流，请于下载后 24 小时内删除；
- 所调用接口均从公开渠道收集，不提供任何破解内容；
- 内容版权归原权利方所有，请勿滥用本项目；
- 如涉及版权或权益问题，请联系删除。

## 五、许可证

GNU GPL-3.0（与上游保持一致；完整文本见 [LICENSE](LICENSE)）。
