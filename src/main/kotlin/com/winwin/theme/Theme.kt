package com.winwin.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// iOS-inspired light color scheme
private val LightColorScheme = lightColorScheme(
    primary = iOSBlue,
    onPrimary = Color.White,
    primaryContainer = iOSBlue.copy(alpha = 0.12f),
    onPrimaryContainer = iOSBlue,
    secondary = iOSSystemGray,
    onSecondary = Color.White,
    secondaryContainer = iOSSystemGray5,
    onSecondaryContainer = LightTextPrimary,
    tertiary = BiliPink,
    onTertiary = Color.White,
    background = LightBackground,
    onBackground = LightTextPrimary,
    surface = LightSurface,
    onSurface = LightTextPrimary,
    surfaceVariant = LightSurfaceVariant,
    onSurfaceVariant = LightTextSecondary,
    surfaceTint = iOSBlue,
    outline = iOSSystemGray3,
    outlineVariant = iOSSystemGray4,
    error = iOSRed,
    onError = Color.White,
)

// iOS-inspired dark color scheme
private val DarkColorScheme = darkColorScheme(
    primary = iOSBlue,
    onPrimary = Color.White,
    primaryContainer = iOSBlue.copy(alpha = 0.2f),
    onPrimaryContainer = iOSBlue,
    secondary = iOSSystemGray2,
    onSecondary = Color.Black,
    secondaryContainer = DarkSurfaceVariant,
    onSecondaryContainer = DarkTextPrimary,
    tertiary = BiliPink,
    onTertiary = Color.White,
    background = DarkBackground,
    onBackground = DarkTextPrimary,
    surface = DarkSurface,
    onSurface = DarkTextPrimary,
    surfaceVariant = DarkSurfaceVariant,
    onSurfaceVariant = DarkTextSecondary,
    surfaceTint = iOSBlue,
    outline = iOSSystemGray3,
    outlineVariant = DarkSurfaceVariant,
    error = iOSRed,
    onError = Color.White,
)

@Composable
fun WinWinTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    MaterialTheme(
        colorScheme = colorScheme,
        typography = AppTypography,
        content = content,
    )
}
