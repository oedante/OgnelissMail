# Прежний («классический») стиль интерфейса — резервная копия

Копия трёх файлов стиля до смягчения в 1.6.20 (решение владельца 17.10.2026: «слишком контрастно, угловато»; новый стиль проверяют тестировщики). Файлы с расширением `.txt`, чтобы анализатор их не разбирал.

| Файл копии | Куда вернуть |
|---|---|
| `app_theme.dart.txt` | `lib/core/theme/app_theme.dart` |
| `tokens.dart.txt` | `lib/core/theme/tokens.dart` |
| `person_photo.dart.txt` | `lib/widgets/common/person_photo.dart` |

Вернуть прежний стиль (функциональность не затронута — меняются только цвета, радиусы, толщина линий и значков):

```
git checkout style-classic-1.6.19 -- lib/core/theme/app_theme.dart lib/core/theme/tokens.dart lib/widgets/common/person_photo.dart
```

или скопировать файлы из этой папки, убрав `.txt`. Метка `style-classic-1.6.19` в репозитории указывает на состояние до смягчения.

Что изменилось в мягком стиле — CHANGELOG, версия 1.6.20.

Отдельно от этих трёх файлов в 1.6.20 добавлен единый для всех платформ вид: шрифт Roboto из пакета приложения (`pubspec.yaml` → `fonts: AppRoboto`) и в `ThemeData` — `visualDensity: standard`, `materialTapTargetSize: padded`, `splashFactory: InkRipple`. Команда выше вернёт и их (они в `app_theme.dart`); строку шрифта в `pubspec.yaml` можно оставить — без ссылки из темы она ни на что не влияет.
