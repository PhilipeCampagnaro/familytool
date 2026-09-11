import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key, kept out of the repository.
//
// `android/key.properties` holds `storeFile`, `storePassword`, `keyAlias` and
// `keyPassword` and is gitignored along with the keystore itself; the keystore
// is the one thing in this project that cannot be regenerated — lose it and the
// app can never be updated under the same Play listing again, only re-published
// as a new app with every install lost. Play App Signing takes a copy, which is
// worth enrolling in for exactly that reason, but the upload key is still ours
// to keep.
//
// Absent, a release build falls back to the debug key so `flutter run --release`
// and a quick APK to a tester's phone still work. That fallback is deliberately
// loud: a debug-signed bundle is refused by Play at upload rather than silently
// accepted, and the warning below is so the refusal is not the first anyone
// hears of it.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUploadKey = keystorePropertiesFile.exists()
if (hasUploadKey) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.aporah.aporah"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aporah.aporah"
        // **Pinned, not `flutter.minSdkVersion`.** That value moves with the
        // Flutter version, so an upgrade would quietly raise the floor and drop
        // phones that already have the app installed — the kind of change that
        // should be a decision, not a side effect of `flutter upgrade`. 24 is
        // Android 7.0 (2016): every plugin here supports it, and what is below
        // it is a rounding error of German devices.
        minSdk = 24
        // These two do follow Flutter, and should: Play enforces a target level
        // floor and raises it every year, so tracking the toolchain is the
        // cheapest way to stay above it.
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                storeFile = keystoreProperties["storeFile"]?.let { rootProject.file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "Aporah: android/key.properties is missing, so this release build is signed " +
                        "with the DEBUG key. It will run on a device and Play will refuse it."
                )
                signingConfigs.getByName("debug")
            }
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
