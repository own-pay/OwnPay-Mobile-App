plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.ownpay.console"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (uses java.time APIs on older Android).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Stable, unique application id for OwnPay Console (also the Play package name).
        applicationId = "org.ownpay.console"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Release is debug-signed for now so `flutter run/build --release` works without the
            // production upload keystore. Swapping in the user's key is a release-time task (see
            // mobile-app/HANDOFF.md) and is independent of the R8 config below.
            signingConfig = signingConfigs.getByName("debug")

            // R8: shrink + optimize + obfuscate the release build. The keep rules that preserve
            // ML Kit, CameraX, the Flutter embedding and the app's manifest-referenced native
            // classes live in proguard-rules.pro — without them R8 would strip the barcode scanner.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // NotificationCompat + foreground-service helpers used by SmsMonitorService.
    implementation("androidx.core:core-ktx:1.13.1")
}
