package com.privatecamera.engine

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.params.StreamConfigurationMap
import android.graphics.ImageFormat
import android.os.Build
import android.util.Log
import android.util.Size
import com.privatecamera.BuildConfig

/**
 * Discovers and optimizes camera hardware for the current device.
 * Detects all lenses, max resolutions, and capabilities.
 */
class CameraHardwareOptimizer(private val context: Context) {

    companion object {
        private const val TAG = "HardwareOptimizer"
    }

    data class LensInfo(
        val cameraId: String,
        val lensType: LensType,
        val maxJpegResolution: Size,
        val maxYuvResolution: Size,
        val supportedFpsRanges: List<IntArray>,
        val hasAutoFocus: Boolean,
        val hasFlash: Boolean,
        val sensorOrientation: Int,
        val physicalSize: android.util.SizeF?,
        val focalLengths: FloatArray,
        val hasOIS: Boolean,
        val isLogicalMultiCamera: Boolean
    ) {
        enum class LensType(val label: String) {
            ULTRA_WIDE("Ultra Wide"),
            WIDE("Wide"),
            TELEPHOTO("Telephoto"),
            FRONT("Front"),
            UNKNOWN("Unknown")
        }
    }

    data class DeviceSpec(
        val modelName: String,
        val lenses: List<LensInfo>,
        val hasLogicalMultiCamera: Boolean,
        val bestBackCameraId: String?,
        val bestFrontCameraId: String?
    )

    /**
     * Run full hardware discovery and return device specification.
     */
    fun discover(): DeviceSpec {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraIds = cameraManager.cameraIdList
        val lenses = mutableListOf<LensInfo>()
        var hasLogicalMulti = false
        var bestBackId: String? = null
        var bestBackPixels = 0L
        var bestFrontId: String? = null

        if (BuildConfig.DEBUG) {
            Log.i(TAG, "=== Camera Hardware Discovery Start ===")
            Log.i(TAG, "Device: ${Build.MANUFACTURER} ${Build.MODEL}")
            Log.i(TAG, "Camera IDs found: ${cameraIds.size}")
        }

        for (id in cameraIds) {
            val characteristics = cameraManager.getCameraCharacteristics(id)
            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
            val configMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?: continue

            // Max JPEG resolution
            val jpegSizes = configMap.getOutputSizes(ImageFormat.JPEG) ?: emptyArray()
            val maxJpeg = jpegSizes.maxByOrNull { it.width.toLong() * it.height } ?: Size(0, 0)

            // Max YUV resolution
            val yuvSizes = configMap.getOutputSizes(ImageFormat.YUV_420_888) ?: emptyArray()
            val maxYuv = yuvSizes.maxByOrNull { it.width.toLong() * it.height } ?: Size(0, 0)

            // Classify lens type
            val focalLengths = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?: floatArrayOf()
            val lensType = classifyLens(facing, focalLengths)

            // Capabilities
            val afModes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
                ?: intArrayOf()
            val hasAutoFocus = afModes.any { it != CameraCharacteristics.CONTROL_AF_MODE_OFF }
            val hasFlash = characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false

            val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0

            val physicalSize = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)

            // OIS
            val oisModes = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION)
                ?: intArrayOf()
            val hasOIS = oisModes.any { it != CameraCharacteristics.LENS_OPTICAL_STABILIZATION_MODE_OFF }

            // Multi-camera check
            val isLogical = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val caps = characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                    ?: intArrayOf()
                caps.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA)
            } else false

            if (isLogical) hasLogicalMulti = true

            // FPS ranges
            val fpsRanges = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                ?.map { intArrayOf(it.lower, it.upper) } ?: emptyList()

            val info = LensInfo(
                cameraId = id,
                lensType = lensType,
                maxJpegResolution = maxJpeg,
                maxYuvResolution = maxYuv,
                supportedFpsRanges = fpsRanges,
                hasAutoFocus = hasAutoFocus,
                hasFlash = hasFlash,
                sensorOrientation = sensorOrientation,
                physicalSize = physicalSize,
                focalLengths = focalLengths,
                hasOIS = hasOIS,
                isLogicalMultiCamera = isLogical
            )
            lenses.add(info)

            // Track best cameras
            val pixels = maxJpeg.width.toLong() * maxJpeg.height
            if (facing == CameraCharacteristics.LENS_FACING_BACK && pixels > bestBackPixels) {
                bestBackPixels = pixels
                bestBackId = id
            }
            if (facing == CameraCharacteristics.LENS_FACING_FRONT) {
                bestFrontId = id
            }

            if (BuildConfig.DEBUG) {
                Log.i(TAG, buildString {
                    append("  [${lensType.label}] Camera $id\n")
                    append("    Max JPEG: ${maxJpeg.width}x${maxJpeg.height}\n")
                    append("    Max YUV:  ${maxYuv.width}x${maxYuv.height}\n")
                    append("    AF: $hasAutoFocus | Flash: $hasFlash | OIS: $hasOIS\n")
                    append("    Focal: ${focalLengths.joinToString()}\n")
                    append("    Logical Multi: $isLogical")
                })
            }
        }

        if (BuildConfig.DEBUG) Log.i(TAG, "=== Camera Hardware Discovery Complete ===")

        return DeviceSpec(
            modelName = "${Build.MANUFACTURER} ${Build.MODEL}",
            lenses = lenses,
            hasLogicalMultiCamera = hasLogicalMulti,
            bestBackCameraId = bestBackId,
            bestFrontCameraId = bestFrontId
        )
    }

    private fun classifyLens(facing: Int?, focalLengths: FloatArray): LensInfo.LensType {
        if (facing == CameraCharacteristics.LENS_FACING_FRONT) return LensInfo.LensType.FRONT
        if (focalLengths.isEmpty()) return LensInfo.LensType.UNKNOWN

        val primaryFocal = focalLengths.first()
        return when {
            primaryFocal < 2.5f -> LensInfo.LensType.ULTRA_WIDE
            primaryFocal > 5.0f -> LensInfo.LensType.TELEPHOTO
            else -> LensInfo.LensType.WIDE
        }
    }

    /**
     * Get the optimal JPEG output size for the given camera.
     */
    fun getOptimalJpegSize(cameraId: String): Size? {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        val configMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?: return null
        val jpegSizes = configMap.getOutputSizes(ImageFormat.JPEG) ?: return null
        return jpegSizes.maxByOrNull { it.width.toLong() * it.height }
    }
}
