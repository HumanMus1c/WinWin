package com.winwin.theme

import androidx.compose.ui.unit.dp

/**
 * Design system tokens — ported from BiliPai's BiliDesign object.
 * iOS-inspired spacing, radius, and duration values.
 */
object BiliDesign {
    object Spacing {
        val xs = 4.dp
        val sm = 8.dp
        val md = 12.dp
        val lg = 16.dp
        val xl = 24.dp
        val xxl = 32.dp
        val xxxl = 48.dp
    }

    object Radius {
        val xs = 4.dp     // Tiny
        val sm = 6.dp     // ExtraSmall
        val md = 12.dp    // Medium (card)
        val lg = 14.dp    // Large (dialog)
        val xl = 20.dp    // ExtraLarge (sheet)
        val floating = 28.dp // Floating bar
        val full = 100.dp  // Pill / Circle
    }

    object Duration {
        val fast = 150
        val normal = 300
        val slow = 500
        val shimmer = 1200
    }

    object Elevation {
        val none = 0.dp
        val xs = 1.dp
        val sm = 2.dp
        val md = 4.dp
        val lg = 8.dp
        val xl = 16.dp
    }
}
