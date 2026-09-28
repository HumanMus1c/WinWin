import 'package:flutter/foundation.dart';

/// 可被 Esc 关闭的二级浮层（OverlayEntry / Stack 伪浮层）登记表。
///
/// 适用于没有路由承载、框架 `ModalRoute` 的 Esc 关闭机制覆盖不到的浮层：
/// 表情面板、弹幕样式浮层、播放器章节面板、音量弹层等。
///
/// 用法：
/// - 浮层打开时调用 [register] 登记“关闭函数”；
/// - 浮层关闭（无论 Esc 还是点外部/点按钮等途径）时调用返回的注销函数；
/// - 全局 Esc 路由器（`AppEscapeScope`）通过 [closeTopmost] 按
///   后进先出（LIFO）关闭最上层浮层，每次 Esc 只消费一个浮层。
///
/// [closeTopmost] 对“已关闭但漏注销”的失效登记自愈剔除，避免浮层
/// 关闭后 Esc 被幽灵登记吞掉。
class EscapeLayerRegistry {
  EscapeLayerRegistry._();

  /// 全局单例。
  static final EscapeLayerRegistry instance = EscapeLayerRegistry._();

  /// 从栈底到栈顶的浮层关闭函数列表（后登记 = 更上层）。
  final List<bool Function()> _layers = <bool Function()>[];

  /// 登记一个已打开的二级浮层。
  ///
  /// [closeIfOpen] 关闭浮层并返回“本次是否真正关闭了一个仍打开的浮层”
  /// （浮层已关闭时应返回 false，由 [closeTopmost] 自愈剔除）。
  ///
  /// 返回的注销函数必须在浮层经其他途径关闭 / 组件 dispose 时调用。
  VoidCallback register(bool Function() closeIfOpen) {
    _layers.add(closeIfOpen);
    return () => _layers.remove(closeIfOpen);
  }

  /// 关闭最上层仍打开的浮层。
  ///
  /// 返回 true 表示本次 Esc 已被该浮层消费；false 表示当前没有打开的浮层。
  bool closeTopmost() {
    while (_layers.isNotEmpty) {
      if (_layers.last()) {
        return true;
      }
      // 浮层已关闭但漏注销：剔除失效登记后继续向下寻找。
      _layers.removeLast();
    }
    return false;
  }
}
