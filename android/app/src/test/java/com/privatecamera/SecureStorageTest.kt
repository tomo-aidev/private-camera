package com.privatecamera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.core.app.ApplicationProvider
import com.privatecamera.privacy.ExifScrubber
import com.privatecamera.privacy.SecureStorage
import org.junit.After
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
class SecureStorageTest {

    private lateinit var context: Context
    private lateinit var storage: SecureStorage

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        storage = SecureStorage(context)
    }

    @After
    fun tearDown() {
        // Clean up test data
        File(context.filesDir, "PrivateBox").deleteRecursively()
    }

    // MARK: - Save Tests

    @Test
    fun `saveImage returns non-null file ID`() {
        val jpeg = createTestJpeg()
        val fileId = storage.saveImage(jpeg)
        assertNotNull("Should return a file ID", fileId)
    }

    @Test
    fun `saveImage stores data that can be loaded`() {
        val jpeg = createTestJpeg()
        val fileId = storage.saveImage(jpeg)!!
        val loaded = storage.loadImage(fileId)
        assertNotNull("Should be able to load saved image", loaded)
        assertTrue("Loaded data should not be empty", loaded!!.isNotEmpty())
    }

    @Test
    fun `saved image has EXIF scrubbed by default`() {
        val jpegWithMeta = createTestJpegWithMetadata()
        val fileId = storage.saveImage(jpegWithMeta)!!
        val loaded = storage.loadImage(fileId)!!
        val audit = ExifScrubber.audit(loaded)
        assertTrue("Saved image should have no GPS", !audit.hasGPS)
    }

    @Test
    fun `saveImage with keepLocation preserves GPS`() {
        val jpegWithMeta = createTestJpegWithMetadata()
        val settings = ExifScrubber.ScrubSettings(keepLocation = true)
        val fileId = storage.saveImage(jpegWithMeta, settings)!!
        val loaded = storage.loadImage(fileId)!!
        val audit = ExifScrubber.audit(loaded)
        assertTrue("GPS should be preserved", audit.hasGPS)
    }

    // MARK: - List Tests

    @Test
    fun `listFiles returns empty for new storage`() {
        val files = storage.listFiles()
        assertTrue("New storage should be empty", files.isEmpty())
    }

    @Test
    fun `listFiles returns saved files`() {
        val jpeg = createTestJpeg()
        storage.saveImage(jpeg)
        storage.saveImage(jpeg)
        val files = storage.listFiles()
        assertEquals("Should have 2 files", 2, files.size)
    }

    // MARK: - Delete Tests

    @Test
    fun `deleteImage removes file`() {
        val jpeg = createTestJpeg()
        val fileId = storage.saveImage(jpeg)!!
        assertTrue("Delete should succeed", storage.deleteImage(fileId))
        assertNull("File should not be loadable after delete", storage.loadImage(fileId))
    }

    @Test
    fun `deleteImage reduces file count`() {
        val jpeg = createTestJpeg()
        storage.saveImage(jpeg)
        val fileId = storage.saveImage(jpeg)!!
        assertEquals(2, storage.listFiles().size)
        storage.deleteImage(fileId)
        assertEquals(1, storage.listFiles().size)
    }

    // MARK: - Storage Stats Tests

    @Test
    fun `getPhotoCount returns correct count`() {
        assertEquals(0, storage.getPhotoCount())
        storage.saveImage(createTestJpeg())
        assertEquals(1, storage.getPhotoCount())
        storage.saveImage(createTestJpeg())
        assertEquals(2, storage.getPhotoCount())
    }

    @Test
    fun `getStorageUsage increases with saved images`() {
        val initialSize = storage.getStorageUsage()
        storage.saveImage(createTestJpeg())
        val afterSave = storage.getStorageUsage()
        assertTrue("Storage should increase after save", afterSave > initialSize)
    }

    // MARK: - Data Persistence Tests

    @Test
    fun `storage directory is in internal files dir`() {
        val root = File(context.filesDir, "PrivateBox")
        assertTrue("PrivateBox directory should exist", root.exists())
        assertTrue("photos subdirectory should exist", File(root, "photos").exists())
        assertTrue("thumbnails subdirectory should exist", File(root, "thumbnails").exists())
    }

    @Test
    fun `new SecureStorage instance can read previously saved data`() {
        val jpeg = createTestJpeg()
        val fileId = storage.saveImage(jpeg)!!

        // Create new instance (simulates app restart)
        val newStorage = SecureStorage(context)
        val loaded = newStorage.loadImage(fileId)
        assertNotNull("New instance should read previously saved data", loaded)
    }

    // MARK: - Helpers

    private fun createTestJpeg(): ByteArray {
        val bitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(bitmap)
        canvas.drawColor(Color.BLUE)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 95, stream)
        bitmap.recycle()
        return stream.toByteArray()
    }

    private fun createTestJpegWithMetadata(): ByteArray {
        val tempFile = File.createTempFile("test", ".jpg")
        try {
            tempFile.writeBytes(createTestJpeg())
            val exif = androidx.exifinterface.media.ExifInterface(tempFile.absolutePath)
            exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_GPS_LATITUDE, "35/1,40/1,0/1")
            exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_GPS_LATITUDE_REF, "N")
            exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_GPS_LONGITUDE, "139/1,45/1,0/1")
            exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_GPS_LONGITUDE_REF, "E")
            exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_DATETIME, "2025:01:15 14:30:00")
            exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_MAKE, "Samsung")
            exif.setAttribute(androidx.exifinterface.media.ExifInterface.TAG_MODEL, "Galaxy S24")
            exif.saveAttributes()
            return tempFile.readBytes()
        } finally {
            tempFile.delete()
        }
    }
}
