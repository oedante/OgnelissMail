// lib/core/utils/text_entities.dart
// Числовые HTML-сущности в ТЕКСТОВОМ теле письма. Exchange при выдаче тела
// как простого текста (ActiveSync, Body Type 1) иногда оставляет символы в
// виде «&#1084;» (буква «м») — в превью списка и при переводе это выглядело
// как «Уважае&#1084;ые коллеги». Только для текста, не для HTML.

final _numeric = RegExp(r'&#(x?)([0-9a-fA-F]{1,6});');

String? decodeTextEntities(String? s) {
  if (s == null || !s.contains('&')) return s;
  return s.replaceAllMapped(_numeric, (m) {
    final hex = m.group(1)!.isNotEmpty;
    final code = int.tryParse(m.group(2)!, radix: hex ? 16 : 10);
    if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
    return String.fromCharCode(code);
  }).replaceAll('&nbsp;', ' ');
}
