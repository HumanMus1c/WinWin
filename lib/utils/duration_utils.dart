/// Duration formatting utilities.
abstract final class DurationUtils {
  /// Formats [seconds] as 'MM:SS' or 'HH:MM:SS' (when hours are present).
  static String formatDuration(num? seconds) {
    if (seconds == null || seconds <= 0) {
      return '00:00';
    }
    final int total = seconds.toInt();
    final int h = total ~/ 3600;
    final int m = (total % 3600) ~/ 60;
    final int s = total % 60;
    final String ss = s.toString().padLeft(2, '0');
    final String mm = m.toString().padLeft(2, '0');
    if (h == 0) {
      return '$mm:$ss';
    }
    return '${h.toString().padLeft(2, '0')}:$mm:$ss';
  }
}
