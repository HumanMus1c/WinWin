import '../theme/colors.dart';

// ── Video Feed Item ──
class VideoItem {
  final int id;
  final String title;
  final String upName;
  final GradientPair upAvatarGradient;
  final String playCount;
  final String danmakuCount;
  final String duration;
  final GradientPair coverGradient;
  final bool isPremium;

  const VideoItem({
    required this.id,
    required this.title,
    required this.upName,
    required this.upAvatarGradient,
    required this.playCount,
    required this.danmakuCount,
    required this.duration,
    required this.coverGradient,
    this.isPremium = false,
  });
}

// ── User Profile ──
class UserProfile {
  final String name;
  final int level;
  final bool isVip;
  final GradientPair avatarGradient;
  final String dynamicCount;
  final String followingCount;
  final String followerCount;
  final String coinCount;

  const UserProfile({
    required this.name,
    required this.level,
    required this.isVip,
    required this.avatarGradient,
    required this.dynamicCount,
    required this.followingCount,
    required this.followerCount,
    required this.coinCount,
  });
}

// ── Mock Data ──
final mockVideos = [
  VideoItem(id: 1, title: '【4K】用一盏灯改变房间氛围——光影美学教程', upName: '影视飓风', upAvatarGradient: coverGradients[0], playCount: '328.4万', danmakuCount: '2.1万', duration: '12:34', coverGradient: coverGradients[0]),
  VideoItem(id: 2, title: '30天学会Flutter——从零到上线完整App', upName: '技术胖', upAvatarGradient: coverGradients[3], playCount: '156.2万', danmakuCount: '8923', duration: '45:20', coverGradient: coverGradients[3]),
  VideoItem(id: 3, title: '我用100块钱在菜市场做了一桌米其林', upName: '老饭骨', upAvatarGradient: coverGradients[1], playCount: '562.1万', danmakuCount: '3.8万', duration: '08:56', coverGradient: coverGradients[1], isPremium: true),
  VideoItem(id: 4, title: 'NASA最新发现：木卫二可能有生命存在', upName: '科普记录者', upAvatarGradient: coverGradients[6], playCount: '89.3万', danmakuCount: '4521', duration: '15:42', coverGradient: coverGradients[6]),
  VideoItem(id: 5, title: '这首歌太上头了！循环了一整天', upName: '音乐合集', upAvatarGradient: coverGradients[4], playCount: '1024.5万', danmakuCount: '8.9万', duration: '03:48', coverGradient: coverGradients[4]),
  VideoItem(id: 6, title: 'Dart 异步原理：Future 与 Stream 的本质', upName: 'JavaEdge', upAvatarGradient: coverGradients[2], playCount: '45.6万', danmakuCount: '2103', duration: '28:45', coverGradient: coverGradients[2]),
  VideoItem(id: 7, title: '【完整版】2026年跨年晚会全程回放', upName: '晚会频道', upAvatarGradient: coverGradients[7], playCount: '215.6万', danmakuCount: '1.2万', duration: '1:48:30', coverGradient: coverGradients[7]),
  VideoItem(id: 8, title: '自制机械键盘全过程——从零开始的硬核体验', upName: '极客湾', upAvatarGradient: coverGradients[5], playCount: '143.9万', danmakuCount: '7865', duration: '18:27', coverGradient: coverGradients[5]),
  VideoItem(id: 9, title: '用AI生成一整部动画短片（附完整工作流）', upName: 'AI绘画师', upAvatarGradient: coverGradients[0], playCount: '478.2万', danmakuCount: '5.6万', duration: '09:15', coverGradient: coverGradients[0], isPremium: true),
  VideoItem(id: 10, title: '重庆8D魔幻城市探索——我找到了隐秘天桥', upName: '旅行者', upAvatarGradient: coverGradients[3], playCount: '234.7万', danmakuCount: '1.5万', duration: '14:08', coverGradient: coverGradients[3]),
  VideoItem(id: 11, title: 'Flutter RenderObject 深度解析', upName: 'Flutter社区', upAvatarGradient: coverGradients[2], playCount: '67.8万', danmakuCount: '3214', duration: '22:10', coverGradient: coverGradients[2]),
  VideoItem(id: 12, title: '猫猫第一次见到雪，反应太可爱了！', upName: '猫咪日记', upAvatarGradient: coverGradients[4], playCount: '892.3万', danmakuCount: '12.4万', duration: '01:23', coverGradient: coverGradients[4]),
];

final mockUser = UserProfile(
  name: 'WinWin用户',
  level: 5,
  isVip: true,
  avatarGradient: coverGradients[3],
  dynamicCount: '42',
  followingCount: '186',
  followerCount: '23',
  coinCount: '1,248',
);

final mockCategories = ['推荐', '关注', '热门', '影视', '知识', '游戏', '科技'];
