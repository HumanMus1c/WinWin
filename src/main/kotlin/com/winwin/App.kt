package com.winwin

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.winwin.ui.components.AppScreen
import com.winwin.ui.components.FrostedBottomBar
import com.winwin.ui.home.HomeScreen
import com.winwin.ui.profile.ProfileScreen

/**
 * WinWin — Compose Multiplatform Desktop spike for BiliPai port.
 *
 * Verifies:
 * 1. Material 3 components on Desktop
 * 2. iOS-inspired design language fidelity
 * 3. Compose UI patterns (LazyVerticalGrid, state, animation)
 * 4. Haze frosted glass blur integration (pending API verification)
 */
@Composable
fun App() {
    var currentScreen by remember { mutableStateOf(AppScreen.Home) }

    Box(Modifier.fillMaxSize()) {
        // ── Content area ──
        Box(Modifier.fillMaxSize()) {
            when (currentScreen) {
                AppScreen.Home -> HomeScreen()
                AppScreen.Profile -> ProfileScreen()
                AppScreen.Dynamic -> HomeScreen()
                AppScreen.History -> HomeScreen()
                AppScreen.ListenVideo -> HomeScreen()
            }
        }

        // ── Bottom navigation bar ──
        FrostedBottomBar(
            currentScreen = currentScreen,
            onNavigate = { currentScreen = it },
            modifier = Modifier.align(Alignment.BottomCenter),
        )
    }
}
