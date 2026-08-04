package com.winwin.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.winwin.model.mockVideos
import com.winwin.theme.BiliDesign
import com.winwin.theme.coverGradients
import com.winwin.ui.components.VideoCard

private val categories = listOf("推荐", "关注", "热门", "影视", "知识", "游戏", "科技")

@Composable
fun HomeScreen(
    modifier: Modifier = Modifier,
) {
    var selectedCategory by remember { mutableStateOf(0) }

    Box(modifier.fillMaxSize()) {
        // ── Feed Grid ──
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = 120.dp,
                bottom = 100.dp,
                start = BiliDesign.Spacing.sm,
                end = BiliDesign.Spacing.sm,
            ),
            horizontalArrangement = Arrangement.spacedBy(BiliDesign.Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(BiliDesign.Spacing.sm),
        ) {
            items(mockVideos) { video ->
                VideoCard(item = video)
            }
        }

        // ── Floating Top Bar ──
        HomeTopBar(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = BiliDesign.Spacing.lg,
                    vertical = BiliDesign.Spacing.sm,
                ),
        )

        // ── Category Tabs ──
        CategoryTabRow(
            selectedIndex = selectedCategory,
            onSelect = { selectedCategory = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 68.dp),
        )
    }
}

@Composable
private fun HomeTopBar(modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(BiliDesign.Radius.floating),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.72f),
        tonalElevation = 0.dp,
        shadowElevation = BiliDesign.Elevation.sm,
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            MaterialTheme.colorScheme.outline.copy(alpha = 0.1f),
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .padding(horizontal = BiliDesign.Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Avatar
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.linearGradient(
                            colors = listOf(coverGradients[3].start, coverGradients[3].end),
                        ),
                    )
                    .border(1.dp, Color.White.copy(alpha = 0.3f), CircleShape)
                    .clickable { },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Filled.Person,
                    contentDescription = "Avatar",
                    tint = Color.White,
                    modifier = Modifier.size(20.dp),
                )
            }

            Spacer(Modifier.width(12.dp))

            // Search pill
            Surface(
                modifier = Modifier
                    .weight(1f)
                    .height(36.dp),
                shape = RoundedCornerShape(100.dp),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Search,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = "搜索视频、UP主...",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 13.sp,
                    )
                }
            }

            Spacer(Modifier.width(12.dp))

            // Settings icon
            Icon(
                imageVector = Icons.Filled.Settings,
                contentDescription = "Settings",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .clickable { }
                    .padding(7.dp),
            )
        }
    }
}

@Composable
private fun CategoryTabRow(
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()

    Row(
        modifier = modifier
            .horizontalScroll(scrollState)
            .padding(horizontal = BiliDesign.Spacing.lg),
        horizontalArrangement = Arrangement.spacedBy(BiliDesign.Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        categories.forEachIndexed { index, label ->
            val isSelected = index == selectedIndex
            val baseColor = MaterialTheme.colorScheme.primary
            val containerAlpha = if (isSelected) 0.28f else 0f

            Surface(
                shape = RoundedCornerShape(100.dp),
                color = baseColor.copy(alpha = containerAlpha),
            ) {
                Text(
                    text = label,
                    modifier = Modifier
                        .clickable { onSelect(index) }
                        .padding(horizontal = 14.dp, vertical = 6.dp),
                    color = if (isSelected) baseColor else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.78f),
                    fontSize = 13.sp,
                    fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}
