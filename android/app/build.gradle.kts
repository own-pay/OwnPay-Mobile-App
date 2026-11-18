import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: the upload key is a release-time secret and must never live in git.
// Copy keystore.properties.example to keystore.properties and fill it in (locally or from CI
// secrets). Debug builds keep the debug keystore. Release builds without keystore.properties
// fail fast with a clear message instead of silently shipping a debug-signed artifact.
val keystorePropertiesFile = rootProject.file("keystore.properties")

android {
    namespace = "org.ownpay.console"
    // Android 17 = API 37. Flutter 3.x ships with compileSdk 36 as its default;
    // pin 37 explicitly so the release targets the latest stable platform.
    compileSdk = 37
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
        // Android 17 = API 37. Explicitly overrides flutter.targetSdkVersion (36 on Flutter 3.50).
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "Release signing is not configured: android/keystore.properties is missing. " +
                        "Copy keystore.properties.example to keystore.properties and provide the " +
                        "OwnPay Console upload key, or build a debug artifact instead.",
                )
            }
            val props = Properties()
            keystorePropertiesFile.inputStream().use { props.load(it) }
            fun required(name: String): String =
                props.getProperty(name)?.takeIf { it.isNotBlank() }
                    ?: throw GradleException("keystore.properties is missing required entry '$name'.")
            storeFile = rootProject.file(required("storeFile"))
            storePassword = required("storePassword")
            keyAlias = required("keyAlias")
            keyPassword = required("keyPassword")
        }
    }

    buildTypes {
        release {
            // Release is signed with the OwnPay Console upload key (release-time secret).
            signingConfig = signingConfigs.getByName("release")

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
