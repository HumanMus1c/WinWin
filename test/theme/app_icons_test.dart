import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/pages/whisper/session/session_more_menu_button.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/theme/inherited_ui_style.dart';
import 'package:winwin/theme/ui_style.dart';

void main() {
  group('AppIcons 静态方法双风格分发测试', () {
    test('全局返回图标分发', () {
      expect(
        AppIcons.backOf(UiStyle.miuix),
        equals(CupertinoIcons.chevron_back),
      );
    });

    test('顶层导航图标分发', () {
      // 首页
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
        AppIcons.dynamicOf(UiStyle.miuix, selected: false),
        equals(CupertinoIcons.bell),
      );
      expect(
        AppIcons.dynamicOf(UiStyle.miuix, selected: true),
        equals(CupertinoIcons.bell_fill),
      );

      // 历史
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
        AppIcons.whisperOf(UiStyle.miuix, selected: false),
        equals(CupertinoIcons.chat_bubble_2),
      );
      expect(
        AppIcons.whisperOf(UiStyle.miuix, selected: true),
        equals(CupertinoIcons.chat_bubble_2_fill),
      );

      // 我的
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
        AppIcons.likeOf(UiStyle.miuix, active: false),
        equals(CupertinoIcons.hand_thumbsup),
      );
      expect(
        AppIcons.likeOf(UiStyle.miuix, active: true),
        equals(CupertinoIcons.hand_thumbsup_fill),
      );

      // 点踩
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
        AppIcons.coinOf(UiStyle.miuix, active: false),
        equals(CupertinoIcons.money_dollar_circle),
      );
      expect(
        AppIcons.coinOf(UiStyle.miuix, active: true),
        equals(CupertinoIcons.money_dollar_circle_fill),
      );

      // 收藏
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
        AppIcons.shareOf(UiStyle.miuix),
        equals(CupertinoIcons.share),
      );

      // 稍后再看
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
      expect(AppIcons.replyOf(UiStyle.miuix), equals(CupertinoIcons.reply));

      // 展开 / 折叠
      expect(
        AppIcons.expandMoreOf(UiStyle.miuix),
        equals(CupertinoIcons.chevron_down),
      );
      expect(
        AppIcons.chevronUpOf(UiStyle.miuix),
        equals(CupertinoIcons.chevron_up),
      );

      // 搜索、清除、更多、设置、刷新、下载、删除
      expect(AppIcons.searchOf(UiStyle.miuix), equals(CupertinoIcons.search));

      expect(AppIcons.clearOf(UiStyle.miuix), equals(CupertinoIcons.clear));

      expect(AppIcons.moreOf(UiStyle.miuix), equals(CupertinoIcons.ellipsis));

      expect(
        AppIcons.settingsOf(UiStyle.miuix),
        equals(CupertinoIcons.settings),
      );

      expect(
        AppIcons.refreshOf(UiStyle.miuix),
        equals(CupertinoIcons.refresh),
      );

      expect(
        AppIcons.downloadOf(UiStyle.miuix),
        equals(CupertinoIcons.arrow_down_to_line),
      );

      expect(AppIcons.deleteOf(UiStyle.miuix), equals(CupertinoIcons.delete));
    });

    test('播放器控制及音画相关图标分发', () {
      // 播放 / 暂停 / 重播
      expect(AppIcons.playOf(UiStyle.miuix), equals(CupertinoIcons.play));
      expect(AppIcons.playOf(UiStyle.miuix, active: true), equals(CupertinoIcons.play_fill));

      expect(AppIcons.pauseOf(UiStyle.miuix), equals(CupertinoIcons.pause));
      expect(AppIcons.pauseOf(UiStyle.miuix, active: true), equals(CupertinoIcons.pause_fill));

      expect(AppIcons.replayOf(UiStyle.miuix), equals(CupertinoIcons.restart));

      // 快进 / 快退
      expect(AppIcons.fastForwardOf(UiStyle.miuix), equals(CupertinoIcons.forward_fill));
      expect(AppIcons.fastRewindOf(UiStyle.miuix), equals(CupertinoIcons.backward_fill));

      // 锁定
      expect(AppIcons.lockOf(UiStyle.miuix), equals(CupertinoIcons.lock_fill));
      expect(AppIcons.lockOutlineOf(UiStyle.miuix), equals(CupertinoIcons.lock));

      // 音量
      expect(AppIcons.volumeUpOf(UiStyle.miuix), equals(CupertinoIcons.speaker_3_fill));
      expect(AppIcons.volumeDownOf(UiStyle.miuix), equals(CupertinoIcons.speaker_1_fill));
      expect(AppIcons.volumeOffOf(UiStyle.miuix), equals(CupertinoIcons.speaker_slash_fill));

      // 全屏 / 网页全屏 / 画中画
      expect(AppIcons.fullscreenOf(UiStyle.miuix, active: false), equals(CupertinoIcons.fullscreen));
      expect(AppIcons.fullscreenOf(UiStyle.miuix, active: true), equals(CupertinoIcons.fullscreen_exit));

      expect(AppIcons.inAppFullscreenOf(UiStyle.miuix, active: false), equals(CupertinoIcons.square));
      expect(AppIcons.inAppFullscreenOf(UiStyle.miuix, active: true), equals(CupertinoIcons.square_fill));

      expect(AppIcons.pipOf(UiStyle.miuix), equals(CupertinoIcons.tv));

      // 弹幕 / 字幕 / 章节
      expect(AppIcons.danmakuOf(UiStyle.miuix, active: true), equals(CupertinoIcons.chat_bubble_fill));
      expect(AppIcons.sendDanmakuOf(UiStyle.miuix), equals(CupertinoIcons.bubble_left));
      expect(AppIcons.danmakuTuneOf(UiStyle.miuix), equals(CupertinoIcons.slider_horizontal_3));

      expect(AppIcons.subtitleOf(UiStyle.miuix, active: true), equals(CupertinoIcons.captions_bubble_fill));

      expect(AppIcons.chapterOf(UiStyle.miuix, active: true), equals(CupertinoIcons.bookmark_fill));
    });

    test('消息对话与设置面板相关图标分发', () {
      // 更多选项
      expect(AppIcons.moreOptionsOf(UiStyle.miuix), equals(CupertinoIcons.ellipsis));

      // 置顶 / 免打扰
      expect(AppIcons.pinOf(UiStyle.miuix, active: false), equals(CupertinoIcons.pin_fill));
      expect(AppIcons.pinOf(UiStyle.miuix, active: true), equals(CupertinoIcons.pin_slash_fill));

      expect(AppIcons.notificationsOffOf(UiStyle.miuix, active: false), equals(CupertinoIcons.bell_slash));
      expect(AppIcons.notificationsOffOf(UiStyle.miuix, active: true), equals(CupertinoIcons.bell_fill));

      // 单选 / 屏蔽 / 错误 / 视频元数据
      expect(AppIcons.radioOf(UiStyle.miuix, selected: true), equals(CupertinoIcons.check_mark_circled_solid));
      expect(AppIcons.radioOf(UiStyle.miuix, selected: false), equals(CupertinoIcons.circle));

      expect(AppIcons.blockOf(UiStyle.miuix), equals(CupertinoIcons.slash_circle));

      expect(AppIcons.errorOf(UiStyle.miuix), equals(CupertinoIcons.exclamationmark_circle));

      expect(AppIcons.viewCountOf(UiStyle.miuix), equals(CupertinoIcons.play_circle));
      expect(AppIcons.danmakuCountOf(UiStyle.miuix), equals(CupertinoIcons.captions_bubble));
      expect(AppIcons.durationOf(UiStyle.miuix), equals(CupertinoIcons.clock));
      expect(AppIcons.calendarOf(UiStyle.miuix), equals(CupertinoIcons.calendar));
    });
    test('阶段5d-L3：两风格分发收敛为同值（恒等）', () {
      expect(
        AppIcons.backOf(UiStyle.material3),
        equals(AppIcons.backOf(UiStyle.miuix)),
      );
      expect(
        AppIcons.homeOf(UiStyle.material3, selected: true),
        equals(AppIcons.homeOf(UiStyle.miuix, selected: true)),
      );
      expect(
        AppIcons.moreOf(UiStyle.material3),
        equals(AppIcons.moreOf(UiStyle.miuix)),
      );
      expect(
        AppIcons.playOf(UiStyle.material3, active: true),
        equals(AppIcons.playOf(UiStyle.miuix, active: true)),
      );
    });
  });

  group('AppBackButton 组件测试', () {
    testWidgets('阶段5d-L3：Material 3 环境下同样渲染 Miuix 矢量返回图标', (tester) async {
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

      expect(find.byType(MiuixIcon), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('在 Miuix 环境下渲染 Miuix 矢量返回图标（阶段3c AppIcon 升级）', (tester) async {
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

      expect(find.byType(MiuixIcon), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_back), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });

  group('SessionMoreMenuButton 组件测试', () {
    testWidgets('阶段5d-L1/L3：Material 3 环境下同样渲染 Miuix 矢量图标并弹出弹层壳', (tester) async {
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

      expect(find.byType(MiuixIcon), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // 点击打开菜单
      await tester.tap(find.byTooltip('更多选项'));
      await tester.pumpAndSettle();

      expect(find.text('置顶会话'), findsOneWidget);
      expect(find.text('开启免打扰'), findsOneWidget);
      expect(find.text('删除会话'), findsOneWidget);
    });

    testWidgets('在 Miuix 环境下渲染 Miuix 矢量更多图标（阶段3c AppIcon 升级）', (tester) async {
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

      expect(find.byType(MiuixIcon), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.ellipsis), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // 点击打开菜单（Tooltip 命中层保持可用）
      await tester.tap(find.byTooltip('更多选项'));
      await tester.pumpAndSettle();

      expect(find.text('取消置顶'), findsOneWidget);
      expect(find.text('关闭免打扰'), findsOneWidget);
      expect(find.text('删除会话'), findsOneWidget);
    });
  });
}
