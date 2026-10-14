import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';

import 'app_icons_art.dart';
import 'app_icons_bdc.g.dart';
import 'app_icons_bili.g.dart';
import 'app_icons_builtin.g.dart';
import 'app_icons_official.g.dart';
import 'app_icons_web.g.dart';
import 'package:winwin/ui/components/app_tooltip.dart';

/// 全局语义图标中心（阶段5d-L4-2 单轨化：原 `*Of(style)` 与 `*(context)` 双分发
/// 已收敛为无参静态方法，字形恒定 Miuix / Apple 图标集；字形→Miuix 矢量映射
/// 由 [AppIcon] 统一处理）。
abstract final class AppIcons {
  // ---------------------------------------------------------------------------
  // 1. 全局返回与导航
  // ---------------------------------------------------------------------------

  /// 全局返回图标（M3：向左箭头；Miuix：精致向左返回箭头）。

  static IconData back() => CupertinoIcons.chevron_back;

  /// 顶层导航 — 首页

  static IconData home({bool selected = false}) => selected ? CupertinoIcons.house_fill : CupertinoIcons.house;

  /// 顶层导航 — 动态

  static IconData dynamic({bool selected = false}) => selected ? CupertinoIcons.bell_fill : CupertinoIcons.bell;

  /// 顶层导航 — 历史

  static IconData history({bool selected = false}) => selected ? CupertinoIcons.clock_fill : CupertinoIcons.clock;

  /// 顶层导航 — 消息

  static IconData whisper({bool selected = false}) => selected
            ? CupertinoIcons.chat_bubble_2_fill
            : CupertinoIcons.chat_bubble_2;

  /// 顶层导航 — 我的

  static IconData profile({bool selected = false}) => selected ? CupertinoIcons.person_fill : CupertinoIcons.person;

  // ---------------------------------------------------------------------------
  // 2. 视频 / 动态 核心互动操作行
  // ---------------------------------------------------------------------------

  /// 点赞

  static IconData like({bool active = false}) => active
            ? CupertinoIcons.hand_thumbsup_fill
            : CupertinoIcons.hand_thumbsup;

  /// 点踩

  static IconData dislike({bool active = false}) => active
            ? CupertinoIcons.hand_thumbsdown_fill
            : CupertinoIcons.hand_thumbsdown;

  /// 投币

  static IconData coin({bool active = false}) => active
            ? CupertinoIcons.money_dollar_circle_fill
            : CupertinoIcons.money_dollar_circle;

  /// 收藏

  static IconData favorite({bool active = false}) => active ? CupertinoIcons.star_fill : CupertinoIcons.star;

  /// 分享

  static IconData share() => CupertinoIcons.share;

  /// 稍后再看

  static IconData watchLater({bool active = false}) => CupertinoIcons.time;

  // ---------------------------------------------------------------------------
  // 3. 评论区互动操作
  // ---------------------------------------------------------------------------

  /// 回复

  static IconData reply() => CupertinoIcons.reply;

  /// 动态转发

  static IconData repost() => CupertinoIcons.arrow_2_circlepath;

  /// 评论（动态/文章/直播间入口）

  static IconData comment() => CupertinoIcons.chat_bubble_text;

  /// 展开更多回复 / 下拉指示

  static IconData expandMore() => CupertinoIcons.chevron_down;

  // ---------------------------------------------------------------------------
  // 4. 通用交互控件
  // ---------------------------------------------------------------------------

  /// 搜索

  static IconData search() => CupertinoIcons.search;

  /// 清除 / 取消

  static IconData clear() => CupertinoIcons.clear;

  /// 更多选项（垂直三点 / 横向省略）

  static IconData more() => CupertinoIcons.ellipsis;

  /// 设置

  static IconData settings() => CupertinoIcons.settings;

  /// 刷新

  static IconData refresh() => CupertinoIcons.refresh;

  /// 下载 / 缓存

  static IconData download() => CupertinoIcons.arrow_down_to_line;

  /// 删除 / 清理

  static IconData delete() => CupertinoIcons.delete;

  /// 排序 / 筛选

  static IconData filter() => CupertinoIcons.slider_horizontal_3;

  /// 成功 / 勾选

  static IconData check() => CupertinoIcons.checkmark;

  /// 前进 / 展开箭头

  static IconData chevronForward() => CupertinoIcons.chevron_forward;

  /// 向上折叠箭头

  static IconData chevronUp() => CupertinoIcons.chevron_up;

  /// 向下展开箭头

  static IconData chevronDown() => CupertinoIcons.chevron_down;

  /// 播放

