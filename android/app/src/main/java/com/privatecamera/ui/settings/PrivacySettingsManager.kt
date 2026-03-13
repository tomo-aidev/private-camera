package com.privatecamera.ui.settings

import android.content.Context
import android.content.SharedPreferences
import com.privatecamera.privacy.ExifScrubber

/**
 * Centralized manager for privacy settings.
 * Uses SharedPreferences for persistence and generates ExifScrubber.ScrubSettings.
 */
class PrivacySettingsManager(context: Context) {

    private val prefs: SharedPreferences =
        context.getSharedPreferences("privacy_settings", Context.MODE_PRIVATE)

    /** When true, location data is NOT included in photos (default: true = exclude location) */
    var removeLocation: Boolean
        get() = prefs.getBoolean(KEY_REMOVE_LOCATION, true)
        set(value) = prefs.edit().putBoolean(KEY_REMOVE_LOCATION, value).apply()

    /** When true, date/time data is NOT included in photos (default: false = include date) */
    var removeDateTime: Boolean
        get() = prefs.getBoolean(KEY_REMOVE_DATETIME, false)
        set(value) = prefs.edit().putBoolean(KEY_REMOVE_DATETIME, value).apply()

    /** When true, device info is NOT included in photos (default: false = include device info) */
    var removeDeviceInfo: Boolean
        get() = prefs.getBoolean(KEY_REMOVE_DEVICE_INFO, false)
        set(value) = prefs.edit().putBoolean(KEY_REMOVE_DEVICE_INFO, value).apply()

    /** Generate ExifScrubber.ScrubSettings from current settings.
     *  Note: ScrubSettings uses "keep" semantics, while UI uses "remove" semantics. */
    val currentScrubSettings: ExifScrubber.ScrubSettings
        get() = ExifScrubber.ScrubSettings(
            keepLocation = !removeLocation,
            keepDateTime = !removeDateTime,
            keepDeviceInfo = !removeDeviceInfo
        )

    companion object {
        private const val KEY_REMOVE_LOCATION = "remove_location"
        private const val KEY_REMOVE_DATETIME = "remove_datetime"
        private const val KEY_REMOVE_DEVICE_INFO = "remove_device_info"

        @Volatile
        private var instance: PrivacySettingsManager? = null

        fun getInstance(context: Context): PrivacySettingsManager {
            return instance ?: synchronized(this) {
                instance ?: PrivacySettingsManager(context.applicationContext).also { instance = it }
            }
        }
    }
}
