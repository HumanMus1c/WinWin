import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:winwin/core/account/account_service.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/account/login_guard.dart';
import 'package:winwin/core/bootstrap.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/http/fav.dart';
import 'package:winwin/http/history.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/toview.dart';
import 'package:winwin/models/fav/fav_models.dart';
import 'package:winwin/models/history/history_models.dart';
import 'package:winwin/models/toview/toview_models.dart';
import 'package:winwin/pages/download/download_page.dart';
import 'package:winwin/pages/fav/fav_page.dart';
import 'package:winwin/pages/history/history_page.dart';
import 'package:winwin/pages/toview/toview_page.dart';
import 'package:winwin/pages/video/detail_page.dart';
import 'package:winwin/ui/components/frosted_bottom_bar.dart';
import 'package:winwin/ui/profile/widgets/profile_horizontal_section.dart';
import 'package:winwin/utils/duration_utils.dart';

// ════════════════════════════════════════════════════════════════
// 1. 离线缓存行 (ProfileDownloadSection)
// ════════════════════════════════════════════════════════════════

class ProfileDownloadSection extends StatefulWidget {
  const ProfileDownloadSection({super.key});

  @override
  State<ProfileDownloadSection> createState() => ProfileDownloadSectionState();
}

class ProfileDownloadSectionState extends State<ProfileDownloadSection> {
  int _downloadCount = 0;
  bool _loading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    if (!mounted) return;
    setState(() => _isRefreshing = true);
    try {
      final customPath = GStorage.setting.get(SettingBoxKey.downloadPath) as String?;
      Directory dir;
      if (customPath != null && customPath.isNotEmpty) {
        dir = Directory(customPath);
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        dir = Directory('${docDir.path}/WinWin/downloads');
      }

      int count = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is Directory || entity is File) {
            count++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _downloadCount = count;
          _loading = false;
          _isRefreshing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _downloadCount = 0;
          _loading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeader(
          title: '离线缓存',
          count: _downloadCount > 0 ? _downloadCount : null,
          onTapTitle: () => showDownloadPage(context),
          onRefresh: reload,
          isRefreshing: _isRefreshing,
        ),
        if (_loading)
          const ProfileCardSkeleton(height: 120)
        else
          ProfileEmptyCard(
            icon: Icons.download_for_offline_outlined,
            message: _downloadCount > 0
                ? '已缓存 $_downloadCount 个项目'
                : '暂无离线缓存视频',
            actionText: '进入离线缓存管理 >',
            onTap: () => showDownloadPage(context),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 2. 我的收藏行 (ProfileFavSection)
// ════════════════════════════════════════════════════════════════

class ProfileFavSection extends StatefulWidget {
  const ProfileFavSection({super.key});

  @override
  State<ProfileFavSection> createState() => ProfileFavSectionState();
}

class ProfileFavSectionState extends State<ProfileFavSection> {
  List<FavFolderInfo> _folders = [];
  int? _totalCount;
  bool _loading = true;
  bool _isRefreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    reload();
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) reload();
  }

  Future<void> reload() async {
    if (!mounted) return;
    await ensureBootstrap();

    if (!Accounts.main.isLogin) {
      if (mounted) {
        setState(() {
          _folders = [];
          _totalCount = null;
          _loading = false;
          _isRefreshing = false;
          _error = '请先登录';
        });
      }
      return;
    }

    setState(() => _isRefreshing = true);
    final mid = Accounts.main.mid;
    final res = await FavHttp.userFavFolder(pn: 1, ps: 10, mid: mid);

    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        setState(() {
          _folders = response.list ?? [];
          _totalCount = response.count ?? _folders.length;
          _loading = false;
          _isRefreshing = false;
          _error = null;
        });
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _isRefreshing = false;
          if (_folders.isEmpty) {
            _error = errMsg ?? '加载失败';
          }
        });
      case Loading():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeader(
          title: '我的收藏',
          count: _totalCount,
          onTapTitle: () => _openFavPage(context),
          onRefresh: reload,
          isRefreshing: _isRefreshing,
        ),
        if (_loading && _folders.isEmpty)
          const ProfileCardSkeleton(height: 165)
        else if (_error == '请先登录')
          ProfileEmptyCard(
            icon: Icons.account_circle_outlined,
            message: '登录后可同步我的收藏',
            actionText: '点击去登录',
            onTap: () => LoginGuard.requireLogin(context),
          )
        else if (_error != null && _folders.isEmpty)
          ProfileEmptyCard(
            icon: Icons.error_outline,
            message: '收藏夹加载失败: $_error',
            actionText: '点击重试',
            onTap: reload,
          )
        else if (_folders.isEmpty)
          ProfileEmptyCard(
            icon: Icons.folder_open_outlined,
            message: '暂无收藏夹',
            actionText: '前往收藏夹 >',
            onTap: () => _openFavPage(context),
          )
        else
          ProfileHorizontalList(
            height: 165,
            itemCount: _folders.length,
            hasMore: (_totalCount ?? 0) > _folders.length,
            onMore: () => _openFavPage(context),
            itemBuilder: (context, index) {
              final item = _folders[index];
              return ProfileFavFolderCard(
                title: item.title,
                cover: item.cover,
                count: item.mediaCount,
                isPublic: item.isPublic,
                heroTag: 'profile_fav_${item.id}',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FavDetailPage(folder: item),
                    ),
                  ).then((_) => reload());
                },
              );
            },
          ),
      ],
    );
  }

  void _openFavPage(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const FavPage()))
        .then((_) => reload());
  }
}

