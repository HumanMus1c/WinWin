import 'package:flutter/material.dart';
import 'components/frosted_bottom_bar.dart';
import 'home/home_page.dart';
import 'profile/profile_page.dart';

/// Root app — manages page switching and floating bottom bar.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  AppPage _currentPage = AppPage.home;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Page content
          IndexedStack(
            index: _currentPage == AppPage.profile ? 1 : 0,
            children: [
              HomePage(
                onGotoProfile: () =>
                    setState(() => _currentPage = AppPage.profile),
              ),
              const ProfilePage(),
            ],
          ),
          // Floating bottom bar with frosted glass blur
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FrostedBottomBar(
              currentPage: _currentPage,
              onNavigate: (page) => setState(() => _currentPage = page),
            ),
          ),
        ],
      ),
    );
  }
}
