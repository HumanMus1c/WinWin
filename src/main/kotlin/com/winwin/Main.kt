package com.winwin

import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import com.winwin.theme.WinWinTheme

/**
 * WinWin — Compose Multiplatform Desktop application entry point.
 *
 * Phone-sized window (420 x 880) to simulate mobile UI on desktop.
 */
fun main() = application {
    val windowState = rememberWindowState(
        width = 420.dp,
        height = 880.dp,
    )

    Window(
        onCloseRequest = ::exitApplication,
        title = "WinWin — BiliPai Desktop Spike",
        state = windowState,
    ) {
        WinWinTheme {
            App()
        }
    }
}
