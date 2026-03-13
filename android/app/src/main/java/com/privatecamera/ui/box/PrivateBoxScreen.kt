package com.privatecamera.ui.box

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.privatecamera.privacy.SecureStorage
import androidx.compose.foundation.Image

private val primary = Color(0xFFEC5B13)

enum class BoxTab(val label: String) {
    ALL("すべて"),
    VIDEO("ビデオ")
}

@Composable
fun PrivateBoxScreen(
    onNavigateToCamera: () -> Unit
) {
    val context = LocalContext.current
    var selectedTab by remember { mutableStateOf(BoxTab.ALL) }
    var isSelecting by remember { mutableStateOf(false) }
    var selectedIds by remember { mutableStateOf(setOf<String>()) }
    val files = remember { SecureStorage.getInstance(context).listFiles() }

    Column(modifier = Modifier.fillMaxSize()) {
        // Compact Header (tabs + select in one row)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Tab buttons (left-aligned)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                BoxTab.entries.forEach { tab ->
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        modifier = Modifier.clickable { selectedTab = tab }
                    ) {
                        Text(
                            tab.label,
                            fontSize = 14.sp,
                            fontWeight = if (tab == selectedTab) FontWeight.Bold else FontWeight.Medium,
                            color = if (tab == selectedTab) primary else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                        )
                        if (tab == selectedTab) {
                            Spacer(modifier = Modifier.height(2.dp))
                            Box(
                                modifier = Modifier
                                    .width(24.dp)
                                    .height(2.dp)
                                    .background(primary)
                            )
                        }
                    }
                }
            }

            // Select / Done button
            TextButton(onClick = {
                isSelecting = !isSelecting
                if (!isSelecting) selectedIds = emptySet()
            }) {
                Text(
                    if (isSelecting) "完了" else "選択",
                    color = primary,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }

        HorizontalDivider()

        // Grid
        if (files.isEmpty()) {
            // Empty state
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.Lock,
                        contentDescription = null,
                        modifier = Modifier.size(48.dp),
                        tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
                    )
                    Spacer(modifier = Modifier.height(16.dp))
                    Text(
                        "プライベートBOXは空です",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "撮影した写真はここに安全に保存されます",
                        fontSize = 14.sp,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
                    )
                }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Fixed(3),
                modifier = Modifier
                    .weight(1f)
                    .padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp)
            ) {
                items(files) { fileId ->
                    PhotoGridCell(
                        fileId = fileId,
                        isSelecting = isSelecting,
                        isSelected = selectedIds.contains(fileId),
                        onTap = {
                            if (isSelecting) {
                                selectedIds = if (selectedIds.contains(fileId)) {
                                    selectedIds - fileId
                                } else {
                                    selectedIds + fileId
                                }
                            }
                        }
                    )
                }
            }
        }

        // Bottom bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.PhotoLibrary, contentDescription = null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
                Text("アルバム", fontSize = 10.sp)
            }

            FloatingActionButton(
                onClick = onNavigateToCamera,
                containerColor = primary,
                modifier = Modifier.size(48.dp)
            ) {
                Icon(Icons.Default.CameraAlt, contentDescription = "カメラ", tint = Color.White)
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(Icons.Default.Lock, contentDescription = null, tint = primary)
                Text("プライベート", fontSize = 10.sp, color = primary)
            }
        }
    }
}

@Composable
private fun PhotoGridCell(
    fileId: String,
    isSelecting: Boolean,
    isSelected: Boolean,
    onTap: () -> Unit
) {
    val context = LocalContext.current
    val bitmap = remember(fileId) {
        val storage = SecureStorage.getInstance(context)
        val bytes = storage.loadImage(fileId)
        bytes?.let {
            // Decode with downsampling for grid performance
            val opts = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size, opts)
            val targetSize = 300
            var sampleSize = 1
            while (opts.outWidth / sampleSize > targetSize * 2 ||
                opts.outHeight / sampleSize > targetSize * 2) {
                sampleSize *= 2
            }
            val decodeOpts = android.graphics.BitmapFactory.Options().apply { inSampleSize = sampleSize }
            android.graphics.BitmapFactory.decodeByteArray(it, 0, it.size, decodeOpts)
        }
    }

    Box(
        modifier = Modifier
            .aspectRatio(1f)
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .clickable { onTap() }
    ) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize()
            )
        } else {
            Icon(
                Icons.Default.Photo,
                contentDescription = null,
                modifier = Modifier.align(Alignment.Center),
                tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
            )
        }

        if (isSelecting) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(4.dp)
                    .size(20.dp)
                    .clip(CircleShape)
                    .background(if (isSelected) primary else Color.Transparent)
                    .then(
                        if (!isSelected) Modifier.background(Color.White.copy(alpha = 0.3f))
                        else Modifier
                    )
            ) {
                if (isSelected) {
                    Icon(
                        Icons.Default.Check,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier
                            .size(14.dp)
                            .align(Alignment.Center)
                    )
                }
            }
        }
    }
}
