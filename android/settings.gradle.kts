pluginManagement {
    // Mirror repositories exist for networks that cannot reach Google's Maven
    // repository at all; see the README for the measurements behind that. They
    // are on by default so a normal local build works out of the box.
    //
    // CI sets `M3E_USE_MIRRORS=false`: GitHub's runners reach the official
    // repositories directly and quickly, so sending every dependency request
    // through a Chinese mirror first would only add latency.
    //
    // Declared *inside* this block on purpose. Gradle evaluates `pluginManagement`
    // specially, before the rest of the settings script, so a top-level `val`
    // declared above it is not in scope here — doing that fails with
    // "Unresolved reference".
    val useMirrors = (System.getenv("M3E_USE_MIRRORS") ?: "true").toBoolean()

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
        // Mirrors first, official repositories after them as fallbacks, so the
        // build still works wherever the mirrors are slow or unreachable.
        if (useMirrors) {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
            maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
