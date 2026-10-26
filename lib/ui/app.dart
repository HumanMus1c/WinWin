import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:winwin/core/window/title_bar_controller.dart';
import 'package:winwin/core/shell/app_scaffold.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/pages/dynamics/view.dart';
import 'package:winwin/pages/history/history_page.dart';
import 'package:winwin/pages/whisper/view.dart';
import 'package:winwin/services/msg_unread_service.dart';
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
  Brightness? _brightness;

  /// 已访问过的根页面索引 —— 懒加载：首次切到某页才构建。
  ///
  /// 此前 5 个根页面（首页/动态/历史/消息/我的）在 [IndexedStack] 中一次性
  /// 构建，冷启动即同时触发各页首批请求（动态流、历史、会话列表等），
  /// 造成启动网络与渲染压力。改为与首页分类 tab 相同的「访问即建」策略：
  /// 未访问页面先占位 [SizedBox.shrink]，首次切换时才实例化并常驻保留状态。
  final Set<int> _visitedPages = {0};

  @override
  void initState() {
    super.initState();
    MsgUnreadService().fetchUnread();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = AppThemeHost.of(context).brightness;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      if (_brightness != brightness) {
        _brightness = brightness;
        windowManager.setBrightness(brightness);
        TitleBarController.instance.syncWithTheme(brightness);
      }
    }
  }

  void _onSelect(int i) {
    setState(() {
      _currentIndex = i;
      _visitedPages.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Esc 全局分层语义（返回上一级 / 取消输入聚焦 / 关闭对话框与二级浮层）
    // 由 main.dart 的 MaterialApp.builder 内 AppEscapeScope 统一处理，
    // 对任意路由（含压栈页面与对话框）生效。
    return AppScaffold(
      // 根壳：MainLayout 自带导航；不预留顶部安全行（根页面无返回按钮 / 标题）。
      reserveTopStrip: false,
      body: MainLayout(
        currentIndex: _currentIndex,
        onSelect: _onSelect,
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildLazyPage(
              0,
              () => HomePage(
                onGotoProfile: () => _onSelect(_indexOf(AppPage.profile)),
              ),
            ),
            _buildLazyPage(1, () => const DynamicsPage()),
            _buildLazyPage(2, () => const HistoryPage()),
            _buildLazyPage(3, () => const WhisperPage()),
            _buildLazyPage(
              4,
              () => ProfilePage(onNavigate: (p) => _onSelect(_indexOf(p))),
            ),
          ],
        ),
      ),
    );
  }

  /// 未访问页面先占位，首次切到才实例化（状态由 [IndexedStack] 常驻保留）。
  Widget _buildLazyPage(int index, Widget Function() builder) {
    if (!_visitedPages.contains(index)) return const SizedBox.shrink();
    return builder();
  }
}

int _indexOf(AppPage page) =>
    navDestinations.indexWhere((d) => d.page == page);

