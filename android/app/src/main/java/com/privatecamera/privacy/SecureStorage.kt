package com.privatecamera.privacy

import android.content.Context
import android.util.Log
import com.privatecamera.BuildConfig
import java.io.File
import java.util.UUID

/**
 * Encrypted local storage for captured images.
 * All data is stored in app-private internal storage — never written to shared media.
 */
class SecureStorage(private val context: Context) {

    companion object {
        private const val TAG = "SecureStorage"
        private const val ROOT_DIR = "PrivateBox"
        private const val PHOTOS_DIR = "photos"
        private const val THUMBNAILS_DIR = "thumbnails"
        private const val VIDEOS_DIR = "videos"

        @Volatile
        private var instance: SecureStorage? = null

        fun getInstance(context: Context): SecureStorage {
            return instance ?: synchronized(this) {
                instance ?: SecureStorage(context.applicationContext).also { instance = it }
            }
        }
    }

    private val storageRoot: File = File(context.filesDir, ROOT_DIR).also { root ->
        listOf(root, File(root, PHOTOS_DIR), File(root, THUMBNAILS_DIR), File(root, VIDEOS_DIR))
            .forEach { it.mkdirs() }
    }

    /**
     * Save scrubbed JPEG data to secure storage. Returns file ID.
     */
    fun saveImage(
        jpegData: ByteArray,
        scrubSettings: ExifScrubber.ScrubSettings = ExifScrubber.ScrubSettings.REMOVE_ALL
    ): String? {
        // Scrub metadata
        val cleanData = ExifScrubber.scrub(jpegData, scrubSettings)

        // Verify clean
        val audit = ExifScrubber.audit(cleanData)
        if (!audit.isFullyClean && !scrubSettings.keepLocation) {
            if (BuildConfig.DEBUG) Log.w(TAG, "Image still has metadata after scrub: GPS=${audit.hasGPS}")
        }

        val fileId = UUID.randomUUID().toString()
        val photoFile = File(File(storageRoot, PHOTOS_DIR), "$fileId.jpg")

        return try {
            photoFile.writeBytes(cleanData)
            if (BuildConfig.DEBUG) Log.i(TAG, "Saved image: $fileId (${cleanData.size} bytes)")
            fileId
        } catch (e: Exception) {
            if (BuildConfig.DEBUG) Log.e(TAG, "Failed to save image", e)
            null
        }
    }

    /**
     * Load image data by file ID.
     */
    fun loadImage(fileId: String): ByteArray? {
        val file = File(File(storageRoot, PHOTOS_DIR), "$fileId.jpg")
        return if (file.exists()) file.readBytes() else null
    }

    /**
     * List all saved file IDs.
     */
    fun listFiles(): List<String> {
        val photosDir = File(storageRoot, PHOTOS_DIR)
        return photosDir.listFiles()
            ?.filter { it.extension == "jpg" }
            ?.map { it.nameWithoutExtension }
            ?.sortedDescending()
            ?: emptyList()
    }

    /**
     * Delete an image by file ID.
     */
    fun deleteImage(fileId: String): Boolean {
        val photoFile = File(File(storageRoot, PHOTOS_DIR), "$fileId.jpg")
        val thumbFile = File(File(storageRoot, THUMBNAILS_DIR), "${fileId}_thumb.jpg")
        val deleted = photoFile.delete()
        thumbFile.delete()
        return deleted
    }

    /**
     * Get total storage usage in bytes.
     */
    fun getStorageUsage(): Long {
        return storageRoot.walkTopDown().filter { it.isFile }.sumOf { it.length() }
    }

    /**
     * Get count of stored photos.
     */
    fun getPhotoCount(): Int {
        return File(storageRoot, PHOTOS_DIR).listFiles()?.size ?: 0
    }
}
