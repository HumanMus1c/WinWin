import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_key.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';

/// 弹幕渲染配置工厂（由 Pref 派生 [DanmakuOption]）。
///
/// ⚠️ 占位实现（由播放器 agent 按契约补建，并行 agent 交付后应覆盖此文件）。
///
/// 屏蔽类型约定（`blockTypes` 内的 int 值）：
/// 0=滚动、1=顶部、2=底部、3=彩色。
abstract final class DanmakuOptions {
  /// 字号基准（窗口 / 全屏），乘以 Pref 字号缩放。
  static const double _fontSizeBase = 15;
  static const double _fontSizeBaseFS = 18;

  static DanmakuOption get({required bool fullscreen, double speed = 1.0}) {
    final blocks = blockTypes;
    final fontScale =
        fullscreen ? Pref.danmakuFontScaleFS : Pref.danmakuFontScale;
    final s = speed <= 0 ? 1.0 : speed;
    // 倍速播放时按比例缩短滚动时长，保持弹幕与视频进度同步。
    final duration = (Pref.danmakuDuration / s).clamp(1.0, 50.0);
    return DanmakuOption(
      fontSize: (fullscreen ? _fontSizeBaseFS : _fontSizeBase) * fontScale,
      fontWeight: Pref.danmakuFontWeight,
      area: GStorage.setting.get(
        SettingBoxKey.danmakuShowArea,
        defaultValue: 1.0,
      ),
      duration: duration,
      hideScroll: blocks.contains(0),
      hideTop: blocks.contains(1),
      hideBottom: blocks.contains(2),
      strokeWidth: Pref.danmakuStrokeWidth,
      lineHeight: Pref.danmakuLineHeight,
    );
  }

  static Set<int> get blockTypes => Pref.danmakuBlockType;

  /// 持久化入口。面板的每次改动已即时写入 GStorage，此处为统一收尾。
  static void save() {
    GStorage.setting.flush();
  }
}
