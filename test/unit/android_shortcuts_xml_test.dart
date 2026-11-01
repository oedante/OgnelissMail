// Ярлыки значка и App Actions Google Ассистента (1.9.x): res/xml/shortcuts.xml
// разбирается, ссылки на строки и списки слов есть, экраны ярлыков понимает
// Dart, манифест ссылается на файл.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/platform/assistant_actions.dart';
import 'package:xml/xml.dart';

const _res = 'android/app/src/main/res';
const _ns = 'http://schemas.android.com/apk/res/android';

Set<String> _names(String file, String tag) => {
  for (final e in XmlDocument.parse(File(file).readAsStringSync()).findAllElements(tag)) e.getAttribute('name')!,
};

void main() {
  final doc = XmlDocument.parse(File('$_res/xml/shortcuts.xml').readAsStringSync());
  final root = doc.rootElement;
  final shortcuts = root.findElements('shortcut').toList();

  test('корень и встроенные намерения', () {
    expect(root.name.local, 'shortcuts');
    final caps = root.findElements('capability').map((c) => c.getAttribute('name', namespace: _ns)).toList();
    expect(caps, ['actions.intent.OPEN_APP_FEATURE', 'actions.intent.GET_THING']);
    for (final c in root.findElements('capability')) {
      final intent = c.getElement('intent')!;
      expect(intent.getAttribute('targetClass', namespace: _ns), 'com.ogneliss.mail.MainActivity');
      expect(intent.getAttribute('action', namespace: _ns), 'com.ogneliss.mail.ASSISTANT');
      expect(intent.getElement('parameter')!.getAttribute('key', namespace: _ns), isIn(['feature', 'q']));
    }
  });

  test('первые четыре ярлыка — прежние быстрые действия; экраны понимает Dart', () {
    final ids = shortcuts.map((s) => s.getAttribute('shortcutId', namespace: _ns)).toList();
    expect(ids.take(4), ['myday', 'compose', 'event', 'reminder']);
    expect(ids.toSet().length, ids.length);
    for (final s in shortcuts) {
      final intent = s.getElement('intent')!;
      expect(intent.getAttribute('targetPackage', namespace: _ns), 'com.ogneliss.mail');
      expect(intent.getAttribute('targetClass', namespace: _ns), 'com.ogneliss.mail.MainActivity');
      final extra = intent.getElement('extra')!;
      expect(extra.getAttribute('name', namespace: _ns), 'ogneliss_widget');
      final type = extra.getAttribute('value', namespace: _ns)!;
      expect(AssistantAction.parse(type), isNotNull, reason: type);
      // OPEN_APP_FEATURE передаёт id ярлыка — его тоже понимает Dart.
      expect(
        AssistantAction.parse('feature?f=${s.getAttribute('shortcutId', namespace: _ns)}')?.kind,
        AssistantAction.parse(type)!.kind,
      );
    }
  });

  test('строки, списки слов и значки существуют', () {
    final strings = _names('$_res/values/strings.xml', 'string');
    final arraysEn = _names('$_res/values/app_actions.xml', 'string-array');
    final arraysRu = _names('$_res/values-ru/app_actions.xml', 'string-array');
    expect(arraysRu, arraysEn);
    for (final s in shortcuts) {
      for (final a in ['shortcutShortLabel', 'shortcutLongLabel']) {
        final v = s.getAttribute(a, namespace: _ns)!;
        expect(strings, contains(v.replaceFirst('@string/', '')), reason: v);
      }
      final icon = s.getAttribute('icon', namespace: _ns);
      if (icon != null) expect(File('$_res/drawable/${icon.replaceFirst('@drawable/', '')}.xml').existsSync(), isTrue);
      final binding = s.getElement('capability-binding')!.getElement('parameter-binding')!;
      expect(arraysEn, contains(binding.getAttribute('value', namespace: _ns)!.replaceFirst('@array/', '')));
    }
  });

  test('манифест подключает ярлыки к главной активности', () {
    final manifest = XmlDocument.parse(File('android/app/src/main/AndroidManifest.xml').readAsStringSync());
    final main = manifest
        .findAllElements('activity')
        .firstWhere((a) => a.getAttribute('name', namespace: _ns) == '.MainActivity');
    final meta = main
        .findElements('meta-data')
        .where((m) => m.getAttribute('name', namespace: _ns) == 'android.app.shortcuts')
        .single;
    expect(meta.getAttribute('resource', namespace: _ns), '@xml/shortcuts');
  });
}