// ════════════════════════════════════════════════════════════════
// 3. 历史记录行 (ProfileHistorySection)
// ════════════════════════════════════════════════════════════════

class ProfileHistorySection extends StatefulWidget {
  const ProfileHistorySection({super.key, this.onNavigate});

  final ValueChanged<AppPage>? onNavigate;

  @override
  State<ProfileHistorySection> createState() => ProfileHistorySectionState();
}

class ProfileHistorySectionState extends State<ProfileHistorySection> {
  List<HistoryItem> _items = [];
  bool _loading = true;
  bool _isRefreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    reload();
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) reload();
  }

  Future<void> reload() async {
    if (!mounted) return;
    await ensureBootstrap();

    if (!Accounts.main.isLogin) {
      if (mounted) {
        setState(() {
          _items = [];
          _loading = false;
          _isRefreshing = false;
          _error = '请先登录';
        });
      }
      return;
    }

    setState(() => _isRefreshing = true);
    final res = await HistoryHttp.historyList(type: 'all', max: null, viewAt: null);

    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        setState(() {
          _items = response.list ?? [];
          _loading = false;
          _isRefreshing = false;
          _error = null;
        });
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _isRefreshing = false;
          if (_items.isEmpty) {
            _error = errMsg ?? '加载失败';
          }
        });
      case Loading():
        break;
    }
  }

  void _gotoHistory(BuildContext context) {
    if (widget.onNavigate != null) {
      widget.onNavigate!(AppPage.history);
    } else {
      showHistoryPage(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeader(
          title: '历史记录',
          onTapTitle: () => _gotoHistory(context),
          onRefresh: reload,
          isRefreshing: _isRefreshing,
        ),
        if (_loading && _items.isEmpty)
          const ProfileCardSkeleton(height: 180)
        else if (_error == '请先登录')
          ProfileEmptyCard(
            icon: Icons.account_circle_outlined,
            message: '登录后可同步观看历史',
            actionText: '点击去登录',
            onTap: () => LoginGuard.requireLogin(context),
          )
        else if (_error != null && _items.isEmpty)
          ProfileEmptyCard(
            icon: Icons.error_outline,
            message: '历史记录加载失败: $_error',
            actionText: '点击重试',
            onTap: reload,
          )
        else if (_items.isEmpty)
          ProfileEmptyCard(
            icon: Icons.history_toggle_off,
            message: '暂无观看历史',
            actionText: '前往查看 >',
            onTap: () => _gotoHistory(context),
          )
        else
          ProfileHorizontalList(
            height: 180,
            itemCount: _items.length,
            hasMore: _items.length >= 10,
            onMore: () => _gotoHistory(context),
            itemBuilder: (context, index) {
              final item = _items[index];
              final duration = item.duration ?? 0;
              final progress = item.progress ?? 0;
              double? fraction;
              if (progress > 0 && duration > 0) {
                fraction = progress / duration;
              } else if (progress == -1) {
                fraction = 1.0;
              }

              String? durationBadge;
              if (duration > 0) {
                durationBadge = DurationUtils.formatDuration(duration);
              }

              String subtitle = item.authorName ?? '';
              if (progress > 0 && duration > 0) {
                subtitle = '看到 ${DurationUtils.formatDuration(progress)} · $subtitle';
              } else if (progress == -1) {
                subtitle = '已看完 · $subtitle';
              }

              final bvid = item.history.bvid ?? '';

              return ProfileVideoCard(
                title: item.title ?? '未知视频',
                cover: item.cover ?? '',
                subtitle: subtitle,
                durationBadge: durationBadge,
                progressFraction: fraction,
                heroTag: bvid.isNotEmpty ? 'profile_history_$bvid' : null,
                onTap: () {
                  if (bvid.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoDetailPage(
                          bvid: bvid,
                          cover: item.cover,
                          heroTag: 'profile_history_$bvid',
                        ),
                      ),
                    ).then((_) => reload());
                  }
                },
              );
            },
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 4. 稍后再看行 (ProfileToviewSection)
// ════════════════════════════════════════════════════════════════

class ProfileToviewSection extends StatefulWidget {
  const ProfileToviewSection({super.key});

  @override
  State<ProfileToviewSection> createState() => ProfileToviewSectionState();
}

class ProfileToviewSectionState extends State<ProfileToviewSection> {
  List<LaterItem> _items = [];
  int? _totalCount;
  bool _loading = true;
  bool _isRefreshing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AccountService().addListener(_onAccountChanged);
    reload();
  }

  @override
  void dispose() {
    AccountService().removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) reload();
  }

  Future<void> reload() async {
    if (!mounted) return;
    await ensureBootstrap();

    if (!Accounts.main.isLogin) {
      if (mounted) {
        setState(() {
          _items = [];
          _totalCount = null;
          _loading = false;
          _isRefreshing = false;
          _error = '请先登录';
        });
      }
      return;
    }

    setState(() => _isRefreshing = true);
    final res = await ToviewHttp.toviewList(page: 1);

    if (!mounted) return;
    switch (res) {
      case Success(:final response):
        setState(() {
          _items = response.list ?? [];
          _totalCount = response.count ?? _items.length;
          _loading = false;
          _isRefreshing = false;
          _error = null;
        });
      case Error(:final errMsg):
        setState(() {
          _loading = false;
          _isRefreshing = false;
          if (_items.isEmpty) {
            _error = errMsg ?? '加载失败';
          }
        });
      case Loading():
        break;
    }
  }

  void _openToviewPage(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const ToviewPage()))
        .then((_) => reload());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeader(
          title: '稍后再看',
          count: _totalCount,
          onTapTitle: () => _openToviewPage(context),
          onRefresh: reload,
          isRefreshing: _isRefreshing,
        ),
        if (_loading && _items.isEmpty)
          const ProfileCardSkeleton(height: 180)
        else if (_error == '请先登录')
          ProfileEmptyCard(
            icon: Icons.account_circle_outlined,
            message: '登录后可查看稍后再看列表',
            actionText: '点击去登录',
            onTap: () => LoginGuard.requireLogin(context),
          )
        else if (_error != null && _items.isEmpty)
          ProfileEmptyCard(
            icon: Icons.error_outline,
            message: '稍后再看加载失败: $_error',
            actionText: '点击重试',
            onTap: reload,
          )
        else if (_items.isEmpty)
          ProfileEmptyCard(
            icon: Icons.watch_later_outlined,
            message: '暂无稍后再看视频',
            actionText: '前往稍后再看 >',
            onTap: () => _openToviewPage(context),
          )
        else
          ProfileHorizontalList(
            height: 180,
            itemCount: _items.length,
            hasMore: (_totalCount ?? 0) > _items.length,
            onMore: () => _openToviewPage(context),
            itemBuilder: (context, index) {
              final item = _items[index];
              final duration = item.duration ?? 0;
              final bvid = item.bvid ?? '';

              String? durationBadge;
              if (duration > 0) {
                durationBadge = DurationUtils.formatDuration(duration);
              }

              return ProfileVideoCard(
                title: item.title ?? '未知视频',
                cover: item.pic ?? '',
                subtitle: item.owner?.name ?? '',
                durationBadge: durationBadge,
                heroTag: bvid.isNotEmpty ? 'profile_toview_$bvid' : null,
                onTap: () {
                  if (bvid.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoDetailPage(
                          bvid: bvid,
                          cover: item.pic,
                          heroTag: 'profile_toview_$bvid',
                        ),
                      ),
                    ).then((_) => reload());
                  }
                },
              );
            },
          ),
      ],
    );
  }
}
