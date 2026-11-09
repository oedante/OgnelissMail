import java.util.Properties

plugins {
    id("com.android.application")
    // kotlin-android убран (AGP 9, встроенный Kotlin): пока в gradle.properties
    // android.builtInKotlin=false, KGP подключает Flutter Gradle Plugin.
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Ключ подписи выпускаемой сборки — android/key.properties (в git не попадает).
// Создаётся скриптом scripts/create_upload_key.ps1:
//   storeFile=C:/Users/…/.ogneliss/upload-keystore.jks
//   keyAlias=upload
//   storePassword=…   ┐ если паролей в файле нет — берутся из переменной
//   keyPassword=…     ┘ окружения OGNELISS_KEYSTORE_PASSWORD (сборочный сервер)
// Если файла нет, release подписывается отладочным ключом (для проверки на
// устройстве; в Google Play и RuStore такая сборка не принимается).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.ogneliss.mail"
    // Не ниже 37: плагин receive_sharing_intent собирается с compileSdk 37
    // («requires Android SDK version 37 or higher»). На targetSdk не влияет.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (запланированные уведомления) требует
        // desugaring java.time на старых Android — без него сборка падает.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.ogneliss.mail"
        // Android 7.0+: требование flutter_secure_storage 10 и local_auth.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        // Google Play с 31.08.2026: новые приложения и обновления — Android 16
        // (API 36) и выше. Явно, чтобы не зависеть от версии Flutter.
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Схема flutter_appauth — только для запасного пути входа без прокси.
        // Отдельная от com.ogneliss.mail (её ловит flutter_web_auth_2 при входе
        // через прокси): с одинаковой схемой Android находил две активности
        // и показывал выбор «Открыть с помощью» после каждого входа.
        manifestPlaceholders["appAuthRedirectScheme"] = "com.ogneliss.mail.appauth"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                val envPassword = System.getenv("OGNELISS_KEYSTORE_PASSWORD")
                storePassword = keystoreProperties.getProperty("storePassword") ?: envPassword
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: envPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
        }
    }
}

// Вместо устаревшего kotlinOptions {} (работает и на AGP 9).
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Устанавливает базовый профиль (src/main/baseline-prof.txt и снятый на
    // телефоне) и при установке не из Google Play — APK, RuStore.
    implementation("androidx.profileinstaller:profileinstaller:1.4.1")
    // enableEdgeToEdge() — рекомендация Google Play для Android 15 (рисование
    // под системными панелями с обратной совместимостью).
    implementation("androidx.activity:activity-ktx:1.10.1")
    // Сигналы сервера на Android (1.9.x, PushWakeFcm.kt): Firebase Cloud
    // Messaging (Apache 2.0, нужны сервисы Google Play) — без плагина
    // google-services и google-services.json, параметры проекта из
    // dart-defines. BoM — та же версия, что у FlutterFire (октябрь 2026).
    implementation(platform("com.google.firebase:firebase-bom:35.1.0"))
    implementation("com.google.firebase:firebase-messaging")
    // Сигналы сервера без сервисов Google (1.10.x, PushWakeUnifiedPush.kt):
    // UnifiedPush connector (Apache 2.0) — расшифровка Web Push на телефоне
    // через Google Tink (Apache 2.0; внутри — protobuf lite, BSD-3-Clause).
    // Connector тянет JVM-сборку com.google.crypto.tink:tink, а в приложении
    // уже есть Android-сборка tink-android (те же классы) — из-за этого
    // сборка падала на «Duplicate class». Берём только tink-android той же
    // версии, что нужна connector.
    implementation("org.unifiedpush.android:connector:3.3.5") {
        exclude(group = "com.google.crypto.tink", module = "tink")
    }
    implementation("com.google.crypto.tink:tink-android:1.23.0")
    // Сигнал ставит разовую задачу плагина workmanager (его BackgroundWorker);
    // версия — та же, что у плагина (workmanager_android 0.10.9).
    implementation("androidx.work:work-runtime:2.11.2")
    // Отчёт консоли MDM (2.2.0, MdmBridge.kt): KeyedAppStates Android
    // Enterprise — androidx.enterprise:enterprise-feedback (Apache 2.0).
    implementation("androidx.enterprise:enterprise-feedback:1.1.0")
    // Перевод писем на устройстве (1.9.x, просьба владельца 31.10.2026):
    // Google ML Kit — бесплатно (условия ML Kit и Google APIs, подпись
    // «Google» у перевода; docs/LICENSING.md). Модели языков скачиваются при
    // первом переводе, в APK — только движок и определение языка.
    implementation("com.google.mlkit:translate:17.0.3")
    implementation("com.google.mlkit:language-id:17.0.6")
}

// Снятие базового профиля на телефоне (docs/guides/BASELINE_PROFILE.md).
// Плагин подключается только по запросу: обычной сборке он не нужен, а
// профиль, снятый однажды, лежит в src/release/generated/baselineProfiles.
if (providers.gradleProperty("ogneliss.baselineProfile").orNull == "true") {
    apply(plugin = "androidx.baselineprofile")
    dependencies {
        add("baselineProfile", project(":baselineprofile"))
    }
    // Плагин кладёт снятый профиль в src/release/generated/baselineProfiles и
    // подключает его только сам. Обычная сборка (без флага) читает
    // src/main/baselineProfiles — копируем туда, чтобы профиль попадал в
    // каждую `flutter build appbundle`.
    val copyBaselineProfile = tasks.register<Copy>("copyBaselineProfileToMain") {
        from("src/release/generated/baselineProfiles")
        include("*.txt")
        into("src/main/baselineProfiles")
    }
    tasks.matching { it.name == "generateBaselineProfile" || it.name == "generateReleaseBaselineProfile" }
        .configureEach { finalizedBy(copyBaselineProfile) }
}

flutter {
    source = "../.."
}
