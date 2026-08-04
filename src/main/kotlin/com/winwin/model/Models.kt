package com.winwin.model

import com.winwin.theme.coverGradients
import com.winwin.theme.GradientPair
import kotlin.random.Random

// ── Video Feed Item ──
data class VideoItem(
    val id: Long,
    val title: String,
    val upName: String,
    val upAvatarGradient: GradientPair,
    val playCount: String,
    val danmakuCount: String,
    val duration: String,
    val coverGradient: GradientPair,
    val isPremium: Boolean = false,
)

// ── User Profile ──
data class UserProfile(
    val name: String,
    val level: Int,
    val isVip: Boolean,
    val avatarGradient: GradientPair,
    val dynamicCount: String,
    val followingCount: String,
    val followerCount: String,
    val coinCount: String,
)

// ── Mock Data ──
val mockVideos = listOf(
    VideoItem(1, "【4K】用一盏灯改变房间氛围——光影美学教程", "影视飓风", coverGradients[0], "328.4万", "2.1万", "12:34", coverGradients[0]),
    VideoItem(2, "30天学会Jetpack Compose——从零到上线完整App", "技术胖", coverGradients[3], "156.2万", "8923", "45:20", coverGradients[3]),
    VideoItem(3, "我用100块钱在菜市场做了一桌米其林", "老饭骨", coverGradients[1], "562.1万", "3.8万", "08:56", coverGradients[1], isPremium = true),
    VideoItem(4, "NASA最新发现：木卫二可能有生命存在", "科普记录者", coverGradients[6], "89.3万", "4521", "15:42", coverGradients[6]),
    VideoItem(5, "这首歌太上头了！循环了一整天", "音乐合集", coverGradients[4], "1024.5万", "8.9万", "03:48", coverGradients[4]),
    VideoItem(6, "Android 面试必问：Handler 原理深度解析", "扔物线", coverGradients[2], "67.8万", "3214", "22:10", coverGradients[2]),
    VideoItem(7, "【完整版】2026年跨年晚会全程回放", "晚会频道", coverGradients[7], "215.6万", "1.2万", "1:48:30", coverGradients[7]),
    VideoItem(8, "自制机械键盘全过程——从零开始的硬核体验", "极客湾", coverGradients[5], "143.9万", "7865", "18:27", coverGradients[5]),
    VideoItem(9, "用AI生成一整部动画短片（附完整工作流）", "AI绘画师", coverGradients[0], "478.2万", "5.6万", "09:15", coverGradients[0], isPremium = true),
    VideoItem(10, "重庆8D魔幻城市探索——我找到了隐秘天桥", "旅行者", coverGradients[3], "234.7万", "1.5万", "14:08", coverGradients[3]),
    VideoItem(11, "Kotlin 协程原理：挂起与恢复的本质", "JavaEdge", coverGradients[2], "45.6万", "2103", "28:45", coverGradients[2]),
    VideoItem(12, "猫猫第一次见到雪，反应太可爱了！", "猫咪日记", coverGradients[4], "892.3万", "12.4万", "01:23", coverGradients[4]),
)

val mockUser = UserProfile(
    name = "WinWin用户",
    level = 5,
    isVip = true,
    avatarGradient = coverGradients[3],
    dynamicCount = "42",
    followingCount = "186",
    followerCount = "23",
    coinCount = "1,248",
)
