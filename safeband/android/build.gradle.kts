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
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (e.g. flutter_ringtone_player) hardcode an old compileSdk
// in their own android/build.gradle, which doesn't inherit the app's
// setting — that mismatch is what "compiled against android-33, requires
// 34+" AAR metadata errors come from. Force every Android library module
// to compile against the same SDK the app itself uses, overriding
// whatever a plugin sets on its own. Deferred to afterEvaluate: a
// plugin's own build.gradle sets its compileSdkVersion AFTER this point,
// so an un-deferred override here gets clobbered right back — but some
// subprojects are already fully evaluated by the time this callback
// registers (Flutter's Gradle integration evaluates plugin subprojects
// early via :app), and afterEvaluate() throws on an already-evaluated
// project — hence the state.executed check to apply immediately instead.
subprojects {
    val applyCompileSdkOverride: () -> Unit = {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.let { it.compileSdk = 36 }
    }
    if (project.state.executed) applyCompileSdkOverride()
    else afterEvaluate { applyCompileSdkOverride() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
