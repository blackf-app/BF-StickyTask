import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Ky release bang key co dinh, doc tu android/key.properties (bi gitignore).
//
// Vi sao KHONG dung debug key nua: auto-update cai de APK, ma Android chi cho
// cai de khi APK moi ky cung mot key voi ban dang cai. debug.keystore duoc sinh
// moi tren tung runner CI => moi release mot chu ky => cai de fail
// INSTALL_FAILED_UPDATE_INCOMPATIBLE.
//
// Tren CI khong co file nay; workflow release.yml dung 4 GitHub Secrets de dung
// lai keystore + key.properties truoc khi build (xem .github/workflows/release.yml).
//
// Khong co key.properties (may chua setup / build debug) thi signingConfig
// release = null, Gradle roi ve debug key: `flutter run --release` van chay,
// nhung APK do KHONG duoc phat hanh.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.blackface.bfstickytask"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.blackface.bfstickytask"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                // storeFile tuong doi so voi android/ (noi dat key.properties).
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Khong co key.properties thi de nguyen (Gradle roi ve debug key) —
            // build duoc de test, nhung dung phat hanh ban do.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
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
