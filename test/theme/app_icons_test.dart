import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_miuix/miuix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winwin/pages/whisper/session/session_more_menu_button.dart';
import 'package:winwin/theme/app_icons.dart';

void main() {
  group('AppIcons 静态方法双风格分发测试', () {
    test('全局返回图标分发', () {
      expect(
        AppIcons.back(),
        equals(CupertinoIcons.chevron_back),
      );
    });

    test('顶层导航图标分发', () {
      // 首页
      expect(
        AppIcons.home(selected: false),
        equals(CupertinoIcons.house),
      );
      expect(
        AppIcons.home(selected: true),
        equals(CupertinoIcons.house_fill),
      );

      // 动态
      expect(
        AppIcons.dynamic(selected: false),
        equals(CupertinoIcons.bell),
      );
      expect(
        AppIcons.dynamic(selected: true),
        equals(CupertinoIcons.bell_fill),
      );

      // 历史
      expect(
        AppIcons.history(selected: false),
        equals(CupertinoIcons.clock),
      );
      expect(
        AppIcons.history(selected: true),
        equals(CupertinoIcons.clock_fill),
      );

      // 消息
      expect(
        AppIcons.whisper(selected: false),
        equals(CupertinoIcons.chat_bubble_2),
      );
      expect(
        AppIcons.whisper(selected: true),
        equals(CupertinoIcons.chat_bubble_2_fill),
      );

      // 我的
      expect(
        AppIcons.profile(selected: false),
        equals(CupertinoIcons.person),
      );
      expect(
        AppIcons.profile(selected: true),
        equals(CupertinoIcons.person_fill),
      );
    });

    test('互动控件图标分发（点赞/点踩/投币/收藏/分享/稍后看）', () {
      // 点赞
      expect(
        AppIcons.like(active: false),
        equals(CupertinoIcons.hand_thumbsup),
      );
      expect(
        AppIcons.like(active: true),
        equals(CupertinoIcons.hand_thumbsup_fill),
      );

      // 点踩
      expect(
        AppIcons.dislike(active: false),
        equals(CupertinoIcons.hand_thumbsdown),
      );
      expect(
        AppIcons.dislike(active: true),
        equals(CupertinoIcons.hand_thumbsdown_fill),
      );

      // 投币
      expect(
        AppIcons.coin(active: false),
        equals(CupertinoIcons.money_dollar_circle),
      );
      expect(
        AppIcons.coin(active: true),
        equals(CupertinoIcons.money_dollar_circle_fill),
      );

      // 收藏
      expect(
        AppIcons.favorite(active: false),
        equals(CupertinoIcons.star),
      );
      expect(
        AppIcons.favorite(active: true),
        equals(CupertinoIcons.star_fill),
      );

      // 分享
      expect(
        AppIcons.share(),
        equals(CupertinoIcons.share),
      );

      // 稍后再看（L5-10：改用独立 time 字形，避免与历史导航 clock 冲突）
      expect(
        AppIcons.watchLater(active: false),
        equals(CupertinoIcons.time),
      );
      expect(
        AppIcons.watchLater(active: true),
        equals(CupertinoIcons.time),
      );
    });

    test('评论区及通用交互图标分发', () {
      // 回复
      expect(AppIcons.reply(), equals(CupertinoIcons.reply));

      // 展开 / 折叠
      expect(
        AppIcons.expandMore(),
        equals(CupertinoIcons.chevron_down),
      );
      expect(
        AppIcons.chevronUp(),
        equals(CupertinoIcons.chevron_up),
      );

      // 搜索、清除、更多、设置、刷新、下载、删除
      expect(AppIcons.search(), equals(CupertinoIcons.search));

      expect(AppIcons.clear(), equals(CupertinoIcons.clear));

      expect(AppIcons.more(), equals(CupertinoIcons.ellipsis));

      expect(
        AppIcons.settings(),
        equals(CupertinoIcons.settings),
      );

      expect(
        AppIcons.refresh(),
        equals(CupertinoIcons.refresh),
      );

      expect(
        AppIcons.download(),
        equals(CupertinoIcons.arrow_down_to_line),
      );

      expect(AppIcons.delete(), equals(CupertinoIcons.delete));
    });

    test('播放器控制及音画相关图标分发', () {
      // 播放 / 暂停 / 重播
      expect(AppIcons.play(), equals(CupertinoIcons.play));
      expect(AppIcons.play(active: true), equals(CupertinoIcons.play_fill));

      expect(AppIcons.pause(), equals(CupertinoIcons.pause));
      expect(AppIcons.pause(active: true), equals(CupertinoIcons.pause_fill));

      expect(AppIcons.replay(), equals(CupertinoIcons.restart));

      // 快进 / 快退
      expect(AppIcons.fastForward(), equals(CupertinoIcons.forward_fill));
      expect(AppIcons.fastRewind(), equals(CupertinoIcons.backward_fill));

      // 锁定
      expect(AppIcons.lock(), equals(CupertinoIcons.lock_fill));
      expect(AppIcons.lockOutline(), equals(CupertinoIcons.lock));

      // 音量
      expect(AppIcons.volumeUp(), equals(CupertinoIcons.speaker_3_fill));
      expect(AppIcons.volumeDown(), equals(CupertinoIcons.speaker_1_fill));
      expect(AppIcons.volumeOff(), equals(CupertinoIcons.speaker_slash_fill));

      // 全屏 / 网页全屏 / 画中画
      expect(AppIcons.fullscreen(active: false), equals(CupertinoIcons.fullscreen));
      expect(AppIcons.fullscreen(active: true), equals(CupertinoIcons.fullscreen_exit));

      expect(AppIcons.inAppFullscreen(active: false), equals(CupertinoIcons.square));
      expect(AppIcons.inAppFullscreen(active: true), equals(CupertinoIcons.square_fill));

      expect(AppIcons.pip(), equals(CupertinoIcons.tv));

      // 弹幕 / 字幕 / 章节
      expect(AppIcons.danmaku(active: true), equals(CupertinoIcons.chat_bubble_fill));
      expect(AppIcons.sendDanmaku(), equals(CupertinoIcons.bubble_left));
      expect(AppIcons.danmakuTune(), equals(CupertinoIcons.slider_horizontal_3));

      expect(AppIcons.subtitle(active: true), equals(CupertinoIcons.captions_bubble_fill));

      expect(AppIcons.chapter(active: true), equals(CupertinoIcons.bookmark_fill));
    });

    test('消息对话与设置面板相关图标分发', () {
      // 更多选项
      expect(AppIcons.moreOptions(), equals(CupertinoIcons.ellipsis));

      // 置顶 / 免打扰
      expect(AppIcons.pin(active: false), equals(CupertinoIcons.pin_fill));
      expect(AppIcons.pin(active: true), equals(CupertinoIcons.pin_slash_fill));

      expect(AppIcons.notificationsOff(active: false), equals(CupertinoIcons.bell_slash));
      expect(AppIcons.notificationsOff(active: true), equals(CupertinoIcons.bell_fill));

      // 单选 / 屏蔽 / 错误 / 视频元数据
      expect(AppIcons.radio(selected: true), equals(CupertinoIcons.check_mark_circled_solid));
      expect(AppIcons.radio(selected: false), equals(CupertinoIcons.circle));

      expect(AppIcons.block(), equals(CupertinoIcons.slash_circle));

      expect(AppIcons.error(), equals(CupertinoIcons.exclamationmark_circle));

      expect(AppIcons.viewCount(), equals(CupertinoIcons.play_circle));
      // 阶段5e-L5-8：弹幕数改用载体字形（渲染为 B 站官网"弹幕数"矢量）。
      expect(AppIcons.danmakuCount(), equals(Icons.subtitles_outlined));
      expect(AppIcons.duration(), equals(CupertinoIcons.clock));
      expect(AppIcons.calendar(), equals(CupertinoIcons.calendar));
    });
  });

  group('AppBackButton 组件测试', () {
    testWidgets('渲染 Miuix 矢量返回图标（阶段5d-L4-2 单轨）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(
            body: AppBackButton(),
          ),
        ),
      );

      expect(find.byType(MiuixIcon), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_back), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });

  group('SessionMoreMenuButton 组件测试', () {
    testWidgets('渲染 Miuix 矢量更多图标并弹出弹层壳（阶段5d-L4-2 单轨）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionMoreMenuButton(
              isPinned: true,
              isDnd: true,
              onToggleTop: () {},
              onToggleDnd: () {},
              onRemove: () {},
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
