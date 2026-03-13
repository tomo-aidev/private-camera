package com.privatecamera

import androidx.exifinterface.media.ExifInterface
import com.privatecamera.privacy.ExifScrubber
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ExifScrubberTest {

    private lateinit var testJpegWithMetadata: ByteArray
    private lateinit var testJpegClean: ByteArray

    @Before
    fun setUp() {
        // Create a minimal valid JPEG with EXIF metadata
        testJpegWithMetadata = createTestJpegWithMetadata()
        testJpegClean = createMinimalJpeg()
    }

    // MARK: - Scrub Tests

    @Test
    fun `scrub removes GPS data`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        val audit = ExifScrubber.audit(scrubbed)
        assertFalse("GPS should be removed", audit.hasGPS)
    }

    @Test
    fun `scrub removes DateTime data`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        val audit = ExifScrubber.audit(scrubbed)
        assertFalse("DateTime should be removed", audit.hasDateTime)
    }

    @Test
    fun `scrub removes device info`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        val audit = ExifScrubber.audit(scrubbed)
        assertFalse("Device info should be removed", audit.hasDeviceInfo)
    }

    @Test
    fun `full scrub produces clean output`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        val audit = ExifScrubber.audit(scrubbed)
        assertTrue("Output should be fully clean", audit.isFullyClean)
    }

    @Test
    fun `scrub with keepLocation preserves GPS`() {
        val settings = ExifScrubber.ScrubSettings(keepLocation = true)
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata, settings)
        val audit = ExifScrubber.audit(scrubbed)
        assertTrue("GPS should be preserved when keepLocation=true", audit.hasGPS)
        assertFalse("DateTime should still be removed", audit.hasDateTime)
        assertFalse("Device info should still be removed", audit.hasDeviceInfo)
    }

    @Test
    fun `scrub with keepDateTime preserves DateTime`() {
        val settings = ExifScrubber.ScrubSettings(keepDateTime = true)
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata, settings)
        val audit = ExifScrubber.audit(scrubbed)
        assertFalse("GPS should be removed", audit.hasGPS)
        assertTrue("DateTime should be preserved when keepDateTime=true", audit.hasDateTime)
    }

    @Test
    fun `scrub with keepDeviceInfo preserves device info`() {
        val settings = ExifScrubber.ScrubSettings(keepDeviceInfo = true)
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata, settings)
        val audit = ExifScrubber.audit(scrubbed)
        assertFalse("GPS should be removed", audit.hasGPS)
        assertTrue("Device info should be preserved when keepDeviceInfo=true", audit.hasDeviceInfo)
    }

    // MARK: - Audit Tests

    @Test
    fun `audit detects GPS data`() {
        val audit = ExifScrubber.audit(testJpegWithMetadata)
        assertTrue("Should detect GPS in test image", audit.hasGPS)
    }

    @Test
    fun `audit detects DateTime data`() {
        val audit = ExifScrubber.audit(testJpegWithMetadata)
        assertTrue("Should detect DateTime in test image", audit.hasDateTime)
    }

    @Test
    fun `audit detects device info`() {
        val audit = ExifScrubber.audit(testJpegWithMetadata)
        assertTrue("Should detect device info in test image", audit.hasDeviceInfo)
    }

    @Test
    fun `audit reports clean for scrubbed image`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        val audit = ExifScrubber.audit(scrubbed)
        assertTrue("Scrubbed image should report as fully clean", audit.isFullyClean)
        assertEquals("Tag count should be 0", 0, audit.tagCount)
    }

    // MARK: - hasGPS Tests

    @Test
    fun `hasGPS returns true for image with GPS`() {
        assertTrue("Should detect GPS", ExifScrubber.hasGPS(testJpegWithMetadata))
    }

    @Test
    fun `hasGPS returns false after scrub`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        assertFalse("Should not detect GPS after scrub", ExifScrubber.hasGPS(scrubbed))
    }

    // MARK: - Data Integrity Tests

    @Test
    fun `scrub preserves valid JPEG format`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        // JPEG starts with FFD8
        assertTrue("Output should be valid JPEG",
            scrubbed.size > 2 && scrubbed[0] == 0xFF.toByte() && scrubbed[1] == 0xD8.toByte())
    }

    @Test
    fun `scrub output is not empty`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        assertTrue("Output should not be empty", scrubbed.isNotEmpty())
    }

    @Test
    fun `scrub output is smaller or equal to input`() {
        val scrubbed = ExifScrubber.scrub(testJpegWithMetadata)
        assertTrue("Scrubbed data should be <= original (metadata removed)",
            scrubbed.size <= testJpegWithMetadata.size)
    }

    // MARK: - Settings Tests

    @Test
    fun `REMOVE_ALL settings have all flags false`() {
        val settings = ExifScrubber.ScrubSettings.REMOVE_ALL
        assertFalse(settings.keepLocation)
        assertFalse(settings.keepDateTime)
        assertFalse(settings.keepDeviceInfo)
    }

    // MARK: - Helpers

    /**
     * Create a minimal valid JPEG and inject EXIF metadata via file.
     */
    private fun createTestJpegWithMetadata(): ByteArray {
        val tempFile = File.createTempFile("test_exif", ".jpg")
        try {
            // Write minimal JPEG
            tempFile.writeBytes(createMinimalJpeg())

            // Add EXIF metadata
            val exif = ExifInterface(tempFile.absolutePath)
            // GPS
            exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE, "35/1,40/1,0/1")
            exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
            exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE, "139/1,45/1,0/1")
            exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, "E")
            // DateTime
            exif.setAttribute(ExifInterface.TAG_DATETIME, "2025:01:15 14:30:00")
            exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, "2025:01:15 14:30:00")
            exif.setAttribute(ExifInterface.TAG_DATETIME_DIGITIZED, "2025:01:15 14:30:00")
            // Device info
            exif.setAttribute(ExifInterface.TAG_MAKE, "Apple")
            exif.setAttribute(ExifInterface.TAG_MODEL, "iPhone 16 Pro")
            exif.setAttribute(ExifInterface.TAG_SOFTWARE, "17.2")
            exif.saveAttributes()

            return tempFile.readBytes()
        } finally {
            tempFile.delete()
        }
    }

    /**
     * Create a minimal valid JPEG file (1x1 pixel, white).
     */
    private fun createMinimalJpeg(): ByteArray {
        val bitmap = android.graphics.Bitmap.createBitmap(100, 100, android.graphics.Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        canvas.drawColor(android.graphics.Color.BLUE)
        val stream = ByteArrayOutputStream()
        bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 95, stream)
        bitmap.recycle()
        return stream.toByteArray()
    }
}
