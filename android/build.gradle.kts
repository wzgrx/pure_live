import com.android.build.gradle.BaseExtension

// AGP 9 built-in Kotlin compiles with the Kotlin Gradle Plugin on the build
// classpath (AGP itself only brings 2.2.10). Keep in step with KOTLIN_VERSION in
// toolchain.env; tool/audit_built_in_kotlin.py checks both.
buildscript {
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.20")
    }
}

allprojects {
    repositories {
        maven(rootProject.file("../plugins/flv_lzc/android/libs")) {
            content {
                includeModule("io.github.flutterplayer", "fplayer-core")
            }
        }
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
            extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.apply {
                compileSdkVersion("android-37.2")
                // One NDK (and so one libc++) for every module built from source.
                ndkVersion = "30.0.16248370"
                // Keep plugin manifests aligned with the native FFmpeg bundle.
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
