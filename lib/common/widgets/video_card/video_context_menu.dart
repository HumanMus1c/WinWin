import 'dart:typed_data' show Uint8List;

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'package:winwin/common/widgets/image/network_img_layer.dart';
import 'package:winwin/common/widgets/miuix_context_menu.dart';
import 'package:winwin/common/widgets/video_card/video_card_adapter.dart';
import 'package:winwin/core/account/accounts.dart';
import 'package:winwin/core/app_messenger.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/http/init.dart';
import 'package:winwin/http/loading_state.dart';
import 'package:winwin/http/member.dart';
import 'package:winwin/http/toview.dart';
import 'package:winwin/http/video.dart';
import 'package:winwin/models/video/rec_video_item.dart';
import 'package:winwin/pages/member/member_space_page.dart';
import 'package:winwin/theme/app_icons.dart';
import 'package:winwin/utils/id_utils.dart';
import 'package:winwin/utils/utils.dart';
import 'package:winwin/core/shell/app_theme_host.dart';
import 'package:winwin/core/shell/app_routes.dart';

String _errMsg(LoadingState state, [String fallback = '操作失败']) {
  if (state is Error) {
    return state.errMsg ?? fallback;
  }
  return fallback;
}

/// 构建视频稿件卡片的交互动作列表（移植自 PiliPlus `VideoPopupMenu`）。
///
/// 图标不设显式尺寸：右键菜单浮层统一按行文本尺寸（bodyMedium）驱动，
/// 保证「图标与选项文本同大小」。
List<ContextMenuAction> buildVideoCardActions({
  required BuildContext context,
  required VideoCardData data,
  dynamic videoItem,
  VoidCallback? onRemove,
}) {
  final actions = <ContextMenuAction>[];
  final bvid = data.bvid;
  final aid = data.aid ?? (bvid != null ? IdUtils.bv2av(bvid) : null);

  // 1. 复制 BV 号
  if (bvid != null && bvid.isNotEmpty) {
    actions.add(
      ContextMenuAction(
        title: Pref.demoMode ? '复制 BV 号' : '复制 BV 号 ($bvid)',
        icon: AppIcon(AppIcons.copy()),
        onTap: () {
          Utils.copyText(bvid);
          showToast(context, '已复制 BV 号：$bvid');
        },
      ),
    );

    // 2. 复制视频链接
    actions.add(
      ContextMenuAction(
        title: '复制视频链接',
        icon: AppIcon(AppIcons.link()),
        onTap: () {
          final url = 'https://www.bilibili.com/video/$bvid';
          Utils.copyText(url);
          showToast(context, '已复制视频链接：$url');
        },
      ),
    );

    // 3. 稍后再看
    actions.add(
      ContextMenuAction(
        title: '稍后再看',
        icon: AppIcon(AppIcons.watchLater()),
        onTap: () async {
          if (!Accounts.main.isLogin) {
            showToast(context, '请先登录');
            return;
          }
          final res = await ToviewHttp.addToview(aid: aid, bvid: bvid);
          if (res.isSuccess) {
            if (context.mounted) {
              showToast(context, '已添加到稍后再看');
            }
          } else {
            if (context.mounted) {
              showToast(context, _errMsg(res, '添加稍后再看失败'));
            }
          }
        },
      ),
    );
  }

  // 4. 访问 UP 主主页
  final mid = data.mid;
  final ownerName = data.ownerName;
  if (mid != null && mid > 0) {
    actions.add(
      ContextMenuAction(
        title: Pref.demoMode ? '访问 UP 主' : '访问 UP 主：${ownerName.isNotEmpty ? ownerName : mid}',
        icon: AppIcon(AppIcons.profile()),
        onTap: () {
          Navigator.push(
            context,
            AppRoute(
              builder: (_) => MemberSpacePage(mid: mid),
            ),
          );
        },
      ),
    );
  }

  // 5. 查看 / 保存封面（演示模式下封面为占位图；对话框内下载动作可安全失败并提示）
  final cover = data.cover;
  if (cover != null && cover.isNotEmpty) {
    actions.add(
      ContextMenuAction(
        title: '查看/保存封面',
        icon: AppIcon(AppIcons.image()),
        onTap: () {
          showVideoCoverDialog(
            context: context,
            title: data.title,
            cover: cover,
            bvid: bvid,
          );
        },
      ),
    );
  }

  // 6. 不感兴趣（支持 App 端 three_point 细分理由与常规点踩）
  final threePoint = data.threePoint;
  final hasDislikeReasons = threePoint != null &&
      ((threePoint.dislikeReasons?.isNotEmpty ?? false) ||
          (threePoint.feedbacks?.isNotEmpty ?? false));

  if (hasDislikeReasons) {
    actions.add(
      ContextMenuAction(
        title: '不感兴趣',
        icon: AppIcon(AppIcons.dislike()),
        onTap: () {
          _showDislikeReasonsDialog(
            context: context,
            data: data,
            onRemove: onRemove,
          );
        },
      ),
    );
  } else if (aid != null || (bvid != null && bvid.isNotEmpty)) {
    actions.add(
      ContextMenuAction(
        title: '不感兴趣',
        icon: AppIcon(AppIcons.dislike()),
        onTap: () async {
          final targetAid = aid ?? (bvid != null ? IdUtils.bv2av(bvid) : null);
          if (targetAid == null) return;
          if (!Accounts.main.isLogin) {
            showToast(context, '请先登录');
            return;
          }
          final res = await VideoHttp.dislikeVideo(aid: targetAid, type: false);
          if (res.isSuccess) {
            if (context.mounted) {
              showToast(context, '已标记不感兴趣，将减少此类推荐');
            }
            onRemove?.call();
          } else {
            if (context.mounted) {
              showToast(context, _errMsg(res, '操作失败'));
            }
          }
        },
      ),
    );
  }

  // 7. 拉黑 UP 主（带二次确认弹窗）
  if (mid != null && mid > 0) {
    actions.add(
      ContextMenuAction(
        title: Pref.demoMode ? '拉黑 UP 主' : '拉黑 UP 主：${ownerName.isNotEmpty ? ownerName : mid}',
        icon: AppIcon(AppIcons.block()),
        onTap: () {
          showDialog(
            context: context,
            builder: (dialogCtx) {
              return AlertDialog(
                title: const Text('提示'),
                content: Text(
                  '确定拉黑 UP 主「${ownerName.isNotEmpty ? ownerName : mid}」($mid)？\n\n'
                  '注：拉黑后将不再向您推荐该 UP 主的稿件。可在「隐私设置 - 黑名单管理」中解除。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: Text(
                      '点错了',
                      style: TextStyle(
                        color: AppThemeHost.of(dialogCtx).colors.outline,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(dialogCtx);
                      final res = await MemberHttp.relationMod(
                        mid: mid,
                        act: 5,
                        reSrc: 11,
                      );
                      if (res.isSuccess) {
                        if (context.mounted) {
                          showToast(context, '已拉黑 UP 主：${ownerName.isNotEmpty ? ownerName : mid}');
                        }
                        onRemove?.call();
                      } else {
                        if (context.mounted) {
                          showToast(context, _errMsg(res, '拉黑失败'));
                        }
                      }
                    },
                    child: const Text('确认拉黑'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  return actions;
}

/// 弹出视频卡片右键/光标位置上下文互动菜单。
Future<void> showVideoContextMenu({
  required BuildContext context,
  required Offset position,
  required VideoCardData data,
  dynamic videoItem,
  VoidCallback? onRemove,
}) async {
  final actions = buildVideoCardActions(
    context: context,
    data: data,
    videoItem: videoItem,
    onRemove: onRemove,
  );

  if (actions.isEmpty) return;

  // 阶段5d-L1：M3 冻结分支（showMenu）已移除，自绘浮层为唯一实现。
  final selectedAction = await showMiuixContextMenu(
    context: context,
    position: position,
    actions: actions,
  );
  selectedAction?.call();
}

/// 视频卡片三点更多按钮（对齐 PiliPlus `VideoPopupMenu`）。
class VideoPopupMenu extends StatelessWidget {
  final VideoCardData data;
  final dynamic videoItem;
  final VoidCallback? onRemove;
  final double iconSize;

  const VideoPopupMenu({
    super.key,
    required this.data,
    this.videoItem,
    this.onRemove,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeHost.of(context);
    final cs = tokens.colors;

    return SizedBox(
      width: 26,
      height: 26,
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: Icon(
          AppIcons.more(),
          size: iconSize,
          color: cs.outline.withValues(alpha: 0.8),
        ),
        tooltip: '更多操作',
        onPressed: () {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null) {
            final pos = box.localToGlobal(Offset(0, box.size.height));
            showVideoContextMenu(
              context: context,
              position: pos,
              data: data,
              videoItem: videoItem,
              onRemove: onRemove,
            );
          }
        },
      ),
    );
  }
}

/// 封面查看与保存对话框（移植自 PiliPlus `imageSaveDialog`，针对桌面端增强另存为存盘）。
void showVideoCoverDialog({
  required BuildContext context,
  required String title,
  required String? cover,
  String? bvid,
}) {
  if (cover == null || cover.isEmpty) return;

  showDialog(
    context: context,
    builder: (dialogCtx) {
      final tokens = AppThemeHost.of(dialogCtx);
      final dialogWidth = (MediaQuery.sizeOf(dialogCtx).width * 0.5).clamp(360.0, 560.0);

      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面图
              AspectRatio(
                aspectRatio: 16 / 10,
                child: NetworkImgLayer(
                  src: cover,
                  width: dialogWidth,
                  height: dialogWidth * 10 / 16,
                ),
              ),
              // 标题与操作栏
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty)
                      SelectableText(
                        title,
                        maxLines: 2,
                        style: tokens.text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // 复制封面链接
                        OutlinedButton.icon(
                          icon: AppIcon(AppIcons.link(), size: 16),
                          label: const Text('复制链接'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            Utils.copyText(cover);
                            showToast(dialogCtx, '已复制封面图片链接');
                          },
                        ),
                        const SizedBox(width: 8),
                        // 另存为图片文件
                        FilledButton.tonalIcon(
                          icon: AppIcon(AppIcons.download(), size: 16),
                          label: const Text('保存封面'),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            final defaultName = '${bvid ?? "cover_${DateTime.now().millisecondsSinceEpoch}"}.jpg';
                            try {
                              final response = await Request().get<List<int>>(
                                cover,
                                options: Options(responseType: ResponseType.bytes),
                              );
                              if (response.data == null || response.data!.isEmpty) {
                                if (dialogCtx.mounted) {
                                  showToast(dialogCtx, '下载封面图片失败');
                                }
                                return;
                              }
                              final fileUri = await FilePicker.saveFile(
                                dialogTitle: '保存封面图片',
                                fileName: defaultName,
                                bytes: Uint8List.fromList(response.data!),
                                type: FileType.image,
                                allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
                              );
                              if (fileUri != null && dialogCtx.mounted) {
                                final savedPath = fileUri.isScheme('file')
                                    ? fileUri.toFilePath()
                                    : fileUri.toString();
                                showToast(dialogCtx, '封面已保存：$savedPath');
                              }
                            } catch (e) {
                              if (dialogCtx.mounted) {
                                showToast(dialogCtx, '保存封面失败：$e');
                              }
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 细分不感兴趣/反馈原因选择弹窗（移植自 PiliPlus `video_popup_menu.dart`）。
void _showDislikeReasonsDialog({
  required BuildContext context,
  required VideoCardData data,
  VoidCallback? onRemove,
}) {
  final tp = data.threePoint;
  if (tp == null) return;

  final dislikeReasons = tp.dislikeReasons ?? [];
  final feedbacks = tp.feedbacks ?? [];
  final goto = data.goto ?? 'av';
  final id = data.param ?? data.aid ?? 0;

  showDialog(
    context: context,
    builder: (dialogCtx) {
      final tokens = AppThemeHost.of(dialogCtx);
      final cs = tokens.colors;

      Widget makeChip(Reason reason, {required bool isFeedback}) {
        return ActionChip(
          label: Text(reason.name ?? '未知'),
          labelStyle: const TextStyle(fontSize: 12),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          onPressed: () async {
            Navigator.pop(dialogCtx);
            final res = await VideoHttp.feedDislike(
              goto: goto,
              id: id,
              reasonId: isFeedback ? null : reason.id,
              feedbackId: isFeedback ? reason.id : null,
            );
            if (res.isSuccess) {
              if (context.mounted) {
                showToast(context, reason.toast ?? '已提交反馈');
              }
              onRemove?.call();
            } else {
              if (context.mounted) {
                showToast(context, _errMsg(res, '提交失败'));
              }
            }
          },
        );
      }

      return SimpleDialog(
        title: const Text('不感兴趣理由', style: TextStyle(fontSize: 16)),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          if (dislikeReasons.isNotEmpty) ...[
            Text('我不想看', style: TextStyle(fontSize: 13, color: cs.primary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: dislikeReasons.map((r) => makeChip(r, isFeedback: false)).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (feedbacks.isNotEmpty) ...[
            Text('反馈问题', style: TextStyle(fontSize: 13, color: cs.primary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: feedbacks.map((r) => makeChip(r, isFeedback: true)).toList(),
            ),
            const SizedBox(height: 12),
          ],
          const Divider(),
          Center(
            child: TextButton.icon(
              icon: AppIcon(AppIcons.undo(), size: 16),
              label: const Text('撤销不感兴趣'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                final res = await VideoHttp.feedDislikeCancel(
                  goto: goto,
                  id: id,
                );
                if (context.mounted) {
                  showToast(context, res.isSuccess ? '已撤销不感兴趣' : _errMsg(res, '撤销失败'));
                }
              },
            ),
          ),
        ],
      );
    },
  );
}
