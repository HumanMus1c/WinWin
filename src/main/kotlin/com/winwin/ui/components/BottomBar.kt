package com.winwin.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.winwin.theme.BiliDesign
import com.winwin.theme.BottomBarColors

enum class AppScreen {
    Home, Dynamic, History, ListenVideo, Profile
}

private data class NavItem(
    val screen: AppScreen,
    val label: String,
    val selectedIcon: ImageVector,
    val unselectedIcon: ImageVector,
    val color: Color,
)

private val navItems = listOf(
    NavItem(AppScreen.Home,        "首页",   Icons.Filled.Home,          Icons.Outlined.Home,          BottomBarColors[0]),
    NavItem(AppScreen.Dynamic,     "动态",   Icons.Filled.Notifications,  Icons.Outlined.Notifications, BottomBarColors[1]),
    NavItem(AppScreen.History,     "历史",   Icons.Filled.History,        Icons.Outlined.History,       BottomBarColors[2]),
    NavItem(AppScreen.ListenVideo, "听视频", Icons.Filled.MusicNote,      Icons.Outlined.MusicNote,     BottomBarColors[3]),
    NavItem(AppScreen.Profile,     "我的",   Icons.Filled.Person,         Icons.Outlined.Person,        BottomBarColors[4]),
)

/**
 * FrostedBottomBar — floating pill-shaped navigation bar.
 * Ported from BiliPai's FrostedBottomBar (simplified).
 */
@Composable
fun FrostedBottomBar(
    currentScreen: AppScreen,
    onNavigate: (AppScreen) -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = BiliDesign.Spacing.lg)
            .padding(bottom = BiliDesign.Spacing.lg),
        shape = RoundedCornerShape(BiliDesign.Radius.floating),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.78f),
        tonalElevation = 0.dp,
        shadowElevation = BiliDesign.Elevation.sm,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(60.dp)
                .padding(horizontal = BiliDesign.Spacing.sm),
            horizontalArrangement = Arrangement.SpaceAround,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            navItems.forEach { item ->
                val isSelected = currentScreen == item.screen
                NavItemButton(
                    item = item,
                    isSelected = isSelected,
                    onClick = { onNavigate(item.screen) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun NavItemButton(
    item: NavItem,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val pressScale by animateFloatAsState(
        targetValue = if (isPressed) 0.88f else 1f,
        animationSpec = tween(BiliDesign.Duration.fast),
        label = "nav_scale",
    )

    val iconColor = if (isSelected) item.color else MaterialTheme.colorScheme.onSurfaceVariant
    val labelColor = if (isSelected) item.color else MaterialTheme.colorScheme.onSurfaceVariant

    Column(
        modifier = modifier
            .height(60.dp)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = if (isSelected) item.selectedIcon else item.unselectedIcon,
            contentDescription = item.label,
            tint = iconColor,
            modifier = Modifier
                .size(24.dp)
                .scale(pressScale),
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = item.label,
            color = labelColor,
            fontSize = 10.sp,
            fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}
