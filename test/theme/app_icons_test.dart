import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/pages/whisper/session/session_more_menu_button.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

void main() {
  group('AppIcons 静态方法双风格分发测试', () {
    test('全局返回图标分发', () {
      expect(AppIcons.backOf(UiStyle.material3), equals(Icons.arrow_back));
      expect(
        AppIcons.backOf(UiStyle.miuix),
        equals(CupertinoIcons.chevron_back),
      );
    });

    test('顶层导航图标分发', () {
      // 首页
      expect(
        AppIcons.homeOf(UiStyle.material3, selected: false),
        equals(Icons.home_outlined),
      );
      expect(
        AppIcons.homeOf(UiStyle.material3, selected: true),
        equals(Icons.home),
      );
      expect(
        AppIcons.homeOf(UiStyle.miuix, selected: false),
        equals(CupertinoIcons.house),
      );
      expect(
        AppIcons.homeOf(UiStyle.miuix, selected: true),
        equals(CupertinoIcons.house_fill),
      );

      // 动态
      expect(
        AppIcons.dynamicOf(UiStyle.material3, selected: false),
        equals(Icons.notifications_outlined),
      );
      expect(
        AppIcons.dynamicOf(UiStyle.material3, selected: true),
        equals(Icons.notifications),
      );
      expect(
        AppIcons.dynamicOf(UiStyle.miuix, selected: false),
        equals(CupertinoIcons.bell),
      );
      expect(
        AppIcons.dynamicOf(UiStyle.miuix, selected: true),
        equals(CupertinoIcons.bell_fill),
      );

      // 历史
      expect(
        AppIcons.historyOf(UiStyle.material3, selected: false),
        equals(Icons.history_outlined),
      );
      expect(
        AppIcons.historyOf(UiStyle.material3, selected: true),
        equals(Icons.history),
      );
      expect(
        AppIcons.historyOf(UiStyle.miuix, selected: false),
        equals(CupertinoIcons.clock),
      );
      expect(
        AppIcons.historyOf(UiStyle.miuix, selected: true),
        equals(CupertinoIcons.clock_fill),
      );

      // 消息
      expect(
        AppIcons.whisperOf(UiStyle.material3, selected: false),
        equals(Icons.chat_bubble_outline),
      );
      expect(
        AppIcons.whisperOf(UiStyle.material3, selected: true),
        equals(Icons.chat_bubble),
      );
      expect(
        AppIcons.whisperOf(UiStyle.miuix, selected: false),
        equals(CupertinoIcons.chat_bubble_2),
      );
      expect(
        AppIcons.whisperOf(UiStyle.miuix, selected: true),
        equals(CupertinoIcons.chat_bubble_2_fill),
      );

      // 我的
      expect(
        AppIcons.profileOf(UiStyle.material3, selected: false),
        equals(Icons.person_outlined),
      );
      expect(
        AppIcons.profileOf(UiStyle.material3, selected: true),
        equals(Icons.person),
      );
      expect(
        AppIcons.profileOf(UiStyle.miuix, selected: false),
        equals(CupertinoIcons.person),
      );
      expect(
        AppIcons.profileOf(UiStyle.miuix, selected: true),
        equals(CupertinoIcons.person_fill),
      );
    });

    test('互动控件图标分发（点赞/点踩/投币/收藏/分享/稍后看）', () {
      // 点赞
      expect(
        AppIcons.likeOf(UiStyle.material3, active: false),
        equals(Icons.thumb_up_outlined),
      );
      expect(
        AppIcons.likeOf(UiStyle.material3, active: true),
        equals(Icons.thumb_up),
      );
      expect(
        AppIcons.likeOf(UiStyle.miuix, active: false),
        equals(CupertinoIcons.hand_thumbsup),
      );
      expect(
        AppIcons.likeOf(UiStyle.miuix, active: true),
        equals(CupertinoIcons.hand_thumbsup_fill),
      );

      // 点踩
      expect(
        AppIcons.dislikeOf(UiStyle.material3, active: false),
        equals(Icons.thumb_down_outlined),
      );
      expect(
        AppIcons.dislikeOf(UiStyle.material3, active: true),
        equals(Icons.thumb_down),
      );
      expect(
        AppIcons.dislikeOf(UiStyle.miuix, active: false),
        equals(CupertinoIcons.hand_thumbsdown),
      );
      expect(
        AppIcons.dislikeOf(UiStyle.miuix, active: true),
        equals(CupertinoIcons.hand_thumbsdown_fill),
      );

      // 投币
      expect(
        AppIcons.coinOf(UiStyle.material3, active: false),
        equals(Icons.monetization_on_outlined),
      );
      expect(
        AppIcons.coinOf(UiStyle.material3, active: true),
        equals(Icons.monetization_on),
      );
      expect(
        AppIcons.coinOf(UiStyle.miuix, active: false),
        equals(CupertinoIcons.money_dollar_circle),
      );
      expect(
        AppIcons.coinOf(UiStyle.miuix, active: true),
        equals(CupertinoIcons.money_dollar_circle_fill),
      );

      // 收藏
      expect(
        AppIcons.favoriteOf(UiStyle.material3, active: false),
        equals(Icons.star_border),
      );
      expect(
        AppIcons.favoriteOf(UiStyle.material3, active: true),
        equals(Icons.star),
      );
      expect(
        AppIcons.favoriteOf(UiStyle.miuix, active: false),
        equals(CupertinoIcons.star),
      );
      expect(
        AppIcons.favoriteOf(UiStyle.miuix, active: true),
        equals(CupertinoIcons.star_fill),
      );

      // 分享
      expect(
        AppIcons.shareOf(UiStyle.material3),
        equals(Icons.share_outlined),
      );
      expect(
        AppIcons.shareOf(UiStyle.miuix),
        equals(CupertinoIcons.share),
      );

      // 稍后再看
      expect(
        AppIcons.watchLaterOf(UiStyle.material3, active: false),
        equals(Icons.watch_later_outlined),
      );
      expect(
        AppIcons.watchLaterOf(UiStyle.material3, active: true),
        equals(Icons.watch_later),
      );
      expect(
        AppIcons.watchLaterOf(UiStyle.miuix, active: false),
        equals(CupertinoIcons.clock),
      );
      expect(
        AppIcons.watchLaterOf(UiStyle.miuix, active: true),
        equals(CupertinoIcons.clock_fill),
      );
    });

    test('评论区及通用交互图标分发', () {
      // 回复
      expect(AppIcons.replyOf(UiStyle.material3), equals(Icons.reply));
      expect(AppIcons.replyOf(UiStyle.miuix), equals(CupertinoIcons.reply));

      // 展开 / 折叠
      expect(
        AppIcons.expandMoreOf(UiStyle.material3),
        equals(Icons.expand_more),
      );
      expect(
        AppIcons.expandMoreOf(UiStyle.miuix),
        equals(CupertinoIcons.chevron_down),
      );
      expect(
        AppIcons.chevronUpOf(UiStyle.material3),
        equals(Icons.expand_less),
      );
      expect(
        AppIcons.chevronUpOf(UiStyle.miuix),
        equals(CupertinoIcons.chevron_up),
      );

      // 搜索、清除、更多、设置、刷新、下载、删除
      expect(AppIcons.searchOf(UiStyle.material3), equals(Icons.search));
      expect(AppIcons.searchOf(UiStyle.miuix), equals(CupertinoIcons.search));

      expect(AppIcons.clearOf(UiStyle.material3), equals(Icons.clear));
      expect(AppIcons.clearOf(UiStyle.miuix), equals(CupertinoIcons.clear));

      expect(AppIcons.moreOf(UiStyle.material3), equals(Icons.more_vert));
      expect(AppIcons.moreOf(UiStyle.miuix), equals(CupertinoIcons.ellipsis));

      expect(
        AppIcons.settingsOf(UiStyle.material3),
        equals(Icons.settings_outlined),
      );
      expect(
        AppIcons.settingsOf(UiStyle.miuix),
        equals(CupertinoIcons.settings),
      );

      expect(AppIcons.refreshOf(UiStyle.material3), equals(Icons.refresh));
      expect(
        AppIcons.refreshOf(UiStyle.miuix),
        equals(CupertinoIcons.refresh),
      );

      expect(
        AppIcons.downloadOf(UiStyle.material3),
        equals(Icons.download_outlined),
      );
      expect(
        AppIcons.downloadOf(UiStyle.miuix),
        equals(CupertinoIcons.arrow_down_to_line),
      );

      expect(
        AppIcons.deleteOf(UiStyle.material3),
        equals(Icons.delete_outline),
      );
      expect(AppIcons.deleteOf(UiStyle.miuix), equals(CupertinoIcons.delete));
    });

    test('播放器控制及音画相关图标分发', () {
      // 播放 / 暂停 / 重播
      expect(AppIcons.playOf(UiStyle.material3), equals(Icons.play_arrow_outlined));
      expect(AppIcons.playOf(UiStyle.material3, active: true), equals(Icons.play_arrow));
      expect(AppIcons.playOf(UiStyle.miuix), equals(CupertinoIcons.play));
      expect(AppIcons.playOf(UiStyle.miuix, active: true), equals(CupertinoIcons.play_fill));

      expect(AppIcons.pauseOf(UiStyle.material3), equals(Icons.pause_circle_outline));
      expect(AppIcons.pauseOf(UiStyle.material3, active: true), equals(Icons.pause));
      expect(AppIcons.pauseOf(UiStyle.miuix), equals(CupertinoIcons.pause));
      expect(AppIcons.pauseOf(UiStyle.miuix, active: true), equals(CupertinoIcons.pause_fill));

      expect(AppIcons.replayOf(UiStyle.material3), equals(Icons.replay));
      expect(AppIcons.replayOf(UiStyle.miuix), equals(CupertinoIcons.restart));

      // 快进 / 快退
      expect(AppIcons.fastForwardOf(UiStyle.material3), equals(Icons.fast_forward));
      expect(AppIcons.fastForwardOf(UiStyle.miuix), equals(CupertinoIcons.forward_fill));
      expect(AppIcons.fastRewindOf(UiStyle.material3), equals(Icons.fast_rewind));
      expect(AppIcons.fastRewindOf(UiStyle.miuix), equals(CupertinoIcons.backward_fill));

      // 锁定
      expect(AppIcons.lockOf(UiStyle.material3), equals(Icons.lock));
      expect(AppIcons.lockOf(UiStyle.miuix), equals(CupertinoIcons.lock_fill));
      expect(AppIcons.lockOutlineOf(UiStyle.material3), equals(Icons.lock_outline));
      expect(AppIcons.lockOutlineOf(UiStyle.miuix), equals(CupertinoIcons.lock));

      // 音量
      expect(AppIcons.volumeUpOf(UiStyle.material3), equals(Icons.volume_up));
      expect(AppIcons.volumeUpOf(UiStyle.miuix), equals(CupertinoIcons.speaker_3_fill));
      expect(AppIcons.volumeDownOf(UiStyle.material3), equals(Icons.volume_down));
      expect(AppIcons.volumeDownOf(UiStyle.miuix), equals(CupertinoIcons.speaker_1_fill));
      expect(AppIcons.volumeOffOf(UiStyle.material3), equals(Icons.volume_off));
      expect(AppIcons.volumeOffOf(UiStyle.miuix), equals(CupertinoIcons.speaker_slash_fill));

      // 全屏 / 网页全屏 / 画中画
      expect(AppIcons.fullscreenOf(UiStyle.material3, active: false), equals(Icons.fullscreen));
      expect(AppIcons.fullscreenOf(UiStyle.material3, active: true), equals(Icons.fullscreen_exit));
      expect(AppIcons.fullscreenOf(UiStyle.miuix, active: false), equals(CupertinoIcons.fullscreen));
      expect(AppIcons.fullscreenOf(UiStyle.miuix, active: true), equals(CupertinoIcons.fullscreen_exit));

      expect(AppIcons.inAppFullscreenOf(UiStyle.material3, active: false), equals(Icons.crop_square_outlined));
      expect(AppIcons.inAppFullscreenOf(UiStyle.material3, active: true), equals(Icons.crop_square));
      expect(AppIcons.inAppFullscreenOf(UiStyle.miuix, active: false), equals(CupertinoIcons.square));
      expect(AppIcons.inAppFullscreenOf(UiStyle.miuix, active: true), equals(CupertinoIcons.square_fill));

      expect(AppIcons.pipOf(UiStyle.material3), equals(Icons.picture_in_picture_alt));
      expect(AppIcons.pipOf(UiStyle.miuix), equals(CupertinoIcons.tv));

      // 弹幕 / 字幕 / 章节
      expect(AppIcons.danmakuOf(UiStyle.material3, active: true), equals(Icons.chat_bubble));
      expect(AppIcons.danmakuOf(UiStyle.miuix, active: true), equals(CupertinoIcons.chat_bubble_fill));
      expect(AppIcons.sendDanmakuOf(UiStyle.material3), equals(Icons.comment_outlined));
      expect(AppIcons.sendDanmakuOf(UiStyle.miuix), equals(CupertinoIcons.bubble_left));
      expect(AppIcons.danmakuTuneOf(UiStyle.material3), equals(Icons.tune));
      expect(AppIcons.danmakuTuneOf(UiStyle.miuix), equals(CupertinoIcons.slider_horizontal_3));

      expect(AppIcons.subtitleOf(UiStyle.material3, active: true), equals(Icons.closed_caption));
      expect(AppIcons.subtitleOf(UiStyle.miuix, active: true), equals(CupertinoIcons.captions_bubble_fill));

      expect(AppIcons.chapterOf(UiStyle.material3, active: true), equals(Icons.bookmarks));
      expect(AppIcons.chapterOf(UiStyle.miuix, active: true), equals(CupertinoIcons.bookmark_fill));
    });

    test('消息对话与设置面板相关图标分发', () {
      // 更多选项
      expect(AppIcons.moreOptionsOf(UiStyle.material3), equals(Icons.more_vert));
      expect(AppIcons.moreOptionsOf(UiStyle.miuix), equals(CupertinoIcons.ellipsis));

      // 置顶 / 免打扰
      expect(AppIcons.pinOf(UiStyle.material3, active: false), equals(Icons.vertical_align_top));
      expect(AppIcons.pinOf(UiStyle.material3, active: true), equals(Icons.vertical_align_bottom));
      expect(AppIcons.pinOf(UiStyle.miuix, active: false), equals(CupertinoIcons.pin_fill));
      expect(AppIcons.pinOf(UiStyle.miuix, active: true), equals(CupertinoIcons.pin_slash_fill));

      expect(AppIcons.notificationsOffOf(UiStyle.material3, active: false), equals(Icons.notifications_off_outlined));
      expect(AppIcons.notificationsOffOf(UiStyle.material3, active: true), equals(Icons.notifications_active_outlined));
      expect(AppIcons.notificationsOffOf(UiStyle.miuix, active: false), equals(CupertinoIcons.bell_slash));
      expect(AppIcons.notificationsOffOf(UiStyle.miuix, active: true), equals(CupertinoIcons.bell_fill));

      // 单选 / 屏蔽 / 错误 / 视频元数据
      expect(AppIcons.radioOf(UiStyle.material3, selected: true), equals(Icons.radio_button_checked));
      expect(AppIcons.radioOf(UiStyle.material3, selected: false), equals(Icons.radio_button_unchecked));
      expect(AppIcons.radioOf(UiStyle.miuix, selected: true), equals(CupertinoIcons.check_mark_circled_solid));
      expect(AppIcons.radioOf(UiStyle.miuix, selected: false), equals(CupertinoIcons.circle));

      expect(AppIcons.blockOf(UiStyle.material3), equals(Icons.block));
      expect(AppIcons.blockOf(UiStyle.miuix), equals(CupertinoIcons.slash_circle));

      expect(AppIcons.errorOf(UiStyle.material3), equals(Icons.error_outline));
      expect(AppIcons.errorOf(UiStyle.miuix), equals(CupertinoIcons.exclamationmark_circle));

      expect(AppIcons.viewCountOf(UiStyle.material3), equals(Icons.play_circle_outline));
      expect(AppIcons.viewCountOf(UiStyle.miuix), equals(CupertinoIcons.play_circle));
      expect(AppIcons.danmakuCountOf(UiStyle.material3), equals(Icons.subtitles_outlined));
      expect(AppIcons.danmakuCountOf(UiStyle.miuix), equals(CupertinoIcons.captions_bubble));
      expect(AppIcons.durationOf(UiStyle.material3), equals(Icons.schedule_outlined));
      expect(AppIcons.durationOf(UiStyle.miuix), equals(CupertinoIcons.clock));
      expect(AppIcons.calendarOf(UiStyle.material3), equals(Icons.calendar_today_outlined));
      expect(AppIcons.calendarOf(UiStyle.miuix), equals(CupertinoIcons.calendar));
    });
  });

  group('AppBackButton 组件测试', () {
    testWidgets('在 Material 3 环境下渲染 Icons.arrow_back', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UiStyleScope(
            style: UiStyle.material3,
            child: const Scaffold(
              body: AppBackButton(),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_back), findsNothing);
    });

    testWidgets('在 Miuix 环境下渲染 CupertinoIcons.chevron_back', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UiStyleScope(
            style: UiStyle.miuix,
            child: const Scaffold(
              body: AppBackButton(),
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.chevron_back), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });

  group('SessionMoreMenuButton 组件测试', () {
    testWidgets('在 Material 3 环境下渲染 Icons.more_vert 并能弹出 MenuAnchor', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UiStyleScope(
            style: UiStyle.material3,
            child: Scaffold(
              body: SessionMoreMenuButton(
                isPinned: false,
                isDnd: false,
                onToggleTop: () {},
                onToggleDnd: () {},
                onRemove: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.ellipsis), findsNothing);

      // 点击打开菜单
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('置顶会话'), findsOneWidget);
      expect(find.text('开启免打扰'), findsOneWidget);
      expect(find.text('删除会话'), findsOneWidget);
    });

    testWidgets('在 Miuix 环境下渲染 CupertinoIcons.ellipsis', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: UiStyleScope(
            style: UiStyle.miuix,
            child: Scaffold(
              body: SessionMoreMenuButton(
                isPinned: true,
                isDnd: true,
                onToggleTop: () {},
                onToggleDnd: () {},
                onRemove: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // 点击打开菜单
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis));
      await tester.pumpAndSettle();

      expect(find.text('取消置顶'), findsOneWidget);
      expect(find.text('关闭免打扰'), findsOneWidget);
      expect(find.text('删除会话'), findsOneWidget);
    });
  });
}
