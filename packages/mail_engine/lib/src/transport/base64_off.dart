import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

/// Раскодировать base64 вложения; большое — в отдельном изоляте (план
/// 08.11.2026 п. 3, микрофризы): вложение 20 МБ — это 27 МБ текста, и
/// удаление переводов строк с раскодированием занимали сотни миллисекунд
/// главного потока — лента и прокрутка замирали, пока файл сохранялся.
/// Маленькое (меньше [threshold] знаков) — сразу: запуск изолята дороже.
Future<Uint8List> decodeBase64Off(String text, {int threshold = 256 * 1024}) {
  if (text.length < threshold) return Future.value(decodeBase64Loose(text));
  return Isolate.run(() => decodeBase64Loose(text), debugName: 'base64');
}

/// base64 с переводами строк и пробелами (EWS, EAS разбивают по 76 знаков).
Uint8List decodeBase64Loose(String text) => base64.decode(text.replaceAll(_ws, ''));

final _ws = RegExp(r'\s');
