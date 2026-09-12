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
