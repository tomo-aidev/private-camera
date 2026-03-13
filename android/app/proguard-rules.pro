# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Keep application classes
-keep class com.privatecamera.** { *; }

# AndroidX / Jetpack Compose
-dontwarn androidx.**
-keep class androidx.** { *; }

# CameraX
-keep class androidx.camera.** { *; }

# Security Crypto
-keep class androidx.security.crypto.** { *; }

# Biometric
-keep class androidx.biometric.** { *; }
