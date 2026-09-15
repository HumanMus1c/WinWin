import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
