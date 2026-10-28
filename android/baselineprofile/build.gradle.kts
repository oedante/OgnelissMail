// Генератор базового профиля (Baseline Profile) — снимается на подключённом
// телефоне. Модуль подключается только при -Pogneliss.baselineProfile=true
// (settings.gradle.kts), обычная сборка `flutter build` его не трогает.
// Инструкция: docs/guides/BASELINE_PROFILE.md.
plugins {
    id("com.android.test")
    id("org.jetbrains.kotlin.android")
    id("androidx.baselineprofile")
}

android {
    namespace = "com.ogneliss.mail.baselineprofile"
    compileSdk = 36

    defaultConfig {
        // Снятие профиля без root — Android 13+.
        minSdk = 28
        targetSdk = 36
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    targetProjectPath = ":app"
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

baselineProfile {
    // Телефон по USB (отладка по USB включена), без эмулятора.
    useConnectedDevices = true
}

dependencies {
    implementation("androidx.test.ext:junit:1.2.1")
    implementation("androidx.test.uiautomator:uiautomator:2.3.0")
    implementation("androidx.benchmark:benchmark-macro-junit4:1.5.0")
}
