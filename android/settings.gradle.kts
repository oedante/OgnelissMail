// Gradle-проект Android для Android Studio (шаблон Flutter 3.38).
// Путь к Flutter SDK берётся из android/local.properties (flutter.sdk=…);
// файл создаёт Android Studio или `flutter pub get`.
pluginManagement {
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
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 9.1.0 + Gradle 9.3.1 — версии шаблона Flutter 3.47 (1.6.3).
    // Встроенный Kotlin и новый DSL пока выключены (gradle.properties).
    id("com.android.application") version "9.1.0" apply false
    // KGP остаётся в classpath: при android.builtInKotlin=false Flutter Gradle
    // Plugin сам подключает его к :app и к плагинам, которые уже перешли на
    // встроенный Kotlin. Версия — как в шаблоне Flutter 3.47.
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // Базовый профиль запуска (Baseline Profile): модуль-генератор и плагин
    // подключаются только при -Pogneliss.baselineProfile=true (ниже).
    id("com.android.test") version "9.1.0" apply false
    // 1.5.0: первая стабильная, что работает с AGP 9.
    id("androidx.baselineprofile") version "1.5.0" apply false
}

include(":app")

// Генератор базового профиля — только по запросу (нужен телефон по USB):
//   gradlew :app:generateBaselineProfile -Pogneliss.baselineProfile=true
// См. docs/guides/BASELINE_PROFILE.md. Обычная сборка его не подключает.
if (providers.gradleProperty("ogneliss.baselineProfile").orNull == "true") {
    include(":baselineprofile")
}
