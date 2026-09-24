allprojects {
    repositories {
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
// `file_picker` 8.x still compiles against android-34, but
// `flutter_plugin_android_lifecycle` now requires 36 or later, and Gradle
// fails the build on the mismatch rather than picking one. This forces every
// plugin module to the newer level, which is the action the failure itself
// recommends.
//
// compileSdk decides only which APIs are available AT COMPILE TIME. targetSdk
// (runtime behaviour) and minSdk (which devices can install) are untouched,
// so this changes nothing a user can observe.
//
// This MUST stay above the `evaluationDependsOn(":app")` block below. That
// call forces each subproject to evaluate immediately, and `afterEvaluate`
// cannot be registered on a project that has already evaluated — registering
// it afterwards fails with "Cannot run Project.afterEvaluate(Action) when the
// project is already evaluated."
//
// Remove this once `file_picker` is upgraded — it is pinned at ^8.1.4 and
// 13.x is current, but 13 restructured into federated platform packages and
// the upgrade wants its own testing. There is exactly one call site,
// `lib/features/titles/file_upload.dart`, covered by `file_upload_test.dart`.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.withGroovyBuilder {
            "compileSdkVersion"(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
