package com.privatecamera.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val privacySettings = remember { PrivacySettingsManager.getInstance(context) }

    var removeLocation by remember { mutableStateOf(privacySettings.removeLocation) }
    var removeDateTime by remember { mutableStateOf(privacySettings.removeDateTime) }
    var removeDeviceInfo by remember { mutableStateOf(privacySettings.removeDeviceInfo) }

    val accentGreen = Color(0xFF44E47E)
    val primary = Color(0xFFEC5B13)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("設定", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(Icons.Default.Close, contentDescription = "閉じる")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp)
        ) {
            // Privacy Section Header
            Text(
                "プライバシー",
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = accentGreen,
                modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
            )

            // Privacy toggles
            SettingsToggle(
                title = "位置情報を含めない",
                subtitle = "GPS座標をEXIFから除外します",
                checked = removeLocation,
                onCheckedChange = {
                    removeLocation = it
                    privacySettings.removeLocation = it
                },
                accentColor = accentGreen
            )

            SettingsToggle(
                title = "日付を含めない",
                subtitle = "撮影日時の情報を除外します",
                checked = removeDateTime,
                onCheckedChange = {
                    removeDateTime = it
                    privacySettings.removeDateTime = it
                },
                accentColor = accentGreen
            )

            SettingsToggle(
                title = "端末情報を含めない",
                subtitle = "機種名・ソフトウェア情報を除外します",
                checked = removeDeviceInfo,
                onCheckedChange = {
                    removeDeviceInfo = it
                    privacySettings.removeDeviceInfo = it
                },
                accentColor = accentGreen
            )

            Text(
                "有効にすると、保存時に該当するEXIFメタデータが自動的に削除されます。",
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f),
                modifier = Modifier.padding(top = 8.dp, bottom = 24.dp)
            )

            HorizontalDivider()

            // App Info Section
            Text(
                "アプリ情報",
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                color = primary,
                modifier = Modifier.padding(top = 16.dp, bottom = 8.dp)
            )

            InfoRow("バージョン", "1.0")
            InfoRow("ビルド", "1")
        }
    }
}

@Composable
private fun SettingsToggle(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    accentColor: Color
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.Medium)
            Text(
                subtitle,
                fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f)
            )
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = accentColor
            )
        )
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, fontSize = 16.sp)
        Text(value, fontSize = 16.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
    }
}
