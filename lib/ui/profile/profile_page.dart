import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/style.dart';
import '../../models/models.dart';
import '../components/ios_components.dart';

/// Profile page — ported from BiliPai's ProfileScreen.
/// Gradient background, user info, stats, iOS-style settings list.
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = mockUser;
    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background (simulating wallpaper) ──
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, 0.5),
                colors: [
                  user.avatarGradient.start.withOpacity(0.8),
                  Theme.of(context).scaffoldBackgroundColor,
                ],
              ),
            ),
          ),
          // ── Content ──
          ListView(
            padding: const EdgeInsets.only(top: 100, bottom: 100),
            children: [
              _UserInfoSection(user: user),
              _StatsSection(user: user),
              const SizedBox(height: Style.md),
              // Services list
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Style.lg),
                child: IOSGroup(
                  children: [
                    IOSClickableItem(icon: Icons.download, title: '离线缓存', iconTint: iosBlue),
                    IOSClickableItem(icon: Icons.history, title: '历史记录', iconTint: iosBlue),
                    IOSClickableItem(icon: Icons.bookmark, title: '我的收藏', iconTint: iosYellow),
                    IOSClickableItem(icon: Icons.watch_later, title: '稍后再看', iconTint: iosGreen),
                    IOSClickableItem(icon: Icons.message, title: '消息中心', iconTint: iosPink),
                  ],
                ),
              ),
              const SizedBox(height: Style.md),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Style.lg),
                child: IOSGroup(
                  children: [
                    IOSClickableItem(icon: Icons.swap_horiz, title: '账号切换', iconTint: iosBlue),
                  ],
                ),
              ),
            ],
          ),
          // ── Top bar (centered title) ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Text(
                    '我的',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserInfoSection extends StatelessWidget {
  final UserProfile user;

  const _UserInfoSection({required this.user});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Style.xl, vertical: Style.lg),
      child: Row(
        children: [
          // Avatar (72px circle with gradient)
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [user.avatarGradient.start, user.avatarGradient.end],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 32),
          ),
          const SizedBox(width: Style.lg),
          // Name + badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Level badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: biliPink,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'LV ${user.level}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // VIP badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: user.isVip ? biliPink : theme.colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        user.isVip ? '大会员' : '正式会员',
                        style: TextStyle(
                          color: user.isVip ? Colors.white : theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  final UserProfile user;

  const _StatsSection({required this.user});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Style.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statColumn(context, '动态', user.dynamicCount),
          _statColumn(context, '关注', user.followingCount),
          _statColumn(context, '粉丝', user.followerCount),
          _statColumn(context, '硬币', user.coinCount),
        ],
      ),
    );
  }

  Widget _statColumn(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
