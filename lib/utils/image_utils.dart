import 'package:flutter/material.dart';

/// Image utilities — Bilibili CDN thumbnail URL handling and cache sizing.
abstract final class ImageUtils {
  /// Matches an existing Bilibili CDN thumbnail suffix, e.g.
  /// `@480w_75q.webp` or `@75q.avif`.
  static final _thumbRegex = RegExp(
    r'(@(\d+[a-z]_?)*)(\..*)?$',
    caseSensitive: false,
  );

  /// Builds a Bilibili CDN thumbnail URL.
  ///
  /// - Returns '' when [src] is null.
  /// - [maxQuality] of 100 means the original image (only http→https).
  /// - Otherwise appends `@<quality>q.webp`; if the URL already carries an
  ///   `@...` suffix, the quality segment is inserted before the extension.
  static String thumbnailUrl(String? src, [int maxQuality = 1]) {
    if (src == null) {
      return '';
    }
    if (maxQuality != 100) {
      bool hasMatch = false;
      src = src.splitMapJoin(
        _thumbRegex,
        onMatch: (match) {
          hasMatch = true;
          final String suffix = match.group(3) ?? '.webp';
          return '${match.group(1)}_${maxQuality}q$suffix';
        },
        onNonMatch: (String str) => str,
      );
      if (!hasMatch) {
        src += '@${maxQuality}q.webp';
      }
    }
    return src.replaceFirst('http://', 'https://');
  }

  /// Converts a logical size to a physical pixel size for image
  /// decoding/caching, based on the device pixel ratio.
  static int cacheSize(double px, BuildContext context) {
    return (px * MediaQuery.devicePixelRatioOf(context)).round();
  }
}
