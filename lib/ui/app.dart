import 'package:flutter/material.dart';

import 'package:winwin/pages/dynamics/view.dart';
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
/// Phase 7.7：动态/消息页接入实现；历史/听视频暂保留占位。
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
    return Scaffold(
      body: MainLayout(
        currentIndex: _currentIndex,
        onSelect: _onSelect,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomePage(onGotoProfile: () => _onSelect(_indexOf(AppPage.profile))),
            const DynamicsPage(),
            _PlaceholderPage(label: navDestinations[2].label),
            const WhisperPage(),
            const ProfilePage(),
          ],
        ),
      ),
    );
  }
}

int _indexOf(AppPage page) =>
    navDestinations.indexWhere((d) => d.page == page);

/// 未实现页面的占位（历史 / 听视频等待后续实现）。
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.construction_outlined, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            '$label · 待实现',
            style: TextStyle(color: cs.outline),
          ),
        ],
      ),
    );
  }
}
