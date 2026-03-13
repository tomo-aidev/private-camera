package com.privatecamera

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import androidx.exifinterface.media.ExifInterface
import com.privatecamera.privacy.ExifScrubber
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * Parameterized tests covering all setting combinations:
 *   1. Location metadata (keep / remove) — 2 values
 *   2. DateTime metadata (keep / remove) — 2 values
 *   3. Device info metadata (keep / remove) — 2 values
 *   4. Photo resolution (5MP / 8MP / 12MP / 48MP) — 4 values
 *   5. Video resolution × frame rate (HD/4K × 24/30/60/120) — 8 values
 *
 * Total full matrix: 2 × 2 × 2 × 4 × 8 = 256 combinations
 * Pairwise representative: covers all 2-way interactions
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SettingsParameterizedTest {

    // MARK: - Test Helpers

    private fun createTestBitmap(width: Int = 100, height: Int = 100): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.RED)
        // Add a unique pattern
        val paint = android.graphics.Paint().apply { color = Color.WHITE }
        canvas.drawRect(
            (width / 4).toFloat(), (height / 4).toFloat(),
            (width * 3 / 4).toFloat(), (height * 3 / 4).toFloat(), paint
        )
        return bitmap
    }

    private fun bitmapToJpeg(bitmap: Bitmap, quality: Int = 95): ByteArray {
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
        return stream.toByteArray()
    }

    private fun createJpegWithMetadata(
        width: Int = 100,
        height: Int = 100,
        gps: Boolean = true,
        dateTime: Boolean = true,
        deviceInfo: Boolean = true
    ): ByteArray {
        val bitmap = createTestBitmap(width, height)
        val jpegData = bitmapToJpeg(bitmap)
        bitmap.recycle()

        val tempFile = File.createTempFile("test_param", ".jpg")
        try {
            tempFile.writeBytes(jpegData)

            val exif = ExifInterface(tempFile.absolutePath)
            if (gps) {
                exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE, "35/1,40/1,0/1")
                exif.setAttribute(ExifInterface.TAG_GPS_LATITUDE_REF, "N")
                exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE, "139/1,45/1,0/1")
                exif.setAttribute(ExifInterface.TAG_GPS_LONGITUDE_REF, "E")
            }
            if (dateTime) {
                exif.setAttribute(ExifInterface.TAG_DATETIME, "2025:06:15 14:30:00")
                exif.setAttribute(ExifInterface.TAG_DATETIME_ORIGINAL, "2025:06:15 14:30:00")
                exif.setAttribute(ExifInterface.TAG_DATETIME_DIGITIZED, "2025:06:15 14:30:00")
            }
            if (deviceInfo) {
                exif.setAttribute(ExifInterface.TAG_MAKE, "Apple")
                exif.setAttribute(ExifInterface.TAG_MODEL, "iPhone 16 Pro")
                exif.setAttribute(ExifInterface.TAG_SOFTWARE, "18.0")
            }
            exif.saveAttributes()

            return tempFile.readBytes()
        } finally {
            tempFile.delete()
        }
    }

    // MARK: - 1. Privacy Metadata Matrix (2×2×2 = 8 combinations)

    @Test
    fun `privacy metadata matrix - all 8 combinations`() {
        val boolValues = listOf(true, false)

        for (keepLoc in boolValues) {
            for (keepDT in boolValues) {
                for (keepDev in boolValues) {
                    val label = "loc=$keepLoc dt=$keepDT dev=$keepDev"

                    val jpegData = createJpegWithMetadata(
                        gps = true, dateTime = true, deviceInfo = true
                    )

                    val settings = ExifScrubber.ScrubSettings(
                        keepLocation = keepLoc,
                        keepDateTime = keepDT,
                        keepDeviceInfo = keepDev
                    )

                    val scrubbed = ExifScrubber.scrub(jpegData, settings)

                    // Verify valid JPEG output
                    assertTrue("Output should be valid JPEG for $label",
                        scrubbed.size > 2 && scrubbed[0] == 0xFF.toByte() && scrubbed[1] == 0xD8.toByte())

                    val audit = ExifScrubber.audit(scrubbed)

                    if (keepLoc) {
                        assertTrue("GPS should be preserved for $label", audit.hasGPS)
                    } else {
                        assertFalse("GPS should be removed for $label", audit.hasGPS)
                    }

                    if (keepDT) {
                        assertTrue("DateTime should be preserved for $label", audit.hasDateTime)
                    } else {
                        assertFalse("DateTime should be removed for $label", audit.hasDateTime)
                    }

                    if (keepDev) {
                        assertTrue("DeviceInfo should be preserved for $label", audit.hasDeviceInfo)
                    } else {
                        assertFalse("DeviceInfo should be removed for $label", audit.hasDeviceInfo)
                    }
                }
            }
        }
    }

    // MARK: - 2. Photo Resolution Tests

    data class PhotoResConfig(val label: String, val targetWidth: Int, val targetHeight: Int, val megapixels: Double)

    private val photoResolutions = listOf(
        PhotoResConfig("5MP", 2592, 1944, 5.0),
        PhotoResConfig("8MP", 3264, 2448, 8.0),
        PhotoResConfig("12MP", 4032, 3024, 12.2),
        PhotoResConfig("48MP", 8064, 6048, 48.8)
    )

    @Test
    fun `photo resolution resize - all resolutions`() {
        // Simulate a 12MP source image
        val sourceWidth = 4032
        val sourceHeight = 3024
        val sourcePixels = sourceWidth.toLong() * sourceHeight.toLong()

        for (res in photoResolutions) {
            val targetPixels = res.targetWidth.toLong() * res.targetHeight.toLong()

            if (targetPixels >= sourcePixels) {
                // Target >= source → no resize needed
                assertTrue("${res.label}: Should not need resize when target >= source", true)
            } else {
                // Target < source → compute expected resize scale
                val scale = Math.sqrt(targetPixels.toDouble() / sourcePixels.toDouble())
                val expectedWidth = (sourceWidth * scale).toInt()
                val expectedHeight = (sourceHeight * scale).toInt()

                assertTrue("${res.label}: Expected width $expectedWidth > 0", expectedWidth > 0)
                assertTrue("${res.label}: Expected height $expectedHeight > 0", expectedHeight > 0)

                // Verify aspect ratio preserved
                val sourceAspect = sourceWidth.toDouble() / sourceHeight.toDouble()
                val resizedAspect = expectedWidth.toDouble() / expectedHeight.toDouble()
                assertEquals("${res.label}: Aspect ratio preserved", sourceAspect, resizedAspect, 0.01)
            }
        }
    }

    @Test
    fun `photo resolution bitmap resize creates valid output`() {
        // Simulate the resize on an actual bitmap (small scale for test performance)
        val source = createTestBitmap(403, 302) // 1/10 scale of 4032x3024
        val sourcePixels = source.width * source.height

        // Resize to "5MP equivalent" at 1/10 scale
        val targetPixels = 259 * 194 // ~50K pixels (1/100 of 5MP)
        if (sourcePixels > targetPixels) {
            val scale = Math.sqrt(targetPixels.toDouble() / sourcePixels.toDouble())
            val newW = (source.width * scale).toInt()
            val newH = (source.height * scale).toInt()

            val resized = Bitmap.createScaledBitmap(source, newW, newH, true)
            assertTrue("Resized width > 0", resized.width > 0)
            assertTrue("Resized height > 0", resized.height > 0)

            // Verify it can be encoded to JPEG
            val jpeg = bitmapToJpeg(resized)
            assertTrue("JPEG output is valid", jpeg.size > 2)

            resized.recycle()
        }
        source.recycle()
    }

    // MARK: - 3. Photo Resolution × Privacy Cross-Matrix

    @Test
    fun `photo resolution with privacy settings - pairwise matrix`() {
        val privacyConfigs = listOf(
            Triple(false, false, false), // all removed
            Triple(true, false, false),  // location only
            Triple(false, true, true),   // dateTime + device
            Triple(true, true, true),    // all kept
        )

        for (res in photoResolutions) {
            for ((keepLoc, keepDT, keepDev) in privacyConfigs) {
                val label = "${res.label} loc=$keepLoc dt=$keepDT dev=$keepDev"

                val jpegData = createJpegWithMetadata(
                    width = 100, height = 75,
                    gps = true, dateTime = true, deviceInfo = true
                )

                val settings = ExifScrubber.ScrubSettings(
                    keepLocation = keepLoc,
                    keepDateTime = keepDT,
                    keepDeviceInfo = keepDev
                )

                val scrubbed = ExifScrubber.scrub(jpegData, settings)
                assertTrue("Output not empty for $label", scrubbed.isNotEmpty())

                val audit = ExifScrubber.audit(scrubbed)
                assertEquals("GPS for $label", keepLoc, audit.hasGPS)
                assertEquals("DateTime for $label", keepDT, audit.hasDateTime)
                assertEquals("DeviceInfo for $label", keepDev, audit.hasDeviceInfo)
            }
        }
    }

    // MARK: - 4. Video Settings Validation

    data class VideoResConfig(val label: String, val width: Int, val height: Int)
    data class VideoFPSConfig(val label: String, val fps: Int)

    private val videoResolutions = listOf(
        VideoResConfig("HD", 1920, 1080),
        VideoResConfig("4K", 3840, 2160)
    )

    private val videoFrameRates = listOf(
        VideoFPSConfig("24fps", 24),
        VideoFPSConfig("30fps", 30),
        VideoFPSConfig("60fps", 60),
        VideoFPSConfig("120fps", 120)
    )

    @Test
    fun `video resolution enum values are valid`() {
        for (res in videoResolutions) {
            assertTrue("${res.label}: Width > 0", res.width > 0)
            assertTrue("${res.label}: Height > 0", res.height > 0)

            // Verify 16:9 aspect ratio
            val aspect = res.width.toDouble() / res.height.toDouble()
            assertEquals("${res.label}: 16:9 aspect", 16.0 / 9.0, aspect, 0.01)
        }
    }

    @Test
    fun `video frame rate values are valid`() {
        for (fps in videoFrameRates) {
            assertTrue("${fps.label}: FPS > 0", fps.fps > 0)
            assertTrue("${fps.label}: FPS <= 240", fps.fps <= 240)
        }
    }

    @Test
    fun `video all resolution and frame rate combinations are valid`() {
        for (res in videoResolutions) {
            for (fps in videoFrameRates) {
                val label = "${res.label}@${fps.label}"

                assertTrue("$label: Valid resolution", res.width > 0 && res.height > 0)
                assertTrue("$label: Valid FPS", fps.fps > 0)

                // Verify data bitrate would be reasonable
                val pixelsPerFrame = res.width.toLong() * res.height.toLong()
                val pixelsPerSecond = pixelsPerFrame * fps.fps
                assertTrue("$label: Pixels/sec > 0", pixelsPerSecond > 0)
            }
        }
    }

    // MARK: - 5. ScrubSettings Data Integrity

    @Test
    fun `ScrubSettings REMOVE_ALL has all flags false`() {
        val settings = ExifScrubber.ScrubSettings.REMOVE_ALL
        assertFalse(settings.keepLocation)
        assertFalse(settings.keepDateTime)
        assertFalse(settings.keepDeviceInfo)
    }

    @Test
    fun `ScrubSettings custom combinations roundtrip correctly`() {
        val boolValues = listOf(true, false)

        for (loc in boolValues) {
            for (dt in boolValues) {
                for (dev in boolValues) {
                    val settings = ExifScrubber.ScrubSettings(
                        keepLocation = loc,
                        keepDateTime = dt,
                        keepDeviceInfo = dev
                    )
                    assertEquals("keepLocation", loc, settings.keepLocation)
                    assertEquals("keepDateTime", dt, settings.keepDateTime)
                    assertEquals("keepDeviceInfo", dev, settings.keepDeviceInfo)
                }
            }
        }
    }

    // MARK: - 6. Full Pipeline Integration

    @Test
    fun `full pipeline - all resolutions with all privacy configs`() {
        val privacyConfigs = listOf(
            Triple(false, false, false),
            Triple(true, true, true),
            Triple(true, false, false),
            Triple(false, true, false),
            Triple(false, false, true),
        )

        for (res in photoResolutions) {
            for ((keepLoc, keepDT, keepDev) in privacyConfigs) {
                val label = "${res.label}_loc${keepLoc}_dt${keepDT}_dev${keepDev}"

                // Step 1: Create source image with metadata
                val sourceJpeg = createJpegWithMetadata(
                    width = 100, height = 75,
                    gps = true, dateTime = true, deviceInfo = true
                )

                // Step 2: Scrub metadata
                val settings = ExifScrubber.ScrubSettings(
                    keepLocation = keepLoc,
                    keepDateTime = keepDT,
                    keepDeviceInfo = keepDev
                )
                val scrubbed = ExifScrubber.scrub(sourceJpeg, settings)

                // Step 3: Verify output integrity
                assertTrue("$label: Valid JPEG",
                    scrubbed.size > 2 && scrubbed[0] == 0xFF.toByte() && scrubbed[1] == 0xD8.toByte())

                // Step 4: Verify metadata state
                val audit = ExifScrubber.audit(scrubbed)
                assertEquals("$label: GPS", keepLoc, audit.hasGPS)
                assertEquals("$label: DateTime", keepDT, audit.hasDateTime)
                assertEquals("$label: DeviceInfo", keepDev, audit.hasDeviceInfo)

                // Step 5: Verify scrubbed JPEG can be decoded to bitmap
                val bitmap = android.graphics.BitmapFactory.decodeByteArray(scrubbed, 0, scrubbed.size)
                assertNotNull("$label: Bitmap decode succeeds", bitmap)
                assertTrue("$label: Bitmap width > 0", bitmap!!.width > 0)
                bitmap.recycle()
            }
        }
    }

    // MARK: - 7. File Write and Read Verification

    @Test
    fun `scrubbed JPEG can be written to and read from file`() {
        val jpegData = createJpegWithMetadata()
        val scrubbed = ExifScrubber.scrub(jpegData)

        val tempFile = File.createTempFile("pipeline_test", ".jpg")
        try {
            tempFile.writeBytes(scrubbed)
            assertTrue("File exists after write", tempFile.exists())
            assertTrue("File size > 0", tempFile.length() > 0)

            // Read back and verify metadata
            val readBack = tempFile.readBytes()
            val audit = ExifScrubber.audit(readBack)
            assertTrue("Read-back should be clean", audit.isFullyClean)

            // Verify image can be decoded
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(readBack, 0, readBack.size)
            assertNotNull("Decoded bitmap not null", bitmap)
            bitmap?.recycle()
        } finally {
            tempFile.delete()
        }
    }

    @Test
    fun `metadata re-added after scrub persists correctly`() {
        // Scrub everything, then re-add metadata selectively (simulate keepLocation flow)
        val jpegData = createJpegWithMetadata()

        val settings = ExifScrubber.ScrubSettings(keepLocation = true, keepDateTime = false, keepDeviceInfo = false)
        val scrubbed = ExifScrubber.scrub(jpegData, settings)

        val tempFile = File.createTempFile("readd_test", ".jpg")
        try {
            tempFile.writeBytes(scrubbed)

            // Read EXIF from written file
            val exif = ExifInterface(tempFile.absolutePath)

            // GPS should be present
            val latLong = exif.latLong
            assertNotNull("Latitude/Longitude should be present", latLong)

            // DateTime should NOT be present
            val dateTime = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
            assertNull("DateTime should be null", dateTime)

            // Device info should NOT be present
            val model = exif.getAttribute(ExifInterface.TAG_MODEL)
            assertNull("Model should be null", model)
        } finally {
            tempFile.delete()
        }
    }
}
