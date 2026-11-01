// integration_test/emulator_test.dart
// Все тесты для эмулятора Android одним запуском (задача «emulator» в
// .github/workflows/ci.yml; 1.9.x, просьба владельца 31.10.2026): каждый
// файл integration_test собирается в отдельный APK, а сборка — самая долгая
// часть задачи (минуты Actions).
//
// Порядок: замеры скорости первыми — первое открытие письма идёт при ещё
// не загруженном движке браузера, как после запуска приложения; затем окно
// письма и редактор; запуск приложения — последним (main() ставит свои
// обработчики ошибок и службы на весь процесс).
//
//   flutter test integration_test/emulator_test.dart -d emulator

import 'mail_editor_test.dart' as editor;
import 'mail_view_test.dart' as mail_view;
import 'perf_test.dart' as perf;
import 'support/harness.dart';

void main() {
  ensureBinding();
  perf.perfTests();
  mail_view.mailViewTests();
  editor.mailEditorTests();
  perf.appStartTests();
}
