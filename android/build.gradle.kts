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

subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null && android.namespace.isNullOrEmpty()) {
            val manifest = file("src/main/AndroidManifest.xml")
            if (manifest.exists()) {
                val match = Regex("""package\s*=\s*"([^"]+)"""").find(manifest.readText())
                if (match != null) {
                    android.namespace = match.groupValues[1]
                } else {
                    android.namespace = "com.plugin.${project.name.replace('-', '_')}"
                }
            } else {
                android.namespace = "com.plugin.${project.name.replace('-', '_')}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