  static IconData play({bool active = false}) => active ? CupertinoIcons.play_fill : CupertinoIcons.play;

  /// 暂停

  static IconData pause({bool active = false}) => active ? CupertinoIcons.pause_fill : CupertinoIcons.pause;

  /// 重播

  static IconData replay() => CupertinoIcons.restart;

  /// 快进

  static IconData fastForward() => CupertinoIcons.forward_fill;

  /// 快退

  static IconData fastRewind() => CupertinoIcons.backward_fill;

  /// 锁定

  static IconData lock() => CupertinoIcons.lock_fill;

  /// 解锁 / 锁外框

  static IconData lockOutline() => CupertinoIcons.lock;

  /// 音量 — 大

  static IconData volumeUp() => CupertinoIcons.speaker_3_fill;

  /// 音量 — 小

  static IconData volumeDown() => CupertinoIcons.speaker_1_fill;

  /// 静音

  static IconData volumeOff() => CupertinoIcons.speaker_slash_fill;

  /// 全屏 / 退出全屏

  static IconData fullscreen({bool active = false}) => active ? CupertinoIcons.fullscreen_exit : CupertinoIcons.fullscreen;

  /// 网页全屏（应用内铺满）

  static IconData inAppFullscreen({bool active = false}) => active ? CupertinoIcons.square_fill : CupertinoIcons.square;

  /// 画中画

  static IconData pip() => CupertinoIcons.tv;

  /// 弹幕开关

  static IconData danmaku({bool active = false}) => active
            ? CupertinoIcons.chat_bubble_fill
            : CupertinoIcons.chat_bubble;

  /// 发送弹幕

  static IconData sendDanmaku() => CupertinoIcons.bubble_left;

  /// 弹幕设置 / 调优

  static IconData danmakuTune() => CupertinoIcons.slider_horizontal_3;

  /// 字幕

  static IconData subtitle({bool active = false}) => active
            ? CupertinoIcons.captions_bubble_fill
            : CupertinoIcons.captions_bubble;

  /// 章节

  static IconData chapter({bool active = false}) => active ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark;

  /// 更多选项（M3: 竖向三点; Miuix: 横向省略三点）

  static IconData moreOptions() => CupertinoIcons.ellipsis;

  /// 置顶

  static IconData pin({bool active = false}) => active ? CupertinoIcons.pin_slash_fill : CupertinoIcons.pin_fill;

  /// 免打扰 / 静音通知

  static IconData notificationsOff({bool active = false}) => active ? CupertinoIcons.bell_fill : CupertinoIcons.bell_slash;

  /// 单选框

  static IconData radio({required bool selected}) => selected
            ? CupertinoIcons.check_mark_circled_solid
            : CupertinoIcons.circle;

  /// 屏蔽 / 封禁

  static IconData block() => CupertinoIcons.slash_circle;

  /// 错误 / 告警提示

  static IconData error() => CupertinoIcons.exclamationmark_circle;

  /// 视频播放数 / 观看数

  static IconData viewCount() => CupertinoIcons.play_circle;

  /// 视频弹幕数（载体字形 → B 站官网"弹幕数"矢量，L5-8）
  static IconData danmakuCount() => Icons.subtitles_outlined;

  /// 视频时长

  static IconData duration() => CupertinoIcons.clock;

  /// 日历 / 发布日期

  static IconData calendar() => CupertinoIcons.calendar;

  // ---------------------------------------------------------------------------
  // 8. 阶段5e-L5-2 新增语义（B 类字形归一：裸 Icons 直参收敛）
  // ---------------------------------------------------------------------------

  /// 文件夹 / 收藏夹
  static IconData folder() => CupertinoIcons.folder;

  /// 复制
  static IconData copy() => CupertinoIcons.doc_on_doc;

  /// 链接
  static IconData link() => CupertinoIcons.link;

  /// 信息 / 说明
  static IconData info() => CupertinoIcons.info;

  /// 发送
  static IconData send() => CupertinoIcons.paperplane;

  /// 图片 / 相册
  static IconData image() => CupertinoIcons.photo;

  /// 用户群组
  static IconData people() => CupertinoIcons.person_2;

  /// 邮件 / 私信
  static IconData mail() => CupertinoIcons.mail;

  /// 电话 / 客服
  static IconData call() => CupertinoIcons.phone;

  /// 定位 / 位置
  static IconData location() => CupertinoIcons.location;

  /// 定时 / 计时
  static IconData timer() => CupertinoIcons.timer;

  /// 录制中（实心圆点）
  static IconData recording() => CupertinoIcons.circle_fill;

