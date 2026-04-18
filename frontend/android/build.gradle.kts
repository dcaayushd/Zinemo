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
    afterEvaluate {
        val androidExt = extensions.findByName("android") ?: return@afterEvaluate
        val currentNamespace = runCatching {
            androidExt.javaClass.getMethod("getNamespace").invoke(androidExt) as String?
        }.getOrNull()

        if (currentNamespace.isNullOrBlank()) {
            val sanitizedName = project.name.replace(Regex("[^A-Za-z0-9_]"), "_")
            val fallbackNamespace = "ci.fix.$sanitizedName"
            runCatching {
                androidExt.javaClass
                    .getMethod("setNamespace", String::class.java)
                    .invoke(androidExt, fallbackNamespace)
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
