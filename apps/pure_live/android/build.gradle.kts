// toolchain.env (repository root) is the single source of the Android
// platform, build-tools and NDK versions (docs/PLAN.md §3): every module,
// the app and each plugin, builds with the versions it names.
val toolchain: Map<String, String> =
    rootDir.resolve("../../../toolchain.env").readLines()
        .map { it.trim() }
        .filter { it.isNotEmpty() && !it.startsWith("#") && "=" in it }
        .associate { it.substringBefore("=").trim() to it.substringAfter("=").trim() }

/** Applies toolchain.env's platform (ANDROID_COMPILE_SDK, e.g. 37.2), build-tools and NDK. */
fun com.android.build.api.dsl.CommonExtension.useToolchain() {
    val platform = toolchain.getValue("ANDROID_COMPILE_SDK").split(".")
    compileSdk = platform[0].toInt()
    compileSdkMinor = platform.getOrNull(1)?.toInt()
    buildToolsVersion = toolchain.getValue("ANDROID_BUILD_TOOLS")
    ndkVersion = toolchain.getValue("ANDROID_NDK_VERSION")
}
extra["useToolchain"] = { android: com.android.build.api.dsl.CommonExtension -> android.useToolchain() }

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

subprojects {
    afterEvaluate {
        if (project.name != "app") {
            extensions.findByType(com.android.build.api.dsl.CommonExtension::class.java)?.useToolchain()
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
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
