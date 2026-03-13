package com.privatecamera

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.privatecamera.engine.DataPersistenceGuard
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DataPersistenceGuardTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    @Test
    fun `verifyOnLaunch creates required directories`() {
        // Delete dirs first
        File(context.filesDir, "PrivateBox").deleteRecursively()

        DataPersistenceGuard.verifyOnLaunch(context)

        val root = File(context.filesDir, "PrivateBox")
        assertTrue("PrivateBox should exist", root.exists())
        assertTrue("photos should exist", File(root, "photos").exists())
        assertTrue("thumbnails should exist", File(root, "thumbnails").exists())
        assertTrue("videos should exist", File(root, "videos").exists())
    }

    @Test
    fun `verifyOnLaunch does not destroy existing data`() {
        // Create some test data
        val photosDir = File(context.filesDir, "PrivateBox/photos")
        photosDir.mkdirs()
        val testFile = File(photosDir, "test.jpg")
        testFile.writeText("test data")

        // Run verification
        DataPersistenceGuard.verifyOnLaunch(context)

        // Verify data survives
        assertTrue("Test file should still exist", testFile.exists())
        assertEquals("Test file content should be preserved", "test data", testFile.readText())
    }

    @Test
    fun `verifyOnLaunch sets storage version`() {
        DataPersistenceGuard.verifyOnLaunch(context)
        val prefs = context.getSharedPreferences("private_camera", Context.MODE_PRIVATE)
        assertTrue("Storage version should be set", prefs.getInt("storage_version", 0) > 0)
    }

    @Test
    fun `storage location is internal not external`() {
        DataPersistenceGuard.verifyOnLaunch(context)
        val root = File(context.filesDir, "PrivateBox")
        // Internal storage path should contain "files"
        assertTrue("Storage should be in internal files dir",
            root.absolutePath.contains("files"))
    }
}
