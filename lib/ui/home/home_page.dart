import 'package:flutter/material.dart';
import '../../theme/colors.dart';
import '../../theme/style.dart';
import '../../models/models.dart';
import '../components/video_card.dart';

/// Home page — ported from BiliPai's HomeScreen.
/// Floating top bar, category tabs, video feed grid.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedCategory = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Feed grid ──
          GridView.builder(
            padding: EdgeInsets.only(
              top: 120,
              bottom: 100,
              left: Style.sm,
              right: Style.sm,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: Style.sm,
              mainAxisSpacing: Style.sm,
              childAspectRatio: 0.72,
            ),
            itemCount: mockVideos.length,
            itemBuilder: (context, index) {
              return VideoCard(item: mockVideos[index]);
            },
          ),
          // ── Floating top bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _HomeTopBar(),
          ),
          // ── Category tabs ──
          Positioned(
            top: 68,
            left: 0,
            right: 0,
            child: _CategoryTabRow(
              selectedIndex: _selectedCategory,
              onSelect: (i) => setState(() => _selectedCategory = i),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floating top bar — avatar + search pill + settings icon.
class _HomeTopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Style.lg, vertical: Style.sm),
      child: Container(
        height: Style.topBarHeight,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withOpacity(0.72),
          borderRadius: BorderRadius.circular(Style.radiusFloating),
          border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            Padding(
              padding: const EdgeInsets.only(left: Style.md),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [coverGradients[3].start, coverGradients[3].end],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 12),
            // Search pill
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.search, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      '搜索视频、UP主...',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Settings icon
            Padding(
              padding: const EdgeInsets.only(right: Style.md),
              child: Icon(Icons.settings, color: theme.colorScheme.onSurfaceVariant, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally scrollable category tabs.
class _CategoryTabRow extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _CategoryTabRow({required this.selectedIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Style.lg),
        itemCount: mockCategories.length,
        separatorBuilder: (_, __) => const SizedBox(width: Style.sm),
        itemBuilder: (context, index) {
          final isSelected = index == selectedIndex;
          final baseColor = theme.colorScheme.primary;
          return GestureDetector(
            onTap: () => onSelect(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? baseColor.withOpacity(0.28) : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                mockCategories[index],
                style: TextStyle(
                  color: isSelected
                      ? baseColor
                      : theme.colorScheme.onSurfaceVariant.withOpacity(0.78),
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
