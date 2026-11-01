// База замеров скорости на эмуляторе (tool/perf/baseline.json) и замеры в
// integration_test/perf_test.dart — одни и те же (1.9.x, просьба владельца
// 31.10.2026): переименованный замер без строки в базе не сравнивался бы ни
// с чем, а строка базы без замера давала бы предупреждение в каждой сборке.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('каждый замер perf_test.dart есть в базе, и наоборот; значения — положительные', () {
    final base = jsonDecode(File('tool/perf/baseline.json').readAsStringSync()) as Map<String, dynamic>;
    final metrics = (base['metrics'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as num));
    expect(metrics.values.every((v) => v > 0), isTrue);

    final src = File('integration_test/perf_test.dart').readAsStringSync();
    final recorded = RegExp(r"PerfLog\.record\(\s*'([a-z_]+)'").allMatches(src).map((m) => m.group(1)!).toSet();
    expect(recorded, isNotEmpty);
    expect(recorded, metrics.keys.toSet());
    expect(recorded.every((n) => n.endsWith('_ms')), isTrue);
  });
}