  /// 撤销
  static IconData undo() => CupertinoIcons.arrow_uturn_left;

  /// 主题 / 调色
  static IconData palette() => CupertinoIcons.paintbrush;

  /// 新增 / 关注（追加语义）
  static IconData add() => CupertinoIcons.add;

  /// 浏览 / 阅读数（眼睛）
  static IconData eye() => CupertinoIcons.eye;

  // ---------------------------------------------------------------------------
  // 9. 设置面语义（B6-2e：直参收敛——原 `AppIcon(Icons.xxx)` 的 1:1 语义封装，
  //    字形暂与 M3 一致（零视觉变化），后续美术替换只改此处一处）。
  // ---------------------------------------------------------------------------

  /// 外观设置入口（主题/字重/缩放）
  static IconData appearance() => Icons.style_outlined;

  /// 播放交互手势（双击/触摸操作）
  static IconData touchAction() => Icons.touch_app_outlined;

  /// 音视频设置入口（画质/音质/硬解/缓冲）
  static IconData videoSetting() => Icons.video_settings_outlined;

  /// 其它设置入口（网络/代理/日志）
  static IconData extraSetting() => Icons.extension_outlined;

  /// 关于页 — 项目说明
  static IconData aboutCode() => Icons.code;

  /// 关于页 — 开源协议
  static IconData openSource() => Icons.source_outlined;

  /// 应用字体选择
  static IconData appFont() => Icons.font_download_outlined;

  /// 主题模式（跟随系统/浅色/深色）
  static IconData themeMode() => Icons.brightness_6_outlined;

  /// 纯黑主题（OLED 省电）
  static IconData pureBlack() => Icons.contrast;

  /// 字体大小缩放
  static IconData fontSize() => Icons.text_fields;

  /// 界面缩放
  static IconData uiScale() => Icons.zoom_in_outlined;

  /// 系统原生标题栏开关
  static IconData nativeTitleBar() => Icons.window;

  /// 托盘图标显隐
  static IconData trayIcon() => Icons.donut_large_rounded;

  /// 退出时最小化到托盘
  static IconData minimizeToTray() => Icons.minimize;

  /// 字体文件导入
  static IconData fontImport() => Icons.file_upload_outlined;

  /// 恢复默认字体
  static IconData fontRestore() => Icons.restore;

  /// 开启硬解
  static IconData hardwareAccel() => Icons.flash_on_outlined;

  /// 免登录 1080P
  static IconData p1080() => Icons.hd_outlined;

  /// 默认音质
  static IconData defaultAudioQuality() => Icons.music_video_outlined;

  /// 音频响度均衡
  static IconData loudnessEqualizer() => Icons.equalizer_outlined;

  /// CDN 服务节点
  static IconData cdnNode() => Icons.cloud_outlined;

  /// 硬件解码模式
  static IconData decodeMode() => Icons.memory;

  /// 播放缓冲大小
  static IconData bufferSize() => Icons.storage;

  /// 进入详情页自动播放
  static IconData autoplay() => Icons.motion_photos_auto_outlined;

  /// 全屏截图按钮显隐
  static IconData screenshotButton() => Icons.photo_camera_outlined;

  /// 键盘控制（空格/方向键）
  static IconData keyboardControl() => Icons.keyboard_outlined;

  /// 启用 HTTP/2
  static IconData http2() => Icons.http;

  /// 系统代理开关
  static IconData systemProxy() => Icons.vpn_key;

  /// 禁用 SSL 证书验证
  static IconData sslBypass() => Icons.security;

  /// APP 端推荐流
  static IconData appRecommend() => Icons.explore_outlined;

  /// 合并相同弹幕
  static IconData mergeDanmaku() => Icons.merge;

  /// 运行日志开关
  static IconData runLog() => Icons.article_outlined;

  /// 暂停观看历史
  static IconData pauseHistory() => Icons.history_toggle_off;

  /// 演示模式
  static IconData demoMode() => Icons.slideshow;

  // ---------------------------------------------------------------------------
  // 10. 通用语义收敛（B6-2f：login/profile/whisper/空态等 35 处直参，
  //    字形暂与 M3 一致，零视觉变化）。
  // ---------------------------------------------------------------------------

  /// 登录提交按钮（各未登录态 FilledButton.icon 共用）
  static IconData loginSubmit() => Icons.login;

  /// 账号输入框前缀
  static IconData accountField() => Icons.account_box;

  /// 密码输入框前缀
  static IconData passwordField() => Icons.password;

  /// 短信验证码输入框前缀
  static IconData smsCodeField() => Icons.sms_outlined;

  /// 扫码失败占位图
  static IconData qrPlaceholder() => Icons.qr_code_2;

