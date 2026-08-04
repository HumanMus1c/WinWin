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
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.hazeEffect
import dev.chrisbanes.haze.materials.HazeMaterials

/**
 * WinWin — Compose Multiplatform Desktop spike for BiliPai port.
 *
 * Verifies:
 * 1. Material 3 components on Desktop
 * 2. Haze frosted glass blur on Desktop
 * 3. iOS-inspired design language fidelity
 * 4. Compose UI patterns (LazyVerticalGrid, state, animation)
 */
@Composable
fun App() {
    var currentScreen by remember { mutableStateOf(AppScreen.Home) }
    val hazeState = remember { HazeState() }

    Box(Modifier.fillMaxSize()) {
        // ── Content area (registered as blur source) ──
        Box(
            Modifier
                .fillMaxSize()
                .hazeSource(hazeState)
        ) {
            when (currentScreen) {
                AppScreen.Home -> HomeScreen()
                AppScreen.Profile -> ProfileScreen()
                AppScreen.Dynamic -> HomeScreen()
                AppScreen.History -> HomeScreen()
                AppScreen.ListenVideo -> HomeScreen()
            }
        }

        // ── Bottom navigation bar (blur consumer — frosted glass) ──
        FrostedBottomBar(
            currentScreen = currentScreen,
            onNavigate = { currentScreen = it },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .hazeEffect(hazeState, HazeMaterials.thin()),
        )
    }
}
