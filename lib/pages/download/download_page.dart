import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/theme/colors.dart';
import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_empty_state.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';
import 'package:winwin/core/shell/app_dialogs.dart';
import 'package:winwin/core/shell/app_scaffold.dart';

/// 打开离线缓存页面。
void showDownloadPage(BuildContext context) {
  Navigator.of(context).push(
    AppRoute<void>(builder: (_) => const DownloadPage()),
  );
}

/// 离线缓存管理页面。
class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  String _cachePath = '加载中...';
  String _cacheSizeStr = '0 MB';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheInfo();
  }

  Future<void> _loadCacheInfo() async {
    try {
      final customPath = GStorage.setting.get(SettingBoxKey.downloadPath) as String?;
      Directory dir;
      if (customPath != null && customPath.isNotEmpty) {
        dir = Directory(customPath);
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        dir = Directory('${docDir.path}/WinWin/downloads');
      }

      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      int totalBytes = 0;
      await for (final file in dir.list(recursive: true, followLinks: false)) {
        if (file is File) {
          totalBytes += await file.length();
        }
      }

      if (mounted) {
        setState(() {
          _cachePath = dir.path;
          _cacheSizeStr = _formatBytes(totalBytes);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cachePath = '默认应用目录';
          _cacheSizeStr = '0 MB';
          _loading = false;
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _clearCache() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理离线缓存'),
        content: const Text('确定要清空已下载的离线缓存文件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final dir = Directory(_cachePath);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          await entity.delete(recursive: true);
        }
      }
      if (mounted) {
        showToast(context, '已清空离线缓存');
        _loadCacheInfo();
      }
    } catch (e) {
      if (mounted) {
        showToast(context, '清空失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;
    final shapes = tokens.shapes;

    return AppScaffold(
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loadCacheInfo,
          icon: AppIcon(AppIcons.refresh(), size: 20),
        ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: biliPink))
          : ListView(
              padding: const EdgeInsets.all(Style.safeSpace),
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(shapes.medium),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppIcon(AppIcons.folder(), color: biliPink, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              '缓存目录与空间',
                              style: tokens.text.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _clearCache,
                              icon: Icon(AppIcons.delete(), size: 16, color: Colors.red),
                              label: const Text('清空', style: TextStyle(color: Colors.red)),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '当前占用：$_cacheSizeStr',
                          style: tokens.text.bodyMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '存放路径：$_cachePath',
                          style: tokens.text.bodySmall?.copyWith(
                            color: cs.outline,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const AppEmptyState(
                  icon: AppIcon(Icons.download_done_outlined),
                  title: '暂无离线缓存视频',
                  subtitle: '视频播放页面下载功能将在后续版本中支持',
                ),
              ],
            ),
    );
  }
}
