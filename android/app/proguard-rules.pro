# OwnPay Console — R8 / ProGuard keep rules for the optimized (minified) release build.
#
# Most plugins ship their own consumer rules; the entries here cover the libraries whose missing
# keeps would break functionality at runtime — chiefly the Google ML Kit barcode scanner used for
# QR pairing (its native pipeline is reached reflectively and obfuscates to short names, so a wrong
# R8 pass surfaces as a native NullPointerException when the camera starts).

# --- Flutter embedding + generated plugin registrant -------------------------------------------
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# --- Google ML Kit barcode scanning (mobile_scanner, unbundled Play-Services variant) ----------
# BarcodeScanning.getClient()/process() reach into these; stripping or renaming them crashes the
# scanner at start (the bug this build fixes). Keep ML Kit + the Play-Services barcode internals.
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# --- CameraX (mobile_scanner camera preview + image analysis) ----------------------------------
-keep class androidx.camera.** { *; }
-keep interface androidx.camera.** { *; }
-dontwarn androidx.camera.**

# --- flutter_local_notifications (serializes notification details via Gson) ---------------------
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-dontwarn com.dexterous.flutterlocalnotifications.**

# --- App native channels referenced by name from AndroidManifest.xml ---------------------------
# (R8 already keeps manifest-declared components; keeping them explicitly survives future refactors.)
-keep class org.ownpay.console.** { *; }

# --- General safety ----------------------------------------------------------------------------
# Enum accessors used reflectively by several plugins (mobile_scanner, etc.).
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
# JNI / native method names must survive obfuscation.
-keepclasseswithmembernames class * {
    native <methods>;
}
-dontwarn kotlinx.coroutines.**
-dontwarn javax.annotation.**
-dontwarn com.google.android.play.core.**
