import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/style.dart';
import '../../models/models.dart';

/// Video card — ported from BiliPai's ElegantVideoCard.
/// 4:3 cover, gradient overlay, stat pills, title, UP name.
class VideoCard extends StatelessWidget {
  final VideoItem item;
  final VoidCallback? onTap;

  const VideoCard({super.key, required this.item, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCover(context),
          const SizedBox(height: 8),
          // Title
          Text(
            item.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // UP name row
          Row(
            children: [
              // UP avatar (mini circle with gradient)
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [item.upAvatarGradient.start, item.upAvatarGradient.end],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  item.upName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCover(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Style.radiusMd),
      child: AspectRatio(
        aspectRatio: Style.cardAspectRatio,
        child: Stack(
          children: [
            // Gradient background
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [item.coverGradient.start, item.coverGradient.end],
                ),
              ),
            ),
            // Bottom gradient mask
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 56,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
                  ),
                ),
              ),
            ),
            // Premium badge (top-right)
            if (item.isPremium)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: biliPink,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '会员',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            // Duration badge (bottom-right)
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.duration,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            // Stat pills (bottom-left)
            Positioned(
              bottom: 4,
              left: 8,
              child: Row(
                children: [
                  _statPill(Icons.play_circle_outline, item.playCount),
                  const SizedBox(width: 10),
                  _statPill(Icons.chat_bubble_outline, item.danmakuCount),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statPill(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white.withOpacity(0.85)),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(color: Colors.white.withOpacity(0.94), fontSize: 11),
        ),
      ],
    );
  }
}
