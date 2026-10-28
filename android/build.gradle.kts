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
// Нижняя граница compileSdk для плагинов Flutter (1.6.3, AGP 9). Старые
// плагины задают свой compileSdk: flutter_appauth 6.0.7 — 31. AGP 9
// проверяет метаданные AAR и у модулей-библиотек, поэтому сборка падала:
// «Dependency 'androidx.fragment:fragment:1.7.1' requires … compile against
// version 34 or later … :flutter_appauth is currently compiled against
// android-31». compileSdk влияет только на сборку (какие API видны при
// компиляции), не на поведение на телефоне — targetSdk плагина не меняем.
// Слушатель регистрируется до evaluationDependsOn ниже и выполняется раньше
// слушателя самого AGP, поэтому новое значение учитывается. Через отражение —
// чтобы корневой скрипт не зависел от классов AGP.
val minPluginCompileSdk = 36
subprojects {
    if (project.name != "app" && !project.state.executed) {
        project.afterEvaluate {
            val android = extensions.findByName("android") ?: return@afterEvaluate
            val methods = android.javaClass.methods
            val current = (methods.firstOrNull { it.name == "getCompileSdkVersion" && it.parameterCount == 0 }
                ?.invoke(android) as? String)
                ?.removePrefix("android-")
                ?.toIntOrNull()
                ?: return@afterEvaluate
            if (current >= minPluginCompileSdk) return@afterEvaluate
            methods.firstOrNull {
                it.name == "compileSdkVersion" && it.parameterCount == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }?.let {
                it.invoke(android, minPluginCompileSdk)
                logger.info("compileSdk плагина ${project.name}: $current → $minPluginCompileSdk")
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
    // Плагины Flutter (device_info_plus 12.x и др.) берут в своём build.gradle
    // `flutter.compileSdkVersion`. Расширение `flutter` создаёт Flutter
    // Gradle Plugin только у :app; при синхронизации проекта в Android Studio
    // плагин его не находил: «Could not get unknown property 'flutter' for
    // extension 'android'» (11.10.2026). :app к этому моменту уже настроен
    // (строка выше) — отдаём плагинам то же расширение, без своих чисел.
    //
    // Настоящее расширение, а не extra-свойство (12.10.2026): плагины на
    // Kotlin DSL (dynamic_color 1.9: `compileSdk = flutter.compileSdkVersion`
    // в build.gradle.kts) видят только зарегистрированные расширения — по
    // extra-свойству Kotlin-скрипт не компилировался: «Unresolved reference:
    // flutter». Groovy-плагины находят расширение так же, как раньше.
    if (project.name != "app" &&
        project.extensions.findByName("flutter") == null &&
        !project.extensions.extraProperties.has("flutter")
    ) {
        rootProject.findProject(":app")?.extensions?.findByName("flutter")?.let { ext ->
            try {
                project.extensions.add("flutter", ext)
            } catch (e: Exception) {
                project.extensions.extraProperties.set("flutter", ext)
            }
        }
    }
}
// Сторонние плагины Flutter собираются с source/target 8 — javac 21 печатает
// «source value 8 is obsolete» по три строки на каждый. Сборку это не
// ломает; глушим только это предупреждение, остальные остаются.
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-options")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