  /// Cookie 输入框前缀
  static IconData cookieField() => Icons.cookie_outlined;

  /// 区号下拉小箭头
  static IconData countryArrow() => Icons.arrow_drop_down;

  /// 切换账号
  static IconData switchAccount() => Icons.swap_horiz;

  /// 退出登录
  static IconData logout() => Icons.logout;

  /// 离线缓存空态
  static IconData offlineEmpty() => Icons.download_for_offline_outlined;

  /// 历史空态
  static IconData historyEmpty() => Icons.history_toggle_off;

  /// 协议条款 — 开源免费
  static IconData clauseOpenSource() => Icons.volunteer_activism_outlined;

  /// 协议条款 — 免责声明
  static IconData clauseDisclaimer() => Icons.balance_outlined;

  /// 协议条款 — 问题反馈
  static IconData clauseFeedback() => Icons.bug_report_outlined;

  /// 消息中心 — @我的
  static IconData atMe() => Icons.alternate_email_rounded;

  /// 消息中心 — 系统通知
  static IconData sysNotice() => Icons.campaign_outlined;

  /// 消息流空态（免打扰铃铛）
  static IconData emptyNotice() => Icons.notifications_none_rounded;

  /// 举报行（红色）
  static IconData reportAbuse() => Icons.report_outlined;

  /// 收藏夹空态
  static IconData folderEmpty() => Icons.folder_off_outlined;

  /// 全部播放（播放列表）
  static IconData playAll() => Icons.playlist_play;

  /// 清空（删除横扫）
  static IconData clearAll() => Icons.delete_sweep;

  /// 搜索无结果空态
  static IconData searchEmpty() => Icons.search_off;

  /// 空间页加载失败
  static IconData spaceOffline() => Icons.cloud_off_outlined;

  /// 番剧播放主按钮
  static IconData playEpisode() => Icons.play_arrow_rounded;

  /// 下载空态
  static IconData downloadEmpty() => Icons.download_done_outlined;

  /// 动态商品入口
  static IconData goodsEntry() => Icons.shopping_bag_outlined;

  /// 画廊上一张
  static IconData galleryPrev() => Icons.chevron_left;

  // ---------------------------------------------------------------------------
  // 11. 图标欠账收敛（B7-c2：B7 期间漏网与新场景直参——`Icon(` 部件替换的
  //    配套语义，字形暂与现状一致，零字形变化）。
  // ---------------------------------------------------------------------------

  /// 内容加载失败空态（云断开）
  static IconData loadFailed() => Icons.cloud_off_outlined;

  /// 关注流空态（订阅）
  static IconData followEmpty() => Icons.subscriptions_outlined;

  /// 表情面板入口
  static IconData emoteEntry() => Icons.sentiment_satisfied_alt_outlined;

  /// 演示遮罩播放占位（描边圆）
  static IconData playCircleOutline() => Icons.play_circle_outline;

  /// 演示单选（选中实心圆勾 / 未选中圆框）
  static IconData singleChoice({required bool selected}) =>
      selected ? Icons.check_circle : Icons.radio_button_unchecked;

  /// 直播开始播放（大箭头）
  static IconData livePlay() => Icons.play_arrow_rounded;

  /// 直播发弹幕入口
  static IconData danmakuInput() => Icons.comment_outlined;

  /// 下拉小箭头
  static IconData dropdownArrow() => Icons.arrow_drop_down;

  /// 网页全屏（比例框）
  static IconData aspectRatio() => Icons.aspect_ratio;

  /// 直播离线指示（轮播中 / 已下播）
  static IconData liveOffline({required bool round}) =>
      round ? Icons.repeat : Icons.sensors_off_outlined;

  /// 直播热度（火焰）
  static IconData hotness() => Icons.local_fire_department;

  /// 空间认证入口（闪电）
  static IconData officialBolt() => Icons.offline_bolt;

  /// 认证标识（盾牌用户）
  static IconData verifiedUser() => Icons.verified_user_outlined;

  /// 排序方向箭头（倒序向下 / 正序向上）
  static IconData sortArrow({required bool descending}) =>
      descending ? Icons.arrow_downward : Icons.arrow_upward;

  /// 取消追番悬停（破心）
  static IconData heartBroken() => Icons.heart_broken_outlined;

  /// 无视频信号（摄像机划叉）
  static IconData videoOff() => Icons.videocam_off_outlined;

  /// 直播状态指示（直播中 / 已结束）
  static IconData liveIndicator({required bool active}) =>
      active ? Icons.sensors : Icons.sensors_off;

