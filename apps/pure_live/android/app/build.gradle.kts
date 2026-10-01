import java.util.Properties

plugins {
    id("com.android.application")
    // AGP 9 provides Built-in Kotlin; the standalone Kotlin Gradle Plugin is not applied.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (docs/PLAN.md §9). key.properties and the keystore never
// enter Git; without them a release build is signed with the debug key.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")?.let(::file)
val hasReleaseSigning = listOf("keyAlias", "keyPassword", "storePassword").all {
    !keystoreProperties.getProperty(it).isNullOrBlank()
} && releaseStoreFile?.isFile == true
val requireReleaseSigning =
    providers.gradleProperty("pureLive.requireReleaseSigning").orNull.toBoolean()
if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException("Release signing is required but android/key.properties is incomplete.")
}

extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
    namespace = "com.mystyle.purelive"
    buildFeatures {
        buildConfig = true
    }
    compileSdk = 37
    ndkVersion = flutter.ndkVersion
    lint {
        checkReleaseBuilds = true
        abortOnError = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        // 3.x's id: the release build installs over 3.x and keeps its data (M15).
        applicationId = "com.mystyle.purelive"
        // 3.x's floor (its FFmpeg bundle needs API 26; M8 keeps that engine).
        minSdk = 26
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "纯粹直播"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = releaseStoreFile
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("Release key not configured; signing the release build with the debug key.")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                file("proguard-rules.pro"),
            )
        }
        // Development builds live next to the user's 3.x install and never
        // touch it or its data: own id, own name.
        debug {
            applicationIdSuffix = ".v4dev"
            manifestPlaceholders["appLabel"] = "纯粹直播 v4dev"
            isMinifyEnabled = false
            isShrinkResources = false
        }
        maybeCreate("profile").apply {
            applicationIdSuffix = ".v4dev"
            manifestPlaceholders["appLabel"] = "纯粹直播 v4dev"
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

// Flutter's build tasks use Project at execution time; keep them out of the
// configuration cache (same as 3.x).
tasks.matching {
    it.name.contains("flutter", ignoreCase = true) || it.name.startsWith("assemble")
}.configureEach {
    notCompatibleWithConfigurationCache(
        "Flutter Gradle tasks are not yet compatible with AGP Built-in Kotlin state",
    )
}
