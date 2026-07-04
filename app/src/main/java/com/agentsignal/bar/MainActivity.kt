package com.agentsignal.bar

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import com.agentsignal.bar.overlay.SignalOverlayView
import com.agentsignal.bar.repository.StatusRepository
import com.agentsignal.bar.ui.SettingsScreen

class MainActivity : ComponentActivity() {

    private lateinit var repository: StatusRepository
    private lateinit var overlayView: SignalOverlayView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        repository = StatusRepository(applicationContext)
        overlayView = SignalOverlayView(applicationContext)

        setContent {
            MaterialTheme {
                SettingsScreen(
                    repository = repository,
                    overlayView = overlayView
                )
            }
        }
    }

    override fun onDestroy() {
        overlayView.hide()
        super.onDestroy()
    }
}
