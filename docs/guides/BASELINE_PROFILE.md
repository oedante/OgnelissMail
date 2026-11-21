# Базовый профиль запуска (Baseline Profile)

Что это. Список Java/Kotlin-кода, который Android компилирует заранее при
установке, а не при первом запуске. У приложения на Flutter он ускоряет
только Android-часть: запуск движка Flutter, встраивание, плагины. Код на
Dart и так собран заранее (AOT), профиль на него не влияет. Ожидаемый
выигрыш на холодном старте — единицы и десятки процентов на медленных
телефонах; на быстрых разница почти не видна.

Что уже есть. В сборку всегда входит `android/app/src/main/baseline-prof.txt`
(общий профиль встраивания Flutter) и `androidx.profileinstaller` — он
устанавливает профиль и при установке не из Google Play (APK, RuStore).
Снятый на устройстве профиль кладётся в
`android/app/src/main/baselineProfiles/` и попадает в каждую сборку.

## Почему не получилось 19–21.11.2026 (Windows, PowerShell)

1. `.\gradlew :app:generateBaselineProfile -Pogneliss.baselineProfile=true`
   PowerShell делит аргумент по точке на два: до Gradle флаг не доходил,
   плагин не подключался — «task 'generateBaselineProfile' not found».
   Теперь есть флаг без точки: `-PognelissBaselineProfile=true` (старый
   тоже работает, но в PowerShell его нужно брать в кавычки), или
   переменная окружения `OGNELISS_BASELINE_PROFILE=1`.
2. С кавычками сборка дошла до `:app:compileNonMinifiedReleaseKotlin` и
   упала: `Illegal char <?> at index 54: …\android\app\provider(?)`.
   Вариант `nonMinifiedRelease` создаёт плагин базового профиля; при
   AGP 9 со старым DSL (`android.newDsl=false`, его пока требует Flutter)
   какой-то каталог исходников передаётся строкой `provider(?)`. На Linux и
   macOS такое имя каталога допустимо, и сборка проходит, а в путях Windows
   символ `?` запрещён. Исправить это в своём проекте нельзя — это стык AGP,
   Kotlin и плагина; ждём их обновлений.

## Как снять профиль сейчас

**Проще всего — в GitHub Actions.** Actions → CI/CD → Run workflow →
включить «Снять базовый профиль…» (остальное можно выключить). Задание
поднимает эмулятор Android 14 на Linux, ставит сборку и снимает профиль
(холодный старт и прокрутка). Через ~40 минут в Artifacts будет
`baseline-profile-<коммит>`: файл `baseline-prof.txt` из него положить в
`android/app/src/main/baselineProfiles/` и закоммитить. Репозиторий
публичный — минуты Actions бесплатные.

**На своём компьютере** — из WSL (Ubuntu) или на Mac, телефон по USB
(отладка по USB, Android 13+), в приложении выполнен вход хотя бы в один
ящик (тогда профиль покрывает и ленту писем):

```
cd android
./gradlew :app:generateReleaseBaselineProfile -PognelissBaselineProfile=true
```

Готовый профиль задача сама копирует в
`android/app/src/main/baselineProfiles/`.

Сценарий снятия — `android/baselineprofile/src/main/java/com/ogneliss/mail/baselineprofile/BaselineProfileGenerator.kt`.
