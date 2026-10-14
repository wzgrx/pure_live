pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // toolchain.env AGP_VERSION.
    id("com.android.application") version "9.4.1" apply false
    // toolchain.env KOTLIN_VERSION: AGP 9's built-in Kotlin takes the newer
    // Kotlin Gradle plugin from the classpath (AGP 9.4.1 ships 2.4.20).
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")
