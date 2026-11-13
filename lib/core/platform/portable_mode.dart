// lib/core/platform/portable_mode.dart
// Переносная версия для Windows (просьба владельца 13.11.2026): рядом с
// ogneliss.exe лежит файл portable.txt — всё, что приложение хранит, пишется
// в папку UserData рядом с программой, а не в AppData. Реализация —
// portable_mode_io.dart; в веб-сборке переносного режима нет.

export 'portable_mode_stub.dart' if (dart.library.ffi) 'portable_mode_io.dart';
