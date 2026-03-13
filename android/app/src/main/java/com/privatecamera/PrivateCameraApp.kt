package com.privatecamera

import android.app.Application
import com.privatecamera.engine.DataPersistenceGuard

class PrivateCameraApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // Verify data persistence on every launch
        DataPersistenceGuard.verifyOnLaunch(this)
    }
}
