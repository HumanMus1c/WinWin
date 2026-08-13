import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:winwin/pages/dynamics/view.dart';
import 'package:winwin/pages/history/history_page.dart';
import 'package:winwin/pages/whisper/view.dart';
import 'home/home_page.dart';
import 'main_layout.dart';
import 'profile/profile_page.dart';
import 'components/frosted_bottom_bar.dart';

/// Root app — manages page switching via [MainLayout].
///
/// Phase 7.4：用 PiliPlus 风格的 [MainLayout] 三槽位壳层替换原 `Stack`。
/// 宽屏自动启用侧边 [AppNavRail]，窄屏显示底部浮动栏（滚动联动显隐）。
///
/// Phase 7.7：动态/消息页接入实现；番剧/直播作为首页子 tab。
/// 动态/历史为根级共享实例：「我的」页入口通过 [ProfilePage.onNavigate]
/// 切换到同一 tab，保证两个入口内容始终一致。
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  int _currentIndex = 0;

  void _onSelect(int i) => setState(() => _currentIndex = i);

  @override
  Widget build(BuildContext context) {
    // Esc 全局返回上一级：键盘事件从焦点节点向上冒泡，对话框/底部弹层
    // 的 ModalRoute 自带 Esc 关闭快捷键、播放器内 PlayerFocus 自行消费
    // Esc（全屏态退出全屏），均先于本层处理；未消费时才由这里兜底
    // pop 当前路由，实现程序全局的 Esc 返回。
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          final navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: MainLayout(
          currentIndex: _currentIndex,
          onSelect: _onSelect,
          body: IndexedStack(
            index: _currentIndex,
            children: [
              HomePage(onGotoProfile: () => _onSelect(_indexOf(AppPage.profile))),
              const DynamicsPage(),
              const HistoryPage(),
              const WhisperPage(),
              ProfilePage(onNavigate: (p) => _onSelect(_indexOf(p))),
            ],
          ),
        ),
      ),
    );
  }
}

int _indexOf(AppPage page) =>
    navDestinations.indexWhere((d) => d.page == page);

