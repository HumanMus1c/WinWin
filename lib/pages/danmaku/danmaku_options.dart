import 'package:winwin/core/storage/storage.dart';
import 'package:winwin/core/storage/storage_pref.dart';
import 'package:winwin/plugin/canvas_danmaku/canvas_danmaku.dart';

/// 弹幕渲染配置工厂（由 [Pref] 派生 [DanmakuOption]）。
///
/// 移植自 PiliPlus `lib/plugin/pl_player/utils/danmaku_options.dart`。
///
/// **屏蔽类型 value 约定**（`Pref.danmakuBlockType` 内的 int 值，
/// 与 `DanmakuElem.mode` 语义对齐，便于设置面板与过滤逻辑共用）：
///
/// | value | 含义 | 对应 DanmakuOption 字段 |
/// |---|---|---|
/// | 2 | 滚动（mode 1/2/3） | `hideScroll` |
/// | 5 | 顶部（mode 5） | `hideTop` |
/// | 4 | 底部（mode 4） | `hideBottom` |
/// | 7 | 高级（mode 7） | `hideSpecial` |
/// | 6 | 彩色 | `blockColorful`（颜色强制白） |
abstract final class DanmakuOptions {
  /// 字号基准（窗口 / 全屏），乘以 Pref 字号缩放。
  static const double _fontSizeBase = 15;
  static const double _fontSizeBaseFS = 15;

  /// 构造渲染引擎所需的 [DanmakuOption]。
  ///
  /// - [fullscreen]：是否全屏（决定字号缩放取 fontScale 还是 fontScaleFS）。
  /// - [speed]：当前播放倍速。滚动/静态时长按 `基准时长 / speed` 联动，
  ///   保持弹幕视觉速度与视频一致。
  static DanmakuOption get({required bool fullscreen, double speed = 1.0}) {
    final blocks = Pref.danmakuBlockType;
    final fontScale =
        fullscreen ? Pref.danmakuFontScaleFS : Pref.danmakuFontScale;
    final s = speed <= 0 ? 1.0 : speed;
    // 倍速播放时按比例缩短滚动/静态时长，保持弹幕与视频进度同步。
    final duration = (Pref.danmakuDuration / s).clamp(1.0, 50.0);
    final staticDuration = (Pref.danmakuStaticDuration / s).clamp(1.0, 50.0);
    return DanmakuOption(
      fontSize: (fullscreen ? _fontSizeBaseFS : _fontSizeBase) * fontScale,
      fontWeight: Pref.danmakuFontWeight,
      area: Pref.danmakuShowArea,
      duration: duration,
      staticDuration: staticDuration,
      hideScroll: blocks.contains(2),
      hideTop: blocks.contains(5),
      hideBottom: blocks.contains(4),
      hideSpecial: blocks.contains(7),
      strokeWidth: Pref.danmakuStrokeWidth,
      scrollFixedVelocity: Pref.danmakuFixedV,
      massiveMode: Pref.danmakuMassiveMode,
      static2Scroll: Pref.danmakuStatic2Scroll,
      safeArea: true,
      lineHeight: Pref.danmakuLineHeight,
    );
  }

  /// 智能云屏蔽等级（0-11），权重低于该值的弹幕在渲染前丢弃。
  static int get weight => Pref.danmakuWeight;

  /// 是否屏蔽彩色弹幕（强制白色）。
  static bool get blockColorful => Pref.blockColorful;

  /// 是否显示会员渐变彩弹幕。
  static bool get showVipDanmaku => Pref.showVipDanmaku;

  /// 是否合并相同内容弹幕（累加 count）。
  static bool get mergeDanmaku => Pref.mergeDanmaku;

  /// 持久化入口。面板的每次改动已即时写入 GStorage，此处为统一收尾。
  static void save() {
    GStorage.setting.flush();
  }

  /// 批量写入多个设置并 flush（设置面板关闭时调用）。
  static void saveAll(Map<String, dynamic> entries) {
    final box = GStorage.setting;
    for (final entry in entries.entries) {
      box.put(entry.key, entry.value);
    }
    box.flush();
  }
}

/// 屏蔽类型列表（设置面板用，value 与 [DanmakuElem.mode] 语义对齐）。
const blockTypesList = <({int value, String label})>[
  (value: 2, label: '滚动'),
  (value: 5, label: '顶部'),
  (value: 4, label: '底部'),
  (value: 7, label: '高级'),
  (value: 6, label: '彩色'),
];
