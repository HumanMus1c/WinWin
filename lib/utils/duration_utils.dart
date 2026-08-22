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

  /// Parses a string like '03:45' or '01:23:45' or '120' to seconds integer.
  static int parseDuration(String? str) {
    if (str == null || str.isEmpty) return 0;
    final asInt = int.tryParse(str);
    if (asInt != null) return asInt;
    final parts = str.split(':').map((e) => int.tryParse(e) ?? 0).toList();
    if (parts.length == 2) {
      return parts[0] * 60 + parts[1];
    } else if (parts.length == 3) {
      return parts[0] * 3600 + parts[1] * 60 + parts[2];
    }
    return 0;
  }
}
