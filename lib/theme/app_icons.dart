import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

/// 全局双风格语义图标分发中心（对齐 BiliPai AppIcons / AppSemanticIconFamily 架构）。
///
/// 运行时支持两套完整图标库的分发：
/// - [UiStyle.material3]：Google Material Design 3 官方图标库 (`Icons.*`)
/// - [UiStyle.miuix]：Apple iOS / Miuix 精美图标库 (`CupertinoIcons.*`)
///
/// 各交互组件可通过静态便利函数（如 `AppIcons.back(context)`）根据 Inherited 上下文
/// 自动切换，也可通过 `AppIcons.backOf(style)` 针对特定风格直接获取对应字形。
abstract final class AppIcons {
  // ---------------------------------------------------------------------------
  // 1. 全局返回与导航
  // ---------------------------------------------------------------------------

  /// 全局返回图标（M3：向左箭头；Miuix：精致向左返回箭头）。
  static IconData back(BuildContext context) =>
      backOf(InheritedUiStyle.of(context));

  static IconData backOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.arrow_back,
        UiStyle.miuix => CupertinoIcons.chevron_back,
      };

  /// 顶层导航 — 首页
  static IconData home(BuildContext context, {bool selected = false}) =>
      homeOf(InheritedUiStyle.of(context), selected: selected);

  static IconData homeOf(UiStyle style, {bool selected = false}) =>
      switch (style) {
        UiStyle.material3 =>
          selected ? Icons.home : Icons.home_outlined,
        UiStyle.miuix =>
          selected ? CupertinoIcons.house_fill : CupertinoIcons.house,
      };

  /// 顶层导航 — 动态
  static IconData dynamic(BuildContext context, {bool selected = false}) =>
      dynamicOf(InheritedUiStyle.of(context), selected: selected);

  static IconData dynamicOf(UiStyle style, {bool selected = false}) =>
      switch (style) {
        UiStyle.material3 =>
          selected ? Icons.notifications : Icons.notifications_outlined,
        UiStyle.miuix =>
          selected ? CupertinoIcons.bell_fill : CupertinoIcons.bell,
      };

  /// 顶层导航 — 历史
  static IconData history(BuildContext context, {bool selected = false}) =>
      historyOf(InheritedUiStyle.of(context), selected: selected);

  static IconData historyOf(UiStyle style, {bool selected = false}) =>
      switch (style) {
        UiStyle.material3 =>
          selected ? Icons.history : Icons.history_outlined,
        UiStyle.miuix =>
          selected ? CupertinoIcons.clock_fill : CupertinoIcons.clock,
      };

  /// 顶层导航 — 消息
  static IconData whisper(BuildContext context, {bool selected = false}) =>
      whisperOf(InheritedUiStyle.of(context), selected: selected);

  static IconData whisperOf(UiStyle style, {bool selected = false}) =>
      switch (style) {
        UiStyle.material3 =>
          selected ? Icons.chat_bubble : Icons.chat_bubble_outline,
        UiStyle.miuix => selected
            ? CupertinoIcons.chat_bubble_2_fill
            : CupertinoIcons.chat_bubble_2,
      };

  /// 顶层导航 — 我的
  static IconData profile(BuildContext context, {bool selected = false}) =>
      profileOf(InheritedUiStyle.of(context), selected: selected);

  static IconData profileOf(UiStyle style, {bool selected = false}) =>
      switch (style) {
        UiStyle.material3 =>
          selected ? Icons.person : Icons.person_outlined,
        UiStyle.miuix =>
          selected ? CupertinoIcons.person_fill : CupertinoIcons.person,
      };

  // ---------------------------------------------------------------------------
  // 2. 视频 / 动态 核心互动操作行
  // ---------------------------------------------------------------------------

  /// 点赞
  static IconData like(BuildContext context, {bool active = false}) =>
      likeOf(InheritedUiStyle.of(context), active: active);

  static IconData likeOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.thumb_up : Icons.thumb_up_outlined,
        UiStyle.miuix => active
            ? CupertinoIcons.hand_thumbsup_fill
            : CupertinoIcons.hand_thumbsup,
      };

  /// 点踩
  static IconData dislike(BuildContext context, {bool active = false}) =>
      dislikeOf(InheritedUiStyle.of(context), active: active);

  static IconData dislikeOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.thumb_down : Icons.thumb_down_outlined,
        UiStyle.miuix => active
            ? CupertinoIcons.hand_thumbsdown_fill
            : CupertinoIcons.hand_thumbsdown,
      };

  /// 投币
  static IconData coin(BuildContext context, {bool active = false}) =>
      coinOf(InheritedUiStyle.of(context), active: active);

  static IconData coinOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.monetization_on : Icons.monetization_on_outlined,
        UiStyle.miuix => active
            ? CupertinoIcons.money_dollar_circle_fill
            : CupertinoIcons.money_dollar_circle,
      };

  /// 收藏
  static IconData favorite(BuildContext context, {bool active = false}) =>
      favoriteOf(InheritedUiStyle.of(context), active: active);

  static IconData favoriteOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 => active ? Icons.star : Icons.star_border,
        UiStyle.miuix =>
          active ? CupertinoIcons.star_fill : CupertinoIcons.star,
      };

  /// 分享
  static IconData share(BuildContext context) =>
      shareOf(InheritedUiStyle.of(context));

  static IconData shareOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.share_outlined,
        UiStyle.miuix => CupertinoIcons.share,
      };

  /// 稍后再看
  static IconData watchLater(BuildContext context, {bool active = false}) =>
      watchLaterOf(InheritedUiStyle.of(context), active: active);

  static IconData watchLaterOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.watch_later : Icons.watch_later_outlined,
        UiStyle.miuix =>
          active ? CupertinoIcons.clock_fill : CupertinoIcons.clock,
      };

  // ---------------------------------------------------------------------------
  // 3. 评论区互动操作
  // ---------------------------------------------------------------------------

  /// 回复
  static IconData reply(BuildContext context) =>
      replyOf(InheritedUiStyle.of(context));

  static IconData replyOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.reply,
        UiStyle.miuix => CupertinoIcons.reply,
      };

  /// 展开更多回复 / 下拉指示
  static IconData expandMore(BuildContext context) =>
      expandMoreOf(InheritedUiStyle.of(context));

  static IconData expandMoreOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.expand_more,
        UiStyle.miuix => CupertinoIcons.chevron_down,
      };

  // ---------------------------------------------------------------------------
  // 4. 通用交互控件
  // ---------------------------------------------------------------------------

  /// 搜索
  static IconData search(BuildContext context) =>
      searchOf(InheritedUiStyle.of(context));

  static IconData searchOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.search,
        UiStyle.miuix => CupertinoIcons.search,
      };

  /// 清除 / 取消
  static IconData clear(BuildContext context) =>
      clearOf(InheritedUiStyle.of(context));

  static IconData clearOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.clear,
        UiStyle.miuix => CupertinoIcons.clear,
      };

  /// 更多选项（垂直三点 / 横向省略）
  static IconData more(BuildContext context) =>
      moreOf(InheritedUiStyle.of(context));

  static IconData moreOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.more_vert,
        UiStyle.miuix => CupertinoIcons.ellipsis,
      };

  /// 设置
  static IconData settings(BuildContext context) =>
      settingsOf(InheritedUiStyle.of(context));

  static IconData settingsOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.settings_outlined,
        UiStyle.miuix => CupertinoIcons.settings,
      };

  /// 刷新
  static IconData refresh(BuildContext context) =>
      refreshOf(InheritedUiStyle.of(context));

  static IconData refreshOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.refresh,
        UiStyle.miuix => CupertinoIcons.refresh,
      };

  /// 下载 / 缓存
  static IconData download(BuildContext context) =>
      downloadOf(InheritedUiStyle.of(context));

  static IconData downloadOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.download_outlined,
        UiStyle.miuix => CupertinoIcons.arrow_down_to_line,
      };

  /// 删除 / 清理
  static IconData delete(BuildContext context) =>
      deleteOf(InheritedUiStyle.of(context));

  static IconData deleteOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.delete_outline,
        UiStyle.miuix => CupertinoIcons.delete,
      };

  /// 排序 / 筛选
  static IconData filter(BuildContext context) =>
      filterOf(InheritedUiStyle.of(context));

  static IconData filterOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.filter_list,
        UiStyle.miuix => CupertinoIcons.slider_horizontal_3,
      };

  /// 成功 / 勾选
  static IconData check(BuildContext context) =>
      checkOf(InheritedUiStyle.of(context));

  static IconData checkOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.check,
        UiStyle.miuix => CupertinoIcons.checkmark,
      };

  /// 前进 / 展开箭头
  static IconData chevronForward(BuildContext context) =>
      chevronForwardOf(InheritedUiStyle.of(context));

  static IconData chevronForwardOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.chevron_right,
        UiStyle.miuix => CupertinoIcons.chevron_forward,
      };

  /// 向上折叠箭头
  static IconData chevronUp(BuildContext context) =>
      chevronUpOf(InheritedUiStyle.of(context));

  static IconData chevronUpOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.expand_less,
        UiStyle.miuix => CupertinoIcons.chevron_up,
      };

  /// 向下展开箭头
  static IconData chevronDown(BuildContext context) =>
      chevronDownOf(InheritedUiStyle.of(context));

  static IconData chevronDownOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.expand_more,
        UiStyle.miuix => CupertinoIcons.chevron_down,
      };

  /// 播放
  static IconData play(BuildContext context, {bool active = false}) =>
      playOf(InheritedUiStyle.of(context), active: active);

  static IconData playOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.play_arrow : Icons.play_arrow_outlined,
        UiStyle.miuix =>
          active ? CupertinoIcons.play_fill : CupertinoIcons.play,
      };

  /// 暂停
  static IconData pause(BuildContext context, {bool active = false}) =>
      pauseOf(InheritedUiStyle.of(context), active: active);

  static IconData pauseOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 => active ? Icons.pause : Icons.pause_circle_outline,
        UiStyle.miuix =>
          active ? CupertinoIcons.pause_fill : CupertinoIcons.pause,
      };

  /// 重播
  static IconData replay(BuildContext context) =>
      replayOf(InheritedUiStyle.of(context));

  static IconData replayOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.replay,
        UiStyle.miuix => CupertinoIcons.restart,
      };

  /// 快进
  static IconData fastForward(BuildContext context) =>
      fastForwardOf(InheritedUiStyle.of(context));

  static IconData fastForwardOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.fast_forward,
        UiStyle.miuix => CupertinoIcons.forward_fill,
      };

  /// 快退
  static IconData fastRewind(BuildContext context) =>
      fastRewindOf(InheritedUiStyle.of(context));

  static IconData fastRewindOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.fast_rewind,
        UiStyle.miuix => CupertinoIcons.backward_fill,
      };

  /// 锁定
  static IconData lock(BuildContext context) =>
      lockOf(InheritedUiStyle.of(context));

  static IconData lockOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.lock,
        UiStyle.miuix => CupertinoIcons.lock_fill,
      };

  /// 解锁 / 锁外框
  static IconData lockOutline(BuildContext context) =>
      lockOutlineOf(InheritedUiStyle.of(context));

  static IconData lockOutlineOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.lock_outline,
        UiStyle.miuix => CupertinoIcons.lock,
      };

  /// 音量 — 大
  static IconData volumeUp(BuildContext context) =>
      volumeUpOf(InheritedUiStyle.of(context));

  static IconData volumeUpOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.volume_up,
        UiStyle.miuix => CupertinoIcons.speaker_3_fill,
      };

  /// 音量 — 小
  static IconData volumeDown(BuildContext context) =>
      volumeDownOf(InheritedUiStyle.of(context));

  static IconData volumeDownOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.volume_down,
        UiStyle.miuix => CupertinoIcons.speaker_1_fill,
      };

  /// 静音
  static IconData volumeOff(BuildContext context) =>
      volumeOffOf(InheritedUiStyle.of(context));

  static IconData volumeOffOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.volume_off,
        UiStyle.miuix => CupertinoIcons.speaker_slash_fill,
      };

  /// 全屏 / 退出全屏
  static IconData fullscreen(BuildContext context, {bool active = false}) =>
      fullscreenOf(InheritedUiStyle.of(context), active: active);

  static IconData fullscreenOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.fullscreen_exit : Icons.fullscreen,
        UiStyle.miuix =>
          active ? CupertinoIcons.fullscreen_exit : CupertinoIcons.fullscreen,
      };

  /// 网页全屏（应用内铺满）
  static IconData inAppFullscreen(BuildContext context, {bool active = false}) =>
      inAppFullscreenOf(InheritedUiStyle.of(context), active: active);

  static IconData inAppFullscreenOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.crop_square : Icons.crop_square_outlined,
        UiStyle.miuix =>
          active ? CupertinoIcons.square_fill : CupertinoIcons.square,
      };

  /// 画中画
  static IconData pip(BuildContext context) =>
      pipOf(InheritedUiStyle.of(context));

  static IconData pipOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.picture_in_picture_alt,
        UiStyle.miuix => CupertinoIcons.tv,
      };

  /// 弹幕开关
  static IconData danmaku(BuildContext context, {bool active = false}) =>
      danmakuOf(InheritedUiStyle.of(context), active: active);

  static IconData danmakuOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.chat_bubble : Icons.chat_bubble_outline,
        UiStyle.miuix => active
            ? CupertinoIcons.chat_bubble_fill
            : CupertinoIcons.chat_bubble,
      };

  /// 发送弹幕
  static IconData sendDanmaku(BuildContext context) =>
      sendDanmakuOf(InheritedUiStyle.of(context));

  static IconData sendDanmakuOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.comment_outlined,
        UiStyle.miuix => CupertinoIcons.bubble_left,
      };

  /// 弹幕设置 / 调优
  static IconData danmakuTune(BuildContext context) =>
      danmakuTuneOf(InheritedUiStyle.of(context));

  static IconData danmakuTuneOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.tune,
        UiStyle.miuix => CupertinoIcons.slider_horizontal_3,
      };

  /// 字幕
  static IconData subtitle(BuildContext context, {bool active = false}) =>
      subtitleOf(InheritedUiStyle.of(context), active: active);

  static IconData subtitleOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.closed_caption : Icons.closed_caption_outlined,
        UiStyle.miuix => active
            ? CupertinoIcons.captions_bubble_fill
            : CupertinoIcons.captions_bubble,
      };

  /// 章节
  static IconData chapter(BuildContext context, {bool active = false}) =>
      chapterOf(InheritedUiStyle.of(context), active: active);

  static IconData chapterOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.bookmarks : Icons.bookmarks_outlined,
        UiStyle.miuix =>
          active ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
      };

  /// 更多选项（M3: 竖向三点; Miuix: 横向省略三点）
  static IconData moreOptions(BuildContext context) =>
      moreOptionsOf(InheritedUiStyle.of(context));

  static IconData moreOptionsOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.more_vert,
        UiStyle.miuix => CupertinoIcons.ellipsis,
      };

  /// 置顶
  static IconData pin(BuildContext context, {bool active = false}) =>
      pinOf(InheritedUiStyle.of(context), active: active);

  static IconData pinOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 =>
          active ? Icons.vertical_align_bottom : Icons.vertical_align_top,
        UiStyle.miuix =>
          active ? CupertinoIcons.pin_slash_fill : CupertinoIcons.pin_fill,
      };

  /// 免打扰 / 静音通知
  static IconData notificationsOff(BuildContext context, {bool active = false}) =>
      notificationsOffOf(InheritedUiStyle.of(context), active: active);

  static IconData notificationsOffOf(UiStyle style, {bool active = false}) =>
      switch (style) {
        UiStyle.material3 => active
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        UiStyle.miuix =>
          active ? CupertinoIcons.bell_fill : CupertinoIcons.bell_slash,
      };

  /// 单选框
  static IconData radio(BuildContext context, {required bool selected}) =>
      radioOf(InheritedUiStyle.of(context), selected: selected);

  static IconData radioOf(UiStyle style, {required bool selected}) =>
      switch (style) {
        UiStyle.material3 =>
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        UiStyle.miuix => selected
            ? CupertinoIcons.check_mark_circled_solid
            : CupertinoIcons.circle,
      };

  /// 屏蔽 / 封禁
  static IconData block(BuildContext context) =>
      blockOf(InheritedUiStyle.of(context));

  static IconData blockOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.block,
        UiStyle.miuix => CupertinoIcons.slash_circle,
      };

  /// 错误 / 告警提示
  static IconData error(BuildContext context) =>
      errorOf(InheritedUiStyle.of(context));

  static IconData errorOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.error_outline,
        UiStyle.miuix => CupertinoIcons.exclamationmark_circle,
      };

  /// 视频播放数 / 观看数
  static IconData viewCount(BuildContext context) =>
      viewCountOf(InheritedUiStyle.of(context));

  static IconData viewCountOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.play_circle_outline,
        UiStyle.miuix => CupertinoIcons.play_circle,
      };

  /// 视频弹幕数
  static IconData danmakuCount(BuildContext context) =>
      danmakuCountOf(InheritedUiStyle.of(context));

  static IconData danmakuCountOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.subtitles_outlined,
        UiStyle.miuix => CupertinoIcons.captions_bubble,
      };

  /// 视频时长
  static IconData duration(BuildContext context) =>
      durationOf(InheritedUiStyle.of(context));

  static IconData durationOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.schedule_outlined,
        UiStyle.miuix => CupertinoIcons.clock,
      };

  /// 日历 / 发布日期
  static IconData calendar(BuildContext context) =>
      calendarOf(InheritedUiStyle.of(context));

  static IconData calendarOf(UiStyle style) => switch (style) {
        UiStyle.material3 => Icons.calendar_today_outlined,
        UiStyle.miuix => CupertinoIcons.calendar,
      };
}

/// 全局通用的自适应返回按钮。
///
/// 根据当前主题的 [UiStyle] 自动渲染 M3 箭头或 Miuix 返回箭头；全屏对话框
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
    final style = InheritedUiStyle.of(context);
    final route = ModalRoute.of(context);
    final isClose = route is PageRoute<dynamic> && route.fullscreenDialog;
    final iconData = isClose ? AppIcons.clearOf(style) : AppIcons.backOf(style);
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurface;

    return IconButton(
      icon: Icon(iconData, size: size, shadows: shadows),
      color: effectiveColor,
      tooltip: tooltip ?? (isClose ? '关闭' : '返回'),
      padding: padding,
      constraints: const BoxConstraints(),
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
