// lib/services/documents/doc_xml.dart
// Дерево XML текста документа с пределом (1.11.x, предпросмотр документов,
// план владельца 04.11.2026).
//
// Текст документа (word/document.xml, content.xml) бывает в десятки
// мегабайт, а показывается только начало ([OfficeLimits.maxTextWeight]).
// Дерево XmlDocument из всей части заняло бы в памяти в разы больше самого
// текста, поэтому дерево строится здесь по событиям (parseEvents) и
// строительство прекращается, когда текста набралось заметно больше, чем
// покажут: на границе абзаца или таблицы верхнего уровня, а в огромной
// таблице — прямо внутри неё (незакрытые элементы просто остаются
// последними). Читателю достаётся обычное дерево XmlElement: работают
// OfficeXml (local, attr, kids) и пространства имён (xmlns копируются).
//
// Начало части, прочитанное через OfficeZip.readHead, обрывается на
// середине — ошибка разбора в конце такого текста не повреждение.

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

import 'office_package.dart';

class DocXml {
  DocXml._();

  /// Дерево из [text]. [blocks] — локальные имена элементов, за конец
  /// которых добавляется [OfficeLimits.blockWeight] (абзацы, ячейки, строки);
  /// [keepBlank] — родители, в которых текст из одних пробелов значим
  /// (w:t у Word; абзацы и фрагменты у OpenDocument). [stopDepth] —
  /// глубина элементов верхнего уровня текста (дети w:body — 2).
  /// [cutInput] — [text] — только начало части.
  ///
  /// `cut` в результате — показана не вся часть. Не XML (ошибка разбора до
  /// конца корневого элемента в целой части) — [OfficeDocError.damaged].
  static ({XmlElement root, bool cut}) parse(
    String text, {
    required Set<String> blocks,
    required bool Function(String parentLocal) keepBlank,
    int stopDepth = 2,
    bool cutInput = false,
    int softLimit = OfficeLimits.maxTextWeight * 2,
    int hardLimit = OfficeLimits.maxTextWeight * 4,
  }) {
    final stack = <XmlElement>[];
    XmlElement? root;
    var weight = 0;
    var cut = false;
    var done = false;
    try {
      for (final e in parseEvents(text)) {
        switch (e) {
          case XmlStartElementEvent():
            if (root != null && stack.isEmpty) {
              // Второй корневой элемент — мусор после документа.
              done = true;
              break;
            }
            final el = XmlElement(XmlName.fromString(e.name), [
              for (final a in e.attributes) XmlAttribute(XmlName.fromString(a.name), a.value),
            ]);
            if (stack.isEmpty) {
              root = el;
            } else {
              stack.last.children.add(el);
            }
            if (!e.isSelfClosing) stack.add(el);
          case XmlEndElementEvent():
            // Закрывающий тег без пары (испорченный, но читаемый документ) —
            // до ближайшего элемента с тем же именем, иначе пропустить.
            var i = stack.length - 1;
            while (i >= 0 && stack[i].name.qualified != e.name) {
              i--;
            }
            if (i < 0) break;
            final closed = stack[i];
            stack.removeRange(i, stack.length);
            if (blocks.contains(closed.name.local)) weight += OfficeLimits.blockWeight;
            if (stack.isEmpty) {
              done = true;
            } else if (weight > softLimit && stack.length <= stopDepth) {
              cut = true;
              done = true;
            }
          case XmlTextEvent():
          case XmlCDATAEvent():
            if (stack.isEmpty) break;
            final v = e is XmlTextEvent ? e.value : (e as XmlCDATAEvent).value;
            final parent = stack.last;
            if (v.trim().isEmpty && !keepBlank(parent.name.local)) break;
            parent.children.add(XmlText(v));
            weight += v.length;
            if (weight > hardLimit) {
              cut = true;
              done = true;
            }
          default:
            break;
        }
        if (done) break;
      }
    } on XmlException catch (e) {
      if (!cutInput && root == null) throw OfficeDocException(OfficeDocError.damaged, e.message);
      if (!cutInput && stack.isNotEmpty) throw OfficeDocException(OfficeDocError.damaged, e.message);
      cut = cut || stack.isNotEmpty;
    }
    if (root == null) throw const OfficeDocException(OfficeDocError.damaged, 'no root element');
    // Часть кончилась внутри документа (обрезанный файл): показать, что есть.
    if (stack.isNotEmpty && !done) cut = true;
    return (root: root, cut: cut || cutInput);
  }
}
