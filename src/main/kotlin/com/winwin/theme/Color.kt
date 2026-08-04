package com.winwin.theme

import androidx.compose.ui.graphics.Color

// ── Bilibili Brand ──
val BiliPink = Color(0xFFFA7298)
val BiliPinkDark = Color(0xFFE45A82)

// ── iOS System Colors ──
val iOSBlue = Color(0xFF007AFF)
val iOSPink = Color(0xFFFF2D55)
val iOSGreen = Color(0xFF34C759)
val iOSOrange = Color(0xFFFF9500)
val iOSYellow = Color(0xFFFFD60A)
val iOSRed = Color(0xFFFF3B30)
val iOSPurple = Color(0xFFAF52DE)
val iOSTeal = Color(0xFF30B0C7)

// ── iOS Gray Scale (Light) ──
val iOSSystemGray = Color(0xFF8E8E93)
val iOSSystemGray2 = Color(0xFFAEAEB2)
val iOSSystemGray3 = Color(0xFFC7C7CC)
val iOSSystemGray4 = Color(0xFFD1D1D6)
val iOSSystemGray5 = Color(0xFFE5E5EA)
val iOSSystemGray6 = Color(0xFFF2F2F7)

// ── Dark Mode ──
val DarkBackground = Color(0xFF0D0D0D)
val DarkSurface = Color(0xFF1A1A1A)
val DarkSurfaceVariant = Color(0xFF262626)
val DarkSurfaceElevated = Color(0xFF2D2D2D)
val DarkTextPrimary = Color(0xFFE8E8E8)
val DarkTextSecondary = Color(0xFFB0B0B0)

// ── Light Mode ──
val LightBackground = iOSSystemGray6
val LightSurface = Color(0xFFFFFFFF)
val LightSurfaceVariant = iOSSystemGray5
val LightTextPrimary = Color(0xFF1C1C1E)
val LightTextSecondary = iOSSystemGray

// ── Bottom Bar Color Palette ──
val BottomBarColors = listOf(
    iOSBlue,      // 0: Home
    iOSOrange,    // 1: Dynamic
    iOSTeal,      // 2: History
    iOSPink,      // 3: Profile
    iOSGreen,     // 4: ListenVideo
    iOSPurple,    // 5: WatchLater
)

// ── Cover Placeholder Gradients (for mock thumbnails) ──
data class GradientPair(val start: Color, val end: Color)

val coverGradients = listOf(
    GradientPair(Color(0xFF6C5CE7), Color(0xFFA36EE8)),
    GradientPair(Color(0xFFE17055), Color(0xFFFDCB6E)),
    GradientPair(Color(0xFF00B894), Color(0xFF55EFC4)),
    GradientPair(Color(0xFF0984E3), Color(0xFF74B9FF)),
    GradientPair(Color(0xFFE84393), Color(0xFFFD79A8)),
    GradientPair(Color(0xFFFAB1A0), Color(0xFFE17055)),
    GradientPair(Color(0xFF2D3436), Color(0xFF636E72)),
    GradientPair(Color(0xFF00CEC9), Color(0xFF55EFC4)),
)
