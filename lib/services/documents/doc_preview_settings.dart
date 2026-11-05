// lib/services/documents/doc_preview_settings.dart
// Какие документы показывать в приложении (1.11.x, просьба владельца
// 04.11.2026: «предпросмотр сделаем отключаемой функцией с возможностью
// отключить определённые типы документов, а что-то оставить»).
//
// Общий выключатель и четыре вида: текстовые документы, таблицы, CSV
// таблицей, презентации. Выключенный вид открывается, как до 1.11: своей
// программой (на iPhone и iPad OpenDocument — листом «Поделиться»), а CSV —
// простым текстом в приложении. Office, RTF и CSV на iPhone и iPad и так
// показывает «Просмотр» iOS — от этих настроек там зависит только
// OpenDocument.
//
// Настройки читаются при запуске (main.dart) и хранятся здесь же, как
// «Широкие письма» (MailHtmlView.fitWide): решение «открыть здесь или своей
// программой» принимает статическая функция без доступа к провайдерам
// (AttachmentPreviewScreen.opensInApp).

import 'package:shared_preferences/shared_preferences.dart';

import 'office_document.dart';

/// Вид документа в настройках просмотра.
enum DocPreviewType { text, sheets, csv, slides }

class DocPreviewSettings {
  DocPreviewSettings._();

  static const enabledKey = 'doc_preview_on';
  static String typeKey(DocPreviewType t) => 'doc_preview_${t.name}';

  /// Все ключи — для «Сбросить настройки».
  static List<String> get keys => [enabledKey, for (final t in DocPreviewType.values) typeKey(t)];

  static bool _enabled = true;
  static final Set<DocPreviewType> _off = {};

  /// Общий выключатель (по умолчанию — включено).
  static bool get enabled => _enabled;

  static void load(SharedPreferences p) {
    _enabled = p.getBool(enabledKey) ?? true;
    _off
      ..clear()
      ..addAll(DocPreviewType.values.where((t) => p.getBool(typeKey(t)) == false));
  }

  /// После «Сбросить настройки»: всё включено.
  static void reset() {
    _enabled = true;
    _off.clear();
  }

  /// Вид включён сам по себе (без учёта общего выключателя) — для
  /// переключателей в настройках.
  static bool typeOn(DocPreviewType t) => !_off.contains(t);

  /// Показывать ли документы вида [t] в приложении.
  static bool isOn(DocPreviewType t) => _enabled && !_off.contains(t);

  static Future<void> setEnabled(SharedPreferences p, bool v) async {
    _enabled = v;
    await p.setBool(enabledKey, v);
  }

  static Future<void> setType(SharedPreferences p, DocPreviewType t, bool v) async {
    if (v) {
      _off.remove(t);
    } else {
      _off.add(t);
    }
    await p.setBool(typeKey(t), v);
  }

  /// Старые .doc, .xls, .ppt (1.12.x) — тем же видом, что DOCX, XLSX, PPTX:
  /// отдельного выключателя у них нет.
  static DocPreviewType typeOf(OfficeFormat f) => switch (f) {
        OfficeFormat.docx || OfficeFormat.odt || OfficeFormat.rtf || OfficeFormat.doc => DocPreviewType.text,
        OfficeFormat.xlsx || OfficeFormat.ods || OfficeFormat.xls => DocPreviewType.sheets,
        OfficeFormat.csv => DocPreviewType.csv,
        OfficeFormat.pptx || OfficeFormat.odp || OfficeFormat.ppt => DocPreviewType.slides,
      };

  /// Вид документа по имени файла и MIME-типу; null — не документ.
  static DocPreviewType? typeOfName(String fileName, {String? mimeType}) {
    final f = OfficeFormats.of(fileName, mimeType: mimeType);
    return f == null ? null : typeOf(f);
  }

  /// Показывать ли файл предпросмотром документа (по виду и настройкам).
  static bool allows(String fileName, {String? mimeType}) {
    final t = typeOfName(fileName, mimeType: mimeType);
    return t != null && isOn(t);
  }
}
