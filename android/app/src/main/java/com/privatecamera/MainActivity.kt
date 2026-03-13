package com.privatecamera

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import com.privatecamera.ui.box.PrivateBoxScreen
import com.privatecamera.ui.camera.CameraScreen
import com.privatecamera.ui.onboarding.OnboardingScreen
import com.privatecamera.ui.onboarding.hasCompletedOnboarding
import com.privatecamera.ui.onboarding.setOnboardingCompleted
import com.privatecamera.ui.settings.SettingsScreen
import com.privatecamera.ui.theme.PrivateCameraTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            PrivateCameraTheme {
                Surface(color = MaterialTheme.colorScheme.background) {
                    AppNavigation()
                }
            }
        }
    }
}

enum class Screen {
    ONBOARDING, CAMERA, SETTINGS, BOX
}

@Composable
fun AppNavigation() {
    val context = LocalContext.current
    var currentScreen by remember {
        mutableStateOf(
            if (hasCompletedOnboarding(context)) Screen.CAMERA else Screen.ONBOARDING
        )
    }

    when (currentScreen) {
        Screen.ONBOARDING -> OnboardingScreen(
            onComplete = {
                setOnboardingCompleted(context)
                currentScreen = Screen.CAMERA
            }
        )
        Screen.CAMERA -> CameraScreen(
            onNavigateToBox = { currentScreen = Screen.BOX },
            onNavigateToSettings = { currentScreen = Screen.SETTINGS }
        )
        Screen.SETTINGS -> SettingsScreen(
            onDismiss = { currentScreen = Screen.CAMERA }
        )
        Screen.BOX -> PrivateBoxScreen(
            onNavigateToCamera = { currentScreen = Screen.CAMERA }
        )
    }
}