  /// 图片损坏占位
  static IconData imageBroken() => Icons.broken_image_outlined;

  /// 认证徽章（闪电小字）
  static IconData badgeBolt() => Icons.bolt;
}

/// 自适应图标部件：Miuix 风格下将具备 Miuix 矢量对应的字形升级为
/// flutter_miuix 原生矢量图标（[MiuixIcon] + [MiuixVectorIcon]）；
/// 其余情况（M3 风格 / 无对应字形 / 带 [shadows] 的媒体叠加场景）回退 [Icon]。
///
/// 调用模式与 [Icon] 兼容：`AppIcon(AppIcons.xxx(), size: 20, color: c)`。
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.shadows,
    this.semanticLabel,
  });

  final IconData icon;
  final double? size;
  final Color? color;
  final List<Shadow>? shadows;

  /// 无障碍语义标签（对齐 material [Icon] 同名参数；矢量路径等效包裹 [Semantics]）。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    // 阶段5d-L3：字形→Miuix 矢量映射恒启用（原 miuix 风格门控收敛移除）。
    // 颜色/尺寸优先级：显式参数 > IconTheme（按钮/AppBar/自定义 IconTheme 等注入）
    // > MiuixContentColor 链 / 24 默认——修复矢量路径不读 IconTheme 导致的
    // 「返回按钮不反色」「尺寸失配」问题。
    if (shadows == null || shadows!.isEmpty) {
      final vector = miuixVectorForGlyph(icon);
      if (vector != null) {
        final iconTheme = IconTheme.of(context);
        // 修复R2b/R2c：向 MiuixIcon 传递**宽松约束**并防止自身膨胀。
        // - 紧约束父级（52×52 Container）会撑满内部 SizedBox，FittedBox 将矢量
        //   放大铺满 → 以 Center 居中解决；
        // - 但裸 Center 在宽松槽位（如 InputDecoration.prefixIcon：minWidth 48 +
        //   max 全宽）会贪心膨胀到整行宽（挤没输入区）→ 以 widthFactor/heightFactor
        //   = 1 收缩为「图标尺寸（下限受槽位约束）」，与 Icon 的占位行为对齐。
        final iconWidget = Center(
          widthFactor: 1,
          heightFactor: 1,
          child: MiuixIcon(
            vector: vector,
            size: size ?? iconTheme.size ?? 24,
            tint: color ?? iconTheme.color,
          ),
        );
        return semanticLabel == null
            ? iconWidget
            : Semantics(label: semanticLabel, child: iconWidget);
      }
    }
    return Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
      shadows: shadows,
    );
  }
}

