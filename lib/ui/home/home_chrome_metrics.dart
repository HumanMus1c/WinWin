import 'package:flutter/widgets.dart';

import 'package:winwin/theme/style.dart';
import 'package:winwin/ui/components/app_tab_view.dart';

/// 首页合并栏（搜索框 + 一级分类 TAB）的几何单一来源。
///
/// 首页分类 TAB 在宽屏是 32 高的紧凑胶囊轨道、窄屏是 42 高的宽体页签
/// （见 [AppTabForm]），合并栏总高随之变化 10px。页面内容顶部预留必须与
/// 同源，否则窄屏下首屏卡片会被浮动顶栏压住。
///
/// 注意：形态判定按**整窗宽**（[resolveAppTabForm] 内部读 `MediaQuery`），
/// 与 `AppTabStrip` 同一口径，故这里不需要再减顶栏左右内距。
class HomeChromeMetrics {
  const HomeChromeMetrics._();

  /// 搜索框行高（常态假框与搜索态真输入条共用）。
  static const double searchRowHeight = 38;

  /// 搜索框行与分类 TAB 行的间距。
  static const double searchTabGap = 6;

  /// 分类 TAB 行高：宽屏紧凑轨道 / 窄屏宽体页签。
  static const double railTabHeight = 32;
  static const double wideTabHeight = 42;

  /// 宽屏下页面内容顶部预留（含浮动顶栏 + 分类行 + 呼吸位）。
  static const double baseTopReserve = 120;

  /// 宽屏下合并栏“固定部分”基准高。
  ///
  /// 合并栏内容 = 上下内距（[Style.sm] × 2）+ 搜索框行 + 行间 + 分类行；
  /// 旧实现按 `Style.sm × 4 + 38 + 6 + Style.md`（= 88）估算，略小于实际，
  /// 但可用高度只用于 clamp 搜索面板，宽屏保持原口径以免观感漂移。
  static const double baseHeaderFixed = Style.sm * 4 +
      searchRowHeight +
      searchTabGap +
      Style.md;

  /// 当前窗口形态下的分类行高。
  static double tabHeightOf(BuildContext context) =>
      resolveAppTabForm(context) == AppTabForm.wide
          ? wideTabHeight
          : railTabHeight;

  /// 页面内容顶部预留：窄屏比宽屏多出的 10px 自动叠加。
  static double topReserveOf(BuildContext context) =>
      baseTopReserve + (tabHeightOf(context) - railTabHeight);

  /// 搜索态“就地扩充块”的可用高度计算基准（合并栏固定部分高度）。
  static double headerFixedOf(BuildContext context) =>
      baseHeaderFixed + (tabHeightOf(context) - railTabHeight);
}
