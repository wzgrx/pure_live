allprojects {
    repositories {
        if (System.getenv("PURE_LIVE_USE_CN_MIRRORS") == "1") {
            maven("https://maven.aliyun.com/repository/google")
            maven("https://maven.aliyun.com/repository/central")
            maven("https://maven.aliyun.com/repository/public")
        }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// The toolchain pins (toolchain.env at the repository root, docs/specs/ENGINEERING.md §3):
// every module compiles against the same platform with the same NDK, CMake
// and build-tools.
val toolchain: Map<String, String> =
    file("../../../toolchain.env").readLines()
        .map { it.trim() }
        .filter { it.isNotEmpty() && !it.startsWith("#") && "=" in it }
        .associate { it.substringBefore("=").trim() to it.substringAfter("=").trim() }
val compileSdkLevel = toolchain.getValue("ANDROID_COMPILE_SDK").split(".")
extra["androidCompileSdk"] = compileSdkLevel[0].toInt()
extra["androidCompileSdkMinor"] = compileSdkLevel.getOrNull(1)?.toInt()
extra["androidNdkVersion"] = toolchain.getValue("ANDROID_NDK_VERSION")
extra["androidBuildTools"] = toolchain.getValue("ANDROID_BUILD_TOOLS")
val androidCmakeVersion = toolchain.getValue("ANDROID_CMAKE_VERSION")

subprojects {
    afterEvaluate {
        if (project.name != "app") {
            extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)?.apply {
                compileSdk = rootProject.extra["androidCompileSdk"] as Int
                compileSdkMinor = rootProject.extra["androidCompileSdkMinor"] as Int?
                ndkVersion = rootProject.extra["androidNdkVersion"] as String
                buildToolsVersion = rootProject.extra["androidBuildTools"] as String
                if (externalNativeBuild.cmake.path != null) {
                    externalNativeBuild.cmake.version = androidCmakeVersion
                    // CMake 4 refuses projects that ask for CMake older than
                    // 3.5 (ffmpeg_kit_extended_flutter asks for 3.4.1).
                    defaultConfig.externalNativeBuild.cmake.arguments += "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
                }
                // Plugin manifests follow the app's floor (app/build.gradle.kts).
                defaultConfig.minSdk = 26
                if (namespace.isNullOrBlank()) {
                    namespace = project.group.toString()
                }
            }
        }
    }
}

subprojects {
    if (project.name != "app") {
        evaluationDependsOn(":app")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