/// Cupertino 字形 → Miuix 矢量映射（仅覆盖 Miuix 图标集具备的通用语义；
/// 播放器专属语义（弹幕/字幕/画质/倍速/画中画等）无对应字形，保留
/// Cupertino——完整覆盖清单见 `docs/flutter_miuix阶段3c-图标体系复盘`）。
///
/// 注：映射键为 [AppIcons] miuix 分支返回的 Cupertino 字形；M3 字形与未列出
/// 的字形由 [AppIcon] 直接回退 [Icon]。
final Map<IconData, MiuixVectorIcon> _miuixVectorByGlyph = {
  CupertinoIcons.chevron_back: MiuixIcons.extended.byName('chevronBackward')!,
  // B7-c3 补丁：home/recent/messages 在 Miuix 素材集中仅有实心版（渲染实测
  // 墨迹占比 27-32%，线条参照 os4 notifications ≈11%）——未选中（线条）字形
  // 不映射、回退 Cupertino 线条字形；填充字形保留实心矢量映射。
  CupertinoIcons.house_fill: MiuixIcons.extended.byName('home')!,
  CupertinoIcons.clock_fill: MiuixIcons.extended.byName('recent')!,
  CupertinoIcons.chat_bubble_2_fill: MiuixIcons.extended.byName('messages')!,
  CupertinoIcons.star: MiuixIcons.extended.byName('favorites')!,
  CupertinoIcons.star_fill: MiuixIcons.extended.byName('favoritesFill')!,
  CupertinoIcons.share: MiuixIcons.extended.byName('share')!,
  CupertinoIcons.reply: MiuixIcons.extended.byName('reply')!,
  CupertinoIcons.chevron_down: MiuixIcons.extended.byName('expandMore')!,
  CupertinoIcons.chevron_up: MiuixIcons.extended.byName('expandLess')!,
  CupertinoIcons.chevron_forward:
      MiuixIcons.extended.byName('chevronForward')!,
  CupertinoIcons.search: MiuixIcons.extended.byName('search')!,
  // 关闭/清除语义使用基础集 close（描边 X，符合弹窗关闭直觉）。
  CupertinoIcons.clear: MiuixIcons.basic.close,
  CupertinoIcons.ellipsis: MiuixIcons.extended.byName('more')!,
  CupertinoIcons.settings: MiuixIcons.extended.byName('settings')!,
  CupertinoIcons.refresh: MiuixIcons.extended.byName('refresh')!,
  CupertinoIcons.arrow_down_to_line: MiuixIcons.extended.byName('download')!,
  CupertinoIcons.delete: MiuixIcons.extended.byName('delete')!,
  CupertinoIcons.slider_horizontal_3: MiuixIcons.extended.byName('tune')!,
  CupertinoIcons.checkmark: MiuixIcons.extended.byName('ok')!,
  CupertinoIcons.play: MiuixIcons.extended.byName('play')!,
  CupertinoIcons.play_fill: MiuixIcons.extended.byName('play')!,
  CupertinoIcons.pause: MiuixIcons.extended.byName('pause')!,
  CupertinoIcons.pause_fill: MiuixIcons.extended.byName('pause')!,
  CupertinoIcons.forward_fill: MiuixIcons.extended.byName('forward')!,
  CupertinoIcons.lock: MiuixIcons.extended.byName('lock')!,
  CupertinoIcons.lock_fill: MiuixIcons.extended.byName('lock')!,
  CupertinoIcons.speaker_3_fill: MiuixIcons.extended.byName('volumeUp')!,
  CupertinoIcons.speaker_slash_fill: MiuixIcons.extended.byName('volumeOff')!,
  CupertinoIcons.pin_fill: MiuixIcons.extended.byName('pin')!,
  CupertinoIcons.pin_slash_fill: MiuixIcons.extended.byName('unpin')!,
  CupertinoIcons.slash_circle: MiuixIcons.extended.byName('blocklist')!,
  // ── 阶段5e-L5-2 新增语义（B 类字形归一） ──
  CupertinoIcons.folder: MiuixIcons.extended.byName('folder')!,
  CupertinoIcons.folder_open: MiuixIcons.extended.byName('folder')!,
  CupertinoIcons.doc_on_doc: MiuixIcons.extended.byName('copy')!,
  CupertinoIcons.link: MiuixIcons.extended.byName('link')!,
  CupertinoIcons.info: MiuixIcons.extended.byName('info')!,
  CupertinoIcons.paperplane: MiuixIcons.extended.byName('send')!,
  CupertinoIcons.photo: MiuixIcons.extended.byName('image')!,
  CupertinoIcons.person_2: MiuixIcons.extended.byName('contacts')!,
  CupertinoIcons.mail: MiuixIcons.extended.byName('email')!,
  CupertinoIcons.phone: MiuixIcons.extended.byName('phone')!,
  CupertinoIcons.location: MiuixIcons.extended.byName('location')!,
  CupertinoIcons.timer: MiuixIcons.extended.byName('timer')!,
  CupertinoIcons.circle_fill: MiuixIcons.extended.byName('recording')!,
  CupertinoIcons.arrow_uturn_left: MiuixIcons.extended.byName('undo')!,
  CupertinoIcons.paintbrush: MiuixIcons.extended.byName('theme')!,
  // ── 阶段5e-L5-3b 补充语义 ──
  CupertinoIcons.add: MiuixIcons.extended.byName('add')!,
  CupertinoIcons.eye: MiuixIcons.extended.byName('show')!,
  // ── 阶段5e-L5-4 补齐（OS4 图集）：通知 / 气泡 / 发送 / 重播 ──
  // 未选中（线条）走 os4 线条版；bell_fill 无实心对应 → 回退实心字形。
  CupertinoIcons.bell: MiuixIcons.os4.byName('notifications')!,
  CupertinoIcons.chat_bubble: MiuixIcons.os4.byName('messages')!,
  CupertinoIcons.chat_bubble_fill: MiuixIcons.os4.byName('messages')!,
  CupertinoIcons.bubble_left: MiuixIcons.os4.byName('send')!,
  CupertinoIcons.restart: MiuixIcons.os4.byName('reset')!,
};

