package com.privatecamera.engine

import android.content.Context
import android.util.Log
import com.privatecamera.BuildConfig
import java.io.File

/**
 * Ensures photo data survives app updates and development rebuilds.
 *
 * Data is stored in internal storage (context.filesDir), which Android
 * preserves across app updates as long as the package name stays constant.
 *
 * DEVELOPMENT RULE: Never change applicationId "com.privatecamera.app"
 */
object DataPersistenceGuard {

    private const val TAG = "DataPersistence"
    private const val STORAGE_VERSION_KEY = "storage_version"
    private const val CURRENT_STORAGE_VERSION = 1

    fun verifyOnLaunch(context: Context) {
        verifyDirectories(context)
        runMigrationsIfNeeded(context)
        logStorageStats(context)
    }

    private fun verifyDirectories(context: Context) {
        val root = File(context.filesDir, "PrivateBox")
        val dirs = listOf(root, File(root, "photos"), File(root, "thumbnails"), File(root, "videos"))
        for (dir in dirs) {
            if (!dir.exists()) {
                dir.mkdirs()
                if (BuildConfig.DEBUG) Log.i(TAG, "Recreated missing directory: ${dir.name}")
            }
        }
    }

    private fun runMigrationsIfNeeded(context: Context) {
        val prefs = context.getSharedPreferences("private_camera", Context.MODE_PRIVATE)
        val savedVersion = prefs.getInt(STORAGE_VERSION_KEY, 0)

        if (savedVersion < CURRENT_STORAGE_VERSION) {
            if (BuildConfig.DEBUG) Log.i(TAG, "Storage migration: v$savedVersion → v$CURRENT_STORAGE_VERSION")
            // Future migrations here
            prefs.edit().putInt(STORAGE_VERSION_KEY, CURRENT_STORAGE_VERSION).apply()
        }
    }

    private fun logStorageStats(context: Context) {
        val photosDir = File(context.filesDir, "PrivateBox/photos")
        val photoCount = photosDir.listFiles()?.size ?: 0
        val totalSize = File(context.filesDir, "PrivateBox")
            .walkTopDown().filter { it.isFile }.sumOf { it.length() }

        if (BuildConfig.DEBUG) Log.i(TAG, "Storage Status: $photoCount photos, ${totalSize / 1024}KB total")
    }
}
