import 'package:flutter/foundation.dart';

import 'package:winwin/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';

/// 弹幕数据控制器：预载分段弹幕、按进度供给、本地回显。
///
/// ⚠️ 占位实现（由播放器 agent 按契约补建，并行 agent 交付后应覆盖此文件）：
/// 尚未接入 grpc 弹幕分段拉取，[preload] 为空实现、[getCurrentDanmaku]
/// 返回空列表；[addLocal] 的本地回显逻辑完整可用。
class WinWinDanmakuController {
  WinWinDanmakuController({required this.cid});

  final int cid;

  /// 本地发送弹幕的回显（发送成功后置入，弹幕视图监听后上屏）。
  final ValueNotifier<DanmakuContentItem<DanmakuElem>?> localEcho =
      ValueNotifier(null);

  bool _closed = false;

  /// 服务端是否关闭了该视频的弹幕。
  bool get danmakuClosed => _closed;

  /// 预载弹幕分段。占位实现：不拉取任何数据。
  Future<void> preload() async {
    _closed = false;
  }

  /// 取 [progressMs] 附近应上屏的弹幕。占位实现：返回空列表。
  List<DanmakuContentItem<DanmakuElem>> getCurrentDanmaku(int progressMs) {
    return const [];
  }

  /// 本地发送弹幕回显（mode：1/2/3=滚动，4=底部，5=顶部）。
  void addLocal({required String text, required int mode, int color = 0xFFFFFF}) {
    final elem = DanmakuElem()
      ..content = text
      ..mode = mode
      ..color = color & 0xFFFFFF;
    localEcho.value = DanmakuContentItem<DanmakuElem>(
      text,
      color: Color(0xFF000000 | (color & 0xFFFFFF)),
      type: typeOfMode(mode),
      selfSend: true,
      extra: elem,
    );
  }

  /// 弹幕 mode → 渲染引擎类型（1/2/3=滚动，4=底部，5=顶部，其余按滚动处理）。
  static DanmakuItemType typeOfMode(int mode) => switch (mode) {
    4 => DanmakuItemType.bottom,
    5 => DanmakuItemType.top,
    _ => DanmakuItemType.scroll,
  };

  void dispose() {
    localEcho.dispose();
  }
}