/// 查询字形对应的 Miuix 矢量。
///
/// 优先级：**B 站官网 BDC 图标字体**（L5-10：消息/稍后再看/空间/评论区等）
/// → B 站官网 Web 端素材（L5-9）→ B 站官网字体素材（L5-8）
/// → 官方美术（L5-7）→ 手绘新美术（L5-6）→ 三集映射 → 内置等价轮廓（L5-5）
/// → null（回退字形）。
MiuixVectorIcon? miuixVectorForGlyph(IconData glyph) =>
    miuixBdcIconFor(glyph) ??
    miuixWebIconFor(glyph) ??
    miuixBiliSiteIconFor(glyph) ??
    miuixOfficialIconFor(glyph) ??
    miuixArtIconFor(glyph) ??
    _miuixVectorByGlyph[glyph] ??
    miuixEquivalenceIconFor(glyph);

final Map<IconData, MiuixVectorIcon> _bdcCache = {};

/// 字形字体族标签：与生成器复合键前缀（cupertino/material）保持一致。
/// cupertino_ui 的 CupertinoIcons 字体族为 'CupertinoIcons'，
/// material_ui 的 Icons 为 'MaterialIcons'（均已核实）。
String _glyphFontTag(IconData glyph) {
  if (glyph.fontFamily == 'CupertinoIcons') return 'cupertino';
  if (glyph.fontFamily == 'MaterialIcons') return 'material';
  return 'unknown';
}

/// 阶段5e-L5-10：**B 站官网 BDC 图标字体层**（svg-next：消息中心 / 稍后再看 /
/// 空间页 freshspace / 视频页 inline SVG）。
///
/// 覆盖：互动六按钮（点赞/点踩/投币/收藏/分享/稍后再看）、评论区与动态
/// （回复/转发/评论/展开）、消息中心四入口（点赞/艾特/系统/回复）、空间与
/// 收藏夹/历史/稍后再看按钮（关注/锁/刷新/复制/删除/更多等）；
/// 由 `tools/bili_bdc_icons_import.py` 预生成。"eo|" 前缀 = evenodd 填充。
///
/// L5-10b：查表键为「字体族:码点」复合键——此前仅按 codePoint 查询，
/// 他层字形与 BDC 条目同码点时会错误截胡（如 `Icons.subtitles_outlined`
/// 0xf3fd 撞 `CupertinoIcons.checkmark`，弹幕数被渲染成对勾）。
MiuixVectorIcon? miuixBdcIconFor(IconData glyph) {
  final data = kBDCIconPaths[
      '${_glyphFontTag(glyph)}:0x${glyph.codePoint.toRadixString(16)}'];
  if (data == null) return null;
  return _bdcCache.putIfAbsent(
    glyph,
    () {
      final eo = data.startsWith('eo|');
      final d = eo ? data.substring(3) : data;
      return MiuixVectorIcon(
        name: 'bdc.${glyph.codePoint.toRadixString(16)}.regular',
        viewport: const Size(960, 960),
        intrinsicSize: const Size(24, 24),
        paths: [
          MiuixVectorPath(
            build: () => miuixParsePath(
              d,
              fillType: eo ? PathFillType.evenOdd : PathFillType.nonZero,
            ),
          ),
        ],
      );
    },
  );
}

final Map<IconData, MiuixVectorIcon> _webSiteCache = {};

/// 阶段5e-L5-9：**B 站官网 Web 端素材层**（直接抓取 www.bilibili.com 页面内联
/// SVG：视频详情页互动栏/元数据 + 首页卡片统计）。
///
/// 覆盖：点赞（激活态=官网实心拇指）/ 投币（官网 ¥ 硬币）/ 分享 /
/// 播放量 / 弹幕数；由 `tools/bili_web_icons_import.py` 预生成
/// （bbox 归一化居中于 960 视口）。"eo|" 前缀 = evenodd 填充。
MiuixVectorIcon? miuixWebIconFor(IconData glyph) {
  final data = kWebIconPaths[glyph.codePoint];
  if (data == null) return null;
  return _webSiteCache.putIfAbsent(
    glyph,
    () {
      final eo = data.startsWith('eo|');
      final d = eo ? data.substring(3) : data;
      return MiuixVectorIcon(
        name: 'webSite.${glyph.codePoint.toRadixString(16)}.regular',
        viewport: const Size(960, 960),
        intrinsicSize: const Size(24, 24),
        paths: [
          MiuixVectorPath(
            build: () => miuixParsePath(
              d,
              fillType: eo ? PathFillType.evenOdd : PathFillType.nonZero,
            ),
          ),
        ],
      );
    },
  );
}

final Map<IconData, MiuixVectorIcon> _biliSiteCache = {};

