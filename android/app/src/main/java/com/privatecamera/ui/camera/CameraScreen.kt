package com.privatecamera.ui.camera

import android.util.Log
import android.view.ViewGroup
import com.privatecamera.BuildConfig
import android.widget.Toast
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.privatecamera.privacy.SecureStorage
import com.privatecamera.ui.settings.PrivacySettingsManager

private val accentGreen = Color(0xFF44E47E)
private val primary = Color(0xFFEC5B13)
private val backgroundDark = Color(0xFF221610)

enum class CameraMode(val label: String) {
    PHOTO("写真"),
    VIDEO("ビデオ")
}

@Composable
fun CameraScreen(
    onNavigateToBox: () -> Unit,
    onNavigateToSettings: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var currentMode by remember { mutableStateOf(CameraMode.PHOTO) }
    var isRecording by remember { mutableStateOf(false) }
    var useFrontCamera by remember { mutableStateOf(false) }
    var timerDuration by remember { mutableIntStateOf(0) }
    var showTimerPicker by remember { mutableStateOf(false) }
    var isFlashEnabled by remember { mutableStateOf(false) }
    var currentZoom by remember { mutableFloatStateOf(1f) }
    var showCaptureFlash by remember { mutableStateOf(false) }

    // ImageCapture use case — retained across recompositions
    val imageCapture = remember {
        ImageCapture.Builder()
            .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
            .setJpegQuality(95)
            .build()
    }

    // Camera preview reference
    val previewView = remember { PreviewView(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }}

    // Bind camera use cases
    LaunchedEffect(useFrontCamera) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            val cameraProvider = cameraProviderFuture.get()
            val preview = Preview.Builder().build().also {
                it.surfaceProvider = previewView.surfaceProvider
            }
            val cameraSelector = if (useFrontCamera) {
                CameraSelector.DEFAULT_FRONT_CAMERA
            } else {
                CameraSelector.DEFAULT_BACK_CAMERA
            }

            // Update flash mode
            imageCapture.flashMode = if (isFlashEnabled) {
                ImageCapture.FLASH_MODE_ON
            } else {
                ImageCapture.FLASH_MODE_OFF
            }

            try {
                cameraProvider.unbindAll()
                cameraProvider.bindToLifecycle(
                    lifecycleOwner,
                    cameraSelector,
                    preview,
                    imageCapture
                )
            } catch (e: Exception) {
                if (BuildConfig.DEBUG) Log.e("CameraScreen", "カメラの起動に失敗しました", e)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    // Update flash mode when toggled
    LaunchedEffect(isFlashEnabled) {
        imageCapture.flashMode = if (isFlashEnabled) {
            ImageCapture.FLASH_MODE_ON
        } else {
            ImageCapture.FLASH_MODE_OFF
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(backgroundDark)
    ) {
        // Camera Preview
        AndroidView(
            factory = { previewView },
            modifier = Modifier.fillMaxSize()
        )

        // Capture flash overlay
        if (showCaptureFlash) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.White)
            )
            LaunchedEffect(showCaptureFlash) {
                kotlinx.coroutines.delay(100)
                showCaptureFlash = false
            }
        }

        // Header
        CameraHeader(
            isFlashEnabled = isFlashEnabled,
            timerDuration = timerDuration,
            onFlashToggle = { isFlashEnabled = !isFlashEnabled },
            onTimerTap = { showTimerPicker = !showTimerPicker },
            onSettingsTap = onNavigateToSettings,
            modifier = Modifier.align(Alignment.TopCenter)
        )

        // Recording indicator
        if (isRecording) {
            RecordingIndicator(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 80.dp)
            )
        }

        // Timer picker
        AnimatedVisibility(
            visible = showTimerPicker,
            enter = fadeIn() + slideInVertically(),
            exit = fadeOut() + slideOutVertically(),
            modifier = Modifier
                .align(Alignment.TopCenter)
                .padding(top = 100.dp)
        ) {
            TimerPicker(
                selected = timerDuration,
                onSelect = {
                    timerDuration = it
                    showTimerPicker = false
                }
            )
        }

        // Footer
        Column(
            modifier = Modifier.align(Alignment.BottomCenter),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Zoom controls
            ZoomControls(
                currentZoom = currentZoom,
                onZoomChange = { currentZoom = it }
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Mode switcher
            ModeSwitcher(
                currentMode = currentMode,
                onModeChange = { currentMode = it }
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Main controls
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 40.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Box button
                IconButton(
                    onClick = onNavigateToBox,
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.05f))
                ) {
                    Icon(
                        Icons.Default.PhotoLibrary,
                        contentDescription = "BOX",
                        tint = Color.White.copy(alpha = 0.8f)
                    )
                }

                // Shutter
                ShutterButton(
                    mode = currentMode,
                    isRecording = isRecording,
                    onTap = {
                        if (currentMode == CameraMode.VIDEO) {
                            isRecording = !isRecording
                            // TODO: Implement CameraX VideoCapture in future
                        } else {
                            // Photo capture with CameraX ImageCapture
                            showCaptureFlash = true
                            capturePhoto(
                                imageCapture = imageCapture,
                                context = context,
                                onSuccess = {
                                    Toast.makeText(context, "撮影しました", Toast.LENGTH_SHORT).show()
                                },
                                onError = {
                                    Toast.makeText(context, "撮影に失敗しました", Toast.LENGTH_SHORT).show()
                                }
                            )
                        }
                    }
                )

                // Flip camera
                IconButton(
                    onClick = { useFrontCamera = !useFrontCamera },
                    modifier = Modifier
                        .size(48.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.05f))
                ) {
                    Icon(
                        Icons.Default.FlipCameraAndroid,
                        contentDescription = "切替",
                        tint = Color.White.copy(alpha = 0.8f)
                    )
                }
            }

            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}

