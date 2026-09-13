allprojects {
    // See `settings.gradle.kts` for what this flag is for; both scripts must
    // agree, so the same expression is repeated here.
    val useMirrors = (System.getenv("M3E_USE_MIRRORS") ?: "true").toBoolean()

    repositories {
        // Mirrors first, official repositories after them as fallbacks.
        if (useMirrors) {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
        }
        google()
        mavenCentral()
    }
}

// Repairs a misconfigured FLUTTER_STORAGE_BASE_URL.
//
// Flutter's own Gradle plugin concatenates that variable verbatim —
// `"$hostedRepository/download.flutter.io"` — so a value without a scheme (the
// commonly copy-pasted `storage.flutter-io.cn`) turns into a *relative* URL that
// Gradle resolves against the module directory and can never find:
//
//   file:/<project>/android/app/storage.flutter-io.cn/download.flutter.io/...
//   Could not find io.flutter:arm64_v8a_debug:1.0.0-<engine hash>
//
// The Flutter tool itself normalises the same variable (which is why
// `flutter pub get` keeps working and only the Android build breaks), so the
// failure is easy to misread as a project problem. When the value is relative,
// add the absolute repository the plugin meant to add.
//
// On a correctly configured machine, and on CI where the variable is unset,
// this block does nothing at all.
val flutterStorageBaseUrl: String? = System.getenv("FLUTTER_STORAGE_BASE_URL")
if (flutterStorageBaseUrl != null && !flutterStorageBaseUrl.startsWith("http")) {
    logger.warn(
        "FLUTTER_STORAGE_BASE_URL is '$flutterStorageBaseUrl' — missing a scheme, so " +
            "Flutter's own engine repository cannot resolve. Adding " +
            "https://$flutterStorageBaseUrl/download.flutter.io as a fallback; " +
            "fix the variable (it needs https://) to remove this warning.",
    )
    allprojects {
        repositories {
            maven { url = uri("https://$flutterStorageBaseUrl/download.flutter.io") }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
