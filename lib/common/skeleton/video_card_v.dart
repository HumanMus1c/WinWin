import 'package:flutter/material.dart';
import 'package:winwin/common/skeleton/skeleton.dart';

/// Skeleton placeholder for the vertical video card.
class VideoCardVSkeleton extends StatelessWidget {
  const VideoCardVSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final color = ColorScheme.of(context).onInverseSurface;
    return Skeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 5, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 200, height: 13, color: color),
                Container(
                  height: 13,
                  width: 140,
                  color: color,
                  margin: const EdgeInsets.only(top: 5),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(height: 11, color: color, width: 40),
                    const SizedBox(width: 8),
                    Container(height: 11, color: color, width: 40),
                  ],
                ),
                Container(
                  height: 11,
                  width: 75,
                  color: color,
                  margin: const EdgeInsets.only(top: 5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
