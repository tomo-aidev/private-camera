package com.privatecamera.ui.camera

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

private val accentGreen = Color(0xFF44E47E)

@Composable
fun ShutterButton(
    mode: CameraMode,
    isRecording: Boolean,
    onTap: () -> Unit
) {
    val scale by animateFloatAsState(
        targetValue = if (isRecording) 1.05f else 1f,
        animationSpec = if (isRecording) {
            infiniteRepeatable(
                animation = tween(800, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse
            )
        } else {
            tween(100)
        },
        label = "shutter_scale"
    )

    val outerRingColor = if (mode == CameraMode.VIDEO) Color.Red else accentGreen
    val mainColor = if (mode == CameraMode.VIDEO) {
        if (isRecording) Color.White.copy(alpha = 0.9f) else Color.Red.copy(alpha = 0.85f)
    } else {
        Color.White
    }

    Box(
        modifier = Modifier
            .size(88.dp)
            .scale(scale)
            .clip(CircleShape)
            .clickable { onTap() },
        contentAlignment = Alignment.Center
    ) {
        // Outer ring
        Box(
            modifier = Modifier
                .size(88.dp)
                .border(3.dp, outerRingColor.copy(alpha = 0.3f), CircleShape)
        )

        // Main circle
        Box(
            modifier = Modifier
                .size(76.dp)
                .clip(CircleShape)
                .background(mainColor)
        )

        // Inner ring or stop square
        if (mode == CameraMode.VIDEO && isRecording) {
            Box(
                modifier = Modifier
                    .size(32.dp)
                    .clip(RoundedCornerShape(8.dp))
                    .background(Color.Red)
            )
        } else {
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .border(2.dp, Color.Black.copy(alpha = 0.05f), CircleShape)
            )
        }
    }
}
