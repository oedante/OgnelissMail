# native_toolchain_rust 1.0.6 + исправление из 1.0.7

Копия пакета [native_toolchain_rust](https://pub.dev/packages/native_toolchain_rust)
1.0.6 (Gregory Conrad, лицензия MIT — `LICENSE`) с одной правкой из 1.0.7
([#104](https://github.com/GregoryConrad/native_toolchain_rust/issues/104)):
в `lib/src/toml_parsing.dart` поле `lib.name` из Cargo.toml читается как
необязательное (`walk<String?>`). Без правки каждый `flutter test` и каждая
сборка печатали «[SEVERE] RustBuilder: Failed to find lib.name …» с текстом
Cargo.toml и стеком, хотя сборка шла дальше (просьба владельца 10.11.2026).

Подключается в `pubspec.yaml` приложения через `dependency_overrides`. Саму
1.0.7 взять нельзя: ей нужен code_assets 2, а super_native_extensions
0.10.0-dev.2 (через irondash_engine_context 0.6) держит code_assets 1.
Убрать копию и переопределение, когда super_drag_and_drop перейдёт на
native_toolchain_rust 1.0.7 или новее.

Пакет — инструмент сборки ядра Rust перетаскивания вложений
(super_native_extensions); в приложение он не входит.
