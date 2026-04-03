import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory.dir("../../build").get()
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

subprojects {
    tasks.withType<KotlinCompile>().configureEach {
        val relatedJavaTaskName = name.replace("Kotlin", "JavaWithJavac")
        val javaTarget = project.tasks.withType<JavaCompile>()
            .matching { it.name == relatedJavaTaskName }
            .firstOrNull()
            ?.targetCompatibility
            ?: project.tasks.withType<JavaCompile>().firstOrNull()?.targetCompatibility
            ?: "17"

        kotlinOptions {
            jvmTarget = javaTarget
        }
    }
}