/**
 * Capture a photo using CameraX ImageCapture, scrub EXIF data, and save to SecureStorage.
 */
private fun capturePhoto(
    imageCapture: ImageCapture,
    context: android.content.Context,
    onSuccess: () -> Unit,
    onError: () -> Unit
) {
    imageCapture.takePicture(
        ContextCompat.getMainExecutor(context),
        object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                try {
                    // Convert ImageProxy to JPEG bytes
                    val buffer = image.planes[0].buffer
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    image.close()

                    // Save to SecureStorage with privacy settings
                    val settings = PrivacySettingsManager.getInstance(context).currentScrubSettings
                    val storage = SecureStorage.getInstance(context)
                    val fileId = storage.saveImage(bytes, settings)

                    if (fileId != null) {
                        if (BuildConfig.DEBUG) Log.i("CameraScreen", "写真を保存しました: $fileId")
                        onSuccess()
                    } else {
                        if (BuildConfig.DEBUG) Log.e("CameraScreen", "写真の保存に失敗しました")
                        onError()
                    }
                } catch (e: Exception) {
                    image.close()
                    if (BuildConfig.DEBUG) Log.e("CameraScreen", "写真の処理中にエラーが発生しました", e)
                    onError()
                }
            }

            override fun onError(exception: ImageCaptureException) {
                if (BuildConfig.DEBUG) Log.e("CameraScreen", "撮影に失敗しました", exception)
                onError()
            }
        }
    )
}

@Composable
private fun CameraHeader(
    isFlashEnabled: Boolean,
    timerDuration: Int,
    onFlashToggle: () -> Unit,
    onTimerTap: () -> Unit,
    onSettingsTap: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 48.dp, start = 16.dp, end = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Flash
        IconButton(onClick = onFlashToggle) {
            Icon(
                if (isFlashEnabled) Icons.Default.FlashOn else Icons.Default.FlashOff,
                contentDescription = "フラッシュ",
                tint = if (isFlashEnabled) primary else Color.White.copy(alpha = 0.8f)
            )
        }

        Row {
            // Timer
            IconButton(onClick = onTimerTap) {
                Box {
                    Icon(
                        Icons.Default.Timer,
                        contentDescription = "タイマー",
                        tint = if (timerDuration > 0) accentGreen else Color.White.copy(alpha = 0.8f)
                    )
                    if (timerDuration > 0) {
                        Text(
                            "$timerDuration",
                            fontSize = 9.sp,
                            fontWeight = FontWeight.Bold,
                            color = accentGreen,
                            modifier = Modifier.align(Alignment.TopEnd)
                        )
                    }
                }
            }

            // Settings
            IconButton(onClick = onSettingsTap) {
                Icon(
                    Icons.Default.Settings,
                    contentDescription = "設定",
                    tint = Color.White.copy(alpha = 0.8f)
                )
            }
        }
    }
}

@Composable
private fun RecordingIndicator(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(Color.Red.copy(alpha = 0.3f))
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(Color.Red)
        )
        Text("REC", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
    }
}

@Composable
private fun TimerPicker(selected: Int, onSelect: (Int) -> Unit) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.6f))
            .padding(horizontal = 20.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        listOf(0 to "オフ", 3 to "3秒", 10 to "10秒").forEach { (value, label) ->
            Text(
                label,
                fontSize = 14.sp,
                fontWeight = if (selected == value) FontWeight.Bold else FontWeight.Medium,
                color = if (selected == value) accentGreen else Color.White.copy(alpha = 0.7f),
                modifier = Modifier.clickable { onSelect(value) }
            )
        }
    }
}

@Composable
private fun ModeSwitcher(currentMode: CameraMode, onModeChange: (CameraMode) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(32.dp)) {
        CameraMode.entries.forEach { mode ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.clickable { onModeChange(mode) }
            ) {
                Text(
                    mode.label,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (mode == currentMode) Color.White else Color.White.copy(alpha = 0.4f)
                )
                Spacer(modifier = Modifier.height(8.dp))
                Box(
                    modifier = Modifier
                        .size(4.dp)
                        .clip(CircleShape)
                        .background(if (mode == currentMode) accentGreen else Color.Transparent)
                )
            }
        }
    }
}

@Composable
private fun ZoomControls(currentZoom: Float, onZoomChange: (Float) -> Unit) {
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50))
            .background(Color.Black.copy(alpha = 0.3f))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        listOf(0.5f to "0.5x", 1f to "1x", 2f to "2x").forEach { (factor, label) ->
            val isActive = kotlin.math.abs(currentZoom - factor) < 0.25f
            Text(
                label,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = if (isActive) accentGreen else Color.White.copy(alpha = 0.6f),
                modifier = Modifier
                    .clip(CircleShape)
                    .background(
                        if (isActive) accentGreen.copy(alpha = 0.15f) else Color.Transparent
                    )
                    .clickable { onZoomChange(factor) }
                    .padding(horizontal = 12.dp, vertical = 6.dp)
            )
        }
    }
}
