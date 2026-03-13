package com.privatecamera.privacy

import android.util.Log
import androidx.exifinterface.media.ExifInterface
import com.privatecamera.BuildConfig
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream

/**
 * Strips EXIF metadata (GPS, DateTime, device info, lens details) from images.
 */
object ExifScrubber {

    private const val TAG = "ExifScrubber"

    /** Metadata categories the user can opt to keep. */
    data class ScrubSettings(
        val keepLocation: Boolean = false,
        val keepDateTime: Boolean = false,
        val keepDeviceInfo: Boolean = false
    ) {
        companion object {
            val REMOVE_ALL = ScrubSettings()
        }
    }

    /** Result of a metadata audit. */
    data class MetadataAudit(
        val hasGPS: Boolean,
        val hasDateTime: Boolean,
        val hasDeviceInfo: Boolean,
        val tagCount: Int
    ) {
        val isFullyClean: Boolean get() = !hasGPS && !hasDateTime && !hasDeviceInfo
    }

    // GPS-related EXIF tags
    private val GPS_TAGS = listOf(
        ExifInterface.TAG_GPS_LATITUDE,
        ExifInterface.TAG_GPS_LATITUDE_REF,
        ExifInterface.TAG_GPS_LONGITUDE,
        ExifInterface.TAG_GPS_LONGITUDE_REF,
        ExifInterface.TAG_GPS_ALTITUDE,
        ExifInterface.TAG_GPS_ALTITUDE_REF,
        ExifInterface.TAG_GPS_TIMESTAMP,
        ExifInterface.TAG_GPS_DATESTAMP,
        ExifInterface.TAG_GPS_PROCESSING_METHOD,
        ExifInterface.TAG_GPS_SPEED,
        ExifInterface.TAG_GPS_SPEED_REF,
        ExifInterface.TAG_GPS_DEST_BEARING,
        ExifInterface.TAG_GPS_DEST_BEARING_REF,
        ExifInterface.TAG_GPS_IMG_DIRECTION,
        ExifInterface.TAG_GPS_IMG_DIRECTION_REF
    )

    // DateTime-related EXIF tags
    private val DATETIME_TAGS = listOf(
        ExifInterface.TAG_DATETIME,
        ExifInterface.TAG_DATETIME_ORIGINAL,
        ExifInterface.TAG_DATETIME_DIGITIZED,
        ExifInterface.TAG_OFFSET_TIME,
        ExifInterface.TAG_OFFSET_TIME_ORIGINAL,
        ExifInterface.TAG_OFFSET_TIME_DIGITIZED,
        ExifInterface.TAG_SUBSEC_TIME,
        ExifInterface.TAG_SUBSEC_TIME_ORIGINAL,
        ExifInterface.TAG_SUBSEC_TIME_DIGITIZED
    )

    // Device-identifying EXIF tags
    private val DEVICE_TAGS = listOf(
        ExifInterface.TAG_MAKE,
        ExifInterface.TAG_MODEL,
        ExifInterface.TAG_SOFTWARE,
        ExifInterface.TAG_CAMERA_OWNER_NAME,
        ExifInterface.TAG_BODY_SERIAL_NUMBER,
        ExifInterface.TAG_LENS_MAKE,
        ExifInterface.TAG_LENS_MODEL,
        ExifInterface.TAG_LENS_SERIAL_NUMBER,
        ExifInterface.TAG_LENS_SPECIFICATION
    )

    /**
     * Scrub metadata from JPEG data according to the given settings.
     * Returns new JPEG data with metadata removed.
     */
    fun scrub(jpegData: ByteArray, settings: ScrubSettings = ScrubSettings.REMOVE_ALL): ByteArray {
        val outputStream = ByteArrayOutputStream()
        outputStream.write(jpegData)

        val inputStream = ByteArrayInputStream(outputStream.toByteArray())
        val exif = ExifInterface(inputStream)

        val tagsToRemove = mutableListOf<String>()

        if (!settings.keepLocation) {
            tagsToRemove.addAll(GPS_TAGS)
        }
        if (!settings.keepDateTime) {
            tagsToRemove.addAll(DATETIME_TAGS)
        }
        if (!settings.keepDeviceInfo) {
            tagsToRemove.addAll(DEVICE_TAGS)
        }

        var removedCount = 0
        for (tag in tagsToRemove) {
            if (exif.getAttribute(tag) != null) {
                exif.setAttribute(tag, null)
                removedCount++
            }
        }

        // Write the modified EXIF back
        val resultStream = ByteArrayOutputStream()
        resultStream.write(jpegData)
        val resultInput = ByteArrayInputStream(resultStream.toByteArray())
        val resultExif = ExifInterface(resultInput)

        for (tag in tagsToRemove) {
            resultExif.setAttribute(tag, null)
        }

        // Re-encode with cleaned EXIF
        val finalOutput = ByteArrayOutputStream()
        finalOutput.write(jpegData)

        // For a proper implementation, we need to write through ExifInterface
        // which requires a seekable stream. Use a temp approach:
        val cleaned = removeExifTags(jpegData, tagsToRemove)

        if (BuildConfig.DEBUG) Log.i(TAG, "EXIF scrub: removed $removedCount tags, ${jpegData.size} → ${cleaned.size} bytes")
        return cleaned
    }

    /**
     * Remove specified EXIF tags from JPEG data.
     */
    private fun removeExifTags(jpegData: ByteArray, tagsToRemove: List<String>): ByteArray {
        val tempFile = kotlin.io.path.createTempFile("scrub", ".jpg").toFile()
        try {
            tempFile.writeBytes(jpegData)
            val exif = ExifInterface(tempFile.absolutePath)

            for (tag in tagsToRemove) {
                exif.setAttribute(tag, null)
            }
            exif.saveAttributes()

            return tempFile.readBytes()
        } finally {
            tempFile.delete()
        }
    }

    /**
     * Audit JPEG data and report what metadata is present.
     */
    fun audit(jpegData: ByteArray): MetadataAudit {
        val inputStream = ByteArrayInputStream(jpegData)
        val exif = ExifInterface(inputStream)

        val hasGPS = GPS_TAGS.any { exif.getAttribute(it) != null }
        val hasDateTime = DATETIME_TAGS.any { exif.getAttribute(it) != null }
        val hasDeviceInfo = DEVICE_TAGS.any { exif.getAttribute(it) != null }

        val allTags = GPS_TAGS + DATETIME_TAGS + DEVICE_TAGS
        val tagCount = allTags.count { exif.getAttribute(it) != null }

        return MetadataAudit(
            hasGPS = hasGPS,
            hasDateTime = hasDateTime,
            hasDeviceInfo = hasDeviceInfo,
            tagCount = tagCount
        )
    }

    /**
     * Quick check: does this JPEG have any GPS data?
     */
    fun hasGPS(jpegData: ByteArray): Boolean {
        val inputStream = ByteArrayInputStream(jpegData)
        val exif = ExifInterface(inputStream)
        return exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE) != null
    }
}
