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
}

/// 全局通用的自适应返回按钮。
///
/// 根据当前主题的 [UiStyle] 自动渲染 M3 箭头或 Miuix 返回箭头，并适配点击热区与视觉回弹。
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    this.color,
    this.onPressed,
    this.tooltip = '返回',
    this.size = 20,
    this.padding = const EdgeInsets.all(8),
  });

  final Color? color;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final style = InheritedUiStyle.of(context);
    final iconData = AppIcons.backOf(style);
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurface;

    return IconButton(
      icon: Icon(iconData, size: size),
      color: effectiveColor,
      tooltip: tooltip,
      padding: padding,
      constraints: const BoxConstraints(),
      onPressed: () {
        if (onPressed != null) {
          onPressed!();
        } else {
          Navigator.maybePop(context);
        }
      },
    );
  }
}
