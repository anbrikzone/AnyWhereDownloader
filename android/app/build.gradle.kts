import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.anywheredownloader.anywhere_downloader"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.anywheredownloader.anywhere_downloader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 31
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreProperties) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key when key.properties isn't present
            // (e.g. a fresh checkout without the release keystore), so
            // `flutter run --release` still works without extra setup.
            signingConfig = if (hasKeystoreProperties) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // AGP 9's release build type minifies/obfuscates by default
            // even with no isMinifyEnabled line at all (confirmed by a real
            // crash: R8-obfuscated stack trace, "class ea.a is not a
            // concrete class" — Jackson, used by youtubedl-android's
            // VideoInfo/VideoFormat mappers for JSON parsing, instantiates
            // classes via reflection, which R8 breaks without keep rules).
            // Explicitly disabled per the user's choice: split-per-abi only,
            // no minification, since we have no way to verify the necessary
            // ProGuard/R8 keep rules for Jackson without extensive testing.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // youtubedl-android bundles python/ffmpeg as opaque *.zip.so blobs it
    // unzips itself at runtime — they aren't real ELF libraries, so they
    // must stay uncompressed in the APK and be extracted to disk at install
    // time (the library locates them via applicationInfo.nativeLibraryDir).
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    // Name release APKs like `AnyWhereDownloader-0.3.5-arm64-v8a.apk` instead
    // of the default `app-arm64-v8a-release.apk`. UpdateService.assetForAbis
    // matches on the ABI substring, so the version/name prefix is free to
    // change. (Flutter's own copy under build/app/outputs/flutter-apk/ may
    // keep its default name depending on the tooling version — the GitHub
    // release upload renames there too as a backstop.)
    applicationVariants.all {
        val variant = this
        outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            if (variant.buildType.name == "release") {
                val abi = output.getFilter("ABI")
                output.outputFileName =
                    "AnyWhereDownloader-${variant.versionName}" +
                    (if (abi != null) "-$abi" else "") + ".apk"
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // yt-dlp engine for YouTube (and later Instagram/X) metadata/URL extraction.
    // The `ffmpeg` module is required even though we don't use its
    // postprocessing (-x --audio-format mp3) yet: YoutubeDL.execute() always
    // sets --ffmpeg-location to a path only populated when this module is
    // present, even for plain --dump-json calls.
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
    implementation("io.github.junkfood02.youtubedl-android:ffmpeg:0.18.1")
}

flutter {
    source = "../.."
}
