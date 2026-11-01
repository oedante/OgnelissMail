#!/usr/bin/env bash
# Интеграционные тесты на эмуляторе Android — шаг задачи «emulator» в
# .github/workflows/ci.yml (1.9.x, просьба владельца 31.10.2026). Отдельным
# скриптом: android-emulator-runner выполняет каждую строку script как
# отдельную команду, без условий и переменных между строками.
#
# Пишет в корень проекта:
#   emulator-machine.jsonl — вывод flutter test --machine (аннотации —
#                            tool/dev/ci_annotate.py, замеры — tool/perf);
#   emulator-stderr.txt    — сборка и ошибки;
#   emulator-logcat.txt    — журнал Android (замеры дублируются и туда).
# Код выхода — как у flutter test.
#
# Локально (эмулятор или телефон подключён): bash tool/dev/emulator_tests.sh [устройство]
set -u

device="${1:-emulator}"
adb devices
adb logcat -c || true
# Экран не гаснет за время тестов.
adb shell settings put system screen_off_timeout 1800000 || true

flutter test integration_test/emulator_test.dart -d "$device" --machine --timeout 5m \
  > emulator-machine.jsonl 2> emulator-stderr.txt
code=$?
tail -n 120 emulator-stderr.txt
adb logcat -d > emulator-logcat.txt 2>/dev/null || true
echo "flutter test: exit $code"
exit $code
