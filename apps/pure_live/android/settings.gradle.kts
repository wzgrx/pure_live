pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    // toolchain.env (repository root) is the single source of the toolchain
    // versions (docs/PLAN.md §3); build.gradle.kts takes them from here.
    val toolchain: Map<String, String> =
        file("../../../toolchain.env").readLines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") && "=" in it }
            .associate { it.substringBefore("=").trim() to it.substringAfter("=").trim() }
    gradle.extra["toolchain"] = toolchain

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    plugins {
        // AGP 9's built-in Kotlin compiles with the Kotlin Gradle Plugin next to
        // it on this classpath; without one, with AGP's own floor (2.2.10).
        id("org.jetbrains.kotlin.android") version toolchain.getValue("KOTLIN_VERSION")
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // toolchain.env AGP_VERSION, written out because flutter_tools reads it
    // from this file.
    id("com.android.application") version "9.4.1" apply false
    id("org.jetbrains.kotlin.android") apply false
}

include(":app")
