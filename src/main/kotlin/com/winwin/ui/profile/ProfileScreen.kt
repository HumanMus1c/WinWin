package com.winwin.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.WatchLater
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.winwin.model.mockUser
import com.winwin.theme.BiliDesign
import com.winwin.theme.BiliPink
import com.winwin.theme.iOSBlue
import com.winwin.theme.iOSGreen
import com.winwin.theme.iOSPink
import com.winwin.theme.iOSYellow
import com.winwin.ui.components.IOSClickableItem
import com.winwin.ui.components.IOSDivider
import com.winwin.ui.components.IOSGroup

private data class ProfileService(
    val title: String,
    val icon: ImageVector,
    val tint: Color,
)

private val services = listOf(
    ProfileService("离线缓存", Icons.Filled.Download, iOSBlue),
    ProfileService("历史记录", Icons.Filled.History, iOSBlue),
    ProfileService("我的收藏", Icons.Filled.Bookmark, iOSYellow),
    ProfileService("稍后再看", Icons.Filled.WatchLater, iOSGreen),
    ProfileService("消息中心", Icons.Filled.History, iOSPink),
)

@Composable
fun ProfileScreen(
    modifier: Modifier = Modifier,
) {
    val user = mockUser

    Box(modifier.fillMaxSize()) {
        // ── Background gradient (simulating wallpaper) ──
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        colors = listOf(
                            user.avatarGradient.start.copy(alpha = 0.8f),
                            MaterialTheme.colorScheme.background,
                        ),
                        startY = 0f,
                        endY = 800f,
                    ),
                ),
        )

        // ── Content ──
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                top = 100.dp,
                bottom = 100.dp,
            ),
        ) {
            // User info section
            item {
                UserInfoSection(
                    name = user.name,
                    level = user.level,
                    isVip = user.isVip,
                    avatarGradient = user.avatarGradient,
                )
            }

            // Stats section
            item {
                UserStatsSection(
                    dynamic = user.dynamicCount,
                    following = user.followingCount,
                    follower = user.followerCount,
                    coin = user.coinCount,
                )
            }

            // Services list
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(
                            horizontal = BiliDesign.Spacing.lg,
                            vertical = BiliDesign.Spacing.md,
                        ),
                ) {
                    IOSGroup {
                        services.forEachIndexed { index, service ->
                            IOSClickableItem(
                                icon = service.icon,
                                title = service.title,
                                iconTint = service.tint,
                            )
                            if (index < services.lastIndex) {
                                IOSDivider()
                            }
                        }
                    }
                }
            }

            // Account switch (extra item)
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = BiliDesign.Spacing.lg),
                ) {
                    IOSGroup {
                        IOSClickableItem(
                            icon = Icons.Filled.Download,
                            title = "账号切换",
                            iconTint = MaterialTheme.colorScheme.primary,
                        )
                    }
                }
            }
        }

        // ── Top Bar (centered title) ──
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            color = Color.Transparent,
        ) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "我的",
                    style = MaterialTheme.typography.titleLarge,
                    color = MaterialTheme.colorScheme.onBackground,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun UserInfoSection(
    name: String,
    level: Int,
    isVip: Boolean,
    avatarGradient: com.winwin.theme.GradientPair,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = BiliDesign.Spacing.xl, vertical = BiliDesign.Spacing.lg),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Avatar (72dp circle with gradient)
        Box(
            modifier = Modifier
                .size(72.dp)
                .clip(CircleShape)
                .background(
                    Brush.linearGradient(
                        colors = listOf(avatarGradient.start, avatarGradient.end),
                    ),
                )
                .border(2.dp, Color.White.copy(alpha = 0.3f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Filled.Person,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(32.dp),
            )
        }

        Spacer(Modifier.width(BiliDesign.Spacing.lg))

        // Name + badges
        Column {
            Text(
                text = name,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Spacer(Modifier.height(8.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                // Level badge
                Surface(
                    shape = RoundedCornerShape(4.dp),
                    color = BiliPink,
                ) {
                    Text(
                        text = "LV $level",
                        color = Color.White,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
                    )
                }

                // VIP badge
                Surface(
                    shape = RoundedCornerShape(4.dp),
                    color = if (isVip) BiliPink else MaterialTheme.colorScheme.surfaceVariant,
                ) {
                    Text(
                        text = if (isVip) "大会员" else "正式会员",
                        color = if (isVip) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Medium,
                        modifier = Modifier.padding(horizontal = 6.dp, vertical = 1.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun UserStatsSection(
    dynamic: String,
    following: String,
    follower: String,
    coin: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = BiliDesign.Spacing.md),
        horizontalArrangement = Arrangement.SpaceAround,
    ) {
        StatColumn(label = "动态", value = dynamic)
        StatColumn(label = "关注", value = following)
        StatColumn(label = "粉丝", value = follower)
        StatColumn(label = "硬币", value = coin)
    }
}

@Composable
private fun StatColumn(label: String, value: String) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = value,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onBackground,
        )
        Spacer(Modifier.height(2.dp))
        Text(
            text = label,
            fontSize = 12.sp,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
