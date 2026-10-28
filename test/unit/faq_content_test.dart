// 1.7.1: «Вопросы и ответы» — у каждого раздела и вопроса есть текст на
// всех четырёх языках, id разделов не повторяются, ссылки — на экраны
// настроек. С 1.7.3 тексты — в assets/l10n/<код>.xml (faq_<раздел>_…).
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/help/faq_content.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/l10n/strings_store.dart';

void main() {
  const langs = ['ru', 'en', 'de', 'fr'];

  test('разделы и вопросы на четырёх языках', () {
    expect(faqSections, isNotEmpty);
    final files = {for (final l in langs) l: StringsStore.parse(File('assets/l10n/$l.xml').readAsStringSync())};
    final ids = <String>{};
    for (final s in faqSections) {
      expect(ids.add(s.id), isTrue, reason: 'повтор раздела ${s.id}');
      expect(s.items, isNotEmpty, reason: s.id);
      for (final l in langs) {
        expect(files[l]!.strings['faq_${s.id}_title']?.trim(), isNotEmpty, reason: '${s.id} $l');
      }
      for (final it in s.items) {
        for (final l in langs) {
          expect(files[l]!.strings['faq_${it.key}_q']?.trim(), isNotEmpty, reason: '${it.key} $l');
          expect(files[l]!.strings['faq_${it.key}_a']?.trim(), isNotEmpty, reason: '${it.key} $l');
        }
        final r = it.route;
        if (r != null) {
          expect(r.startsWith('/settings') || r == '/vip-settings', isTrue, reason: r);
        }
      }
    }
  });

  test('текст на языке приложения, иначе английский', () {
    final item = faqSections.first.items.first;
    final ru = item.q(AppLocalizations(const Locale('ru')));
    final en = item.q(AppLocalizations(const Locale('en')));
    expect(ru, isNot(en));
    // Языка нет — английский.
    expect(item.q(AppLocalizations(const Locale('xx'))), en);
  });
}