/// 阶段5e-L5-8：**B 站官网素材层**（A+B：bilifont 主站 + vanfont 详情页）。
///
/// 覆盖：点赞/点踩/投币/收藏/分享（互动行）、播放数/弹幕数（元数据行）、
/// 搜索/收藏夹/下载等；由 `tools/bili_site_assets_import.py` 预生成
/// （bbox 归一化居中于 960 视口，视觉重量与其余矢量对齐）。
MiuixVectorIcon? miuixBiliSiteIconFor(IconData glyph) {
  final data = kBiliSiteIconPaths[glyph.codePoint];
  if (data == null) return null;
  return _biliSiteCache.putIfAbsent(
    glyph,
    () => MiuixVectorIcon(
      name: 'biliSite.${glyph.codePoint.toRadixString(16)}.regular',
      viewport: const Size(960, 960),
      intrinsicSize: const Size(24, 24),
      paths: [
        MiuixVectorPath(build: () => miuixParsePath(data)),
      ],
    ),
  );
}

final Map<IconData, MiuixVectorIcon> _officialVectorCache = {};

/// 阶段5e-L5-7：**官方美术**（Material Symbols，Apache-2.0）。
///
/// 覆盖 L5-6 手绘的 27 个字形（"仅换自绘部分"）；来源为 BiliPai 本地
/// VectorDrawable（12 个）与 Google 官方仓库补缺（15 个），由
/// `tools/official_symbols_import.py` 预生成至 `app_icons_official.g.dart`。
MiuixVectorIcon? miuixOfficialIconFor(IconData glyph) {
  final data = kOfficialIconPaths[glyph.codePoint];
  if (data == null) return null;
  return _officialVectorCache.putIfAbsent(
    glyph,
    () => MiuixVectorIcon(
      name: 'official.${glyph.codePoint.toRadixString(16)}.regular',
      viewport: const Size(960, 960),
      intrinsicSize: const Size(24, 24),
      paths: [
        MiuixVectorPath(build: () => miuixParsePath(data)),
      ],
    ),
  );
}

final Map<IconData, MiuixVectorIcon> _builtinVectorCache = {};

/// 内置**等价轮廓**（L5-5 数据；美术候选对照用）。
MiuixVectorIcon? miuixEquivalenceIconFor(IconData glyph) {
  final data = kBuiltinIconPaths[glyph.codePoint];
  if (data == null) return null;
  return _builtinVectorCache.putIfAbsent(
    glyph,
    () => MiuixVectorIcon(
      name: 'builtin.${glyph.codePoint.toRadixString(16)}.regular',
      viewport: const Size(1300, 1300),
      intrinsicSize: const Size(24, 24),
      paths: [
        MiuixVectorPath(build: () => miuixParsePath(data)),
      ],
    ),
  );
}

/// 全局通用的自适应返回按钮。
///
/// 恒渲染 Miuix 返回箭头（阶段5d-L4-2 单轨）；全屏对话框
/// 路由（fullscreenDialog，如登录页）自动切换为“关闭”图标与提示。
/// 默认点击行为统一为 [Navigator.maybePop]（与键盘 Esc 的全局返回语义一致），
/// 需要前置副作用（如暂停播放器）时用 [onBeforePop]，完全自定义时用 [onPressed]。
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    this.color,
    this.onPressed,
    this.onBeforePop,
    this.tooltip,
    this.size = 20,
    this.padding = const EdgeInsets.all(8),
    this.shadows,
  });

  final Color? color;

  /// 完全自定义点击行为（提供后不再自动返回，由调用方自行处理）。
  final VoidCallback? onPressed;

  /// 返回前的副作用回调（在统一 [Navigator.maybePop] 之前执行，例如
  /// 视频/番剧播放页暂停并解绑播放器）。
  final VoidCallback? onBeforePop;

  /// 悬浮提示；缺省时普通页面为“返回”、全屏对话框页为“关闭”。
  final String? tooltip;

  final double size;
  final EdgeInsetsGeometry padding;

  /// 覆盖在视频/封面等媒体内容上时的字形阴影（对比度增强）。
  final List<Shadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    final isClose = route is PageRoute<dynamic> && route.fullscreenDialog;
    final iconData = isClose ? AppIcons.clear() : AppIcons.back();
    final tokens = AppThemeHost.of(context);
    final effectiveColor = color ?? tokens.colors.onSurface;

    return MiuixIconButton(
      minWidth: 0,
      minHeight: 0,
      child: AppTooltip(
        message: tooltip ?? (isClose ? '关闭' : '返回'),
        child: Padding(
          padding: padding,
          child: AppIcon(
            iconData,
            size: size,
            color: effectiveColor,
            shadows: shadows,
          ),
        ),
      ),
      onPressed: () {
        if (onPressed != null) {
          onPressed!();
          return;
        }
        onBeforePop?.call();
        Navigator.maybePop(context);
      },
    );
  }
}
