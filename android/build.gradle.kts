import org.gradle.api.Action
import org.gradle.api.Task

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

    project.evaluationDependsOn(":app")
}

// For plugin modules, make each Kotlin compile task match the JVM target
// of its corresponding Java compile task.
fun syncJvmTarget(proj: Project, kotlinTask: org.jetbrains.kotlin.gradle.tasks.KotlinCompile) {
    val variantName = kotlinTask.name.removePrefix("compile").removeSuffix("Kotlin")
    val javaTaskName = "compile${variantName}JavaWithJavac"
    val javaTask = proj.tasks.findByName(javaTaskName)
    if (javaTask is JavaCompile) {
        kotlinTask.kotlinOptions.jvmTarget = javaTask.targetCompatibility
    }
}

fun linkKotlinToJavaTarget(proj: Project) {
    // Configure KotlinCompile tasks that already exist
    val ktTasks = proj.tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java)
    for (task in ktTasks) {
        syncJvmTarget(proj, task)
    }
    // Also configure KotlinCompile tasks created later (lazy plugins)
    proj.tasks.whenTaskAdded(object : Action<Task> {
        override fun execute(task: Task) {
            if (task is org.jetbrains.kotlin.gradle.tasks.KotlinCompile) {
                syncJvmTarget(proj, task)
            }
        }
    })
}

allprojects {
    if (name != "app") {
        if (!state.executed) {
            afterEvaluate { linkKotlinToJavaTarget(this) }
        } else {
            linkKotlinToJavaTarget(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
