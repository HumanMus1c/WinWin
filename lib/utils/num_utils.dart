/// Number formatting utilities (Bilibili style 万/亿 notation).
abstract final class NumUtils {
  /// Formats [number] into a short human-readable string:
  /// - below 10000: plain number, e.g. '9527'
  /// - 10000 or more: '1.2万'
  /// - 100000000 or more: '3.4亿'
  static String formatNum(int? number) {
    if (number == null) {
      return '0';
    }
    if (number >= 100000000) {
      return _format(number / 100000000, '亿');
    }
    if (number >= 10000) {
      return _format(number / 10000, '万');
    }
    return number.toString();
  }

  static String _format(double value, String unit) {
    final double result = (value * 10).roundToDouble() / 10;
    final int intResult = result.toInt();
    if (result == intResult) {
      return '$intResult$unit';
    }
    return '$result$unit';
  }
}
