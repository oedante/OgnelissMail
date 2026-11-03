// «Управляется организацией» в настройках (MDM, 1.10.5): что задала
// организация и контакт ИТ-поддержки; без политики раздела нет.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/settings/widgets/managed_policy_section.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/services/security/managed_config.dart';

class _Fixed extends ManagedPolicyNotifier {
  _Fixed(this.p);
  final ManagedPolicy p;
  @override
  ManagedPolicy build() => p;
}

Future<void> _pump(WidgetTester t, ManagedPolicy p) async {
  await t.pumpWidget(ProviderScope(
    overrides: [managedPolicyProvider.overrideWith(() => _Fixed(p))],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Scaffold(body: SingleChildScrollView(child: ManagedPolicySection())),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('политика: организация, правила, поддержка', (t) async {
    await _pump(
        t,
        ManagedPolicy.fromMap(const {
          'org_name': 'ООО Ромашка',
          'support_contact': '+7 (495) 123-45-67',
          'account_email': 'i.petrov@romashka.ru',
          'allowed_domains': 'romashka.ru',
          'require_app_lock': true,
          'min_pin_length': 6,
          'block_share': true,
          'block_copy': true,
          'hide_notification_content': true,
        }));
    expect(find.text('Управляется организацией'), findsOneWidget);
    expect(find.text('ООО Ромашка'), findsOneWidget);
    expect(find.text('Ящик: i.petrov@romashka.ru'), findsOneWidget);
    expect(find.text('Только ящики доменов: romashka.ru'), findsOneWidget);
    expect(find.text('Обязательный код приложения (от 6 цифр)'), findsOneWidget);
    expect(find.text('«Поделиться», сохранение в файлы, PDF и печать запрещены'), findsOneWidget);
    expect(find.text('Копирование текста писем запрещено'), findsOneWidget);
    expect(find.text('Уведомления без отправителя и темы'), findsOneWidget);
    expect(find.text('Вложения открываются только в приложении'), findsNothing);
    expect(find.text('+7 (495) 123-45-67'), findsOneWidget);
  });

  testWidgets('без политики — раздела нет', (t) async {
    await _pump(t, ManagedPolicy.none);
    expect(find.text('Управляется организацией'), findsNothing);
  });

  test('контакт поддержки: телефон, почта, ссылка', () {
    expect(ManagedPolicySection.contactUri('+7 (495) 123-45-67').toString(), 'tel:+74951234567');
    expect(ManagedPolicySection.contactUri('it@romashka.ru').toString(), 'mailto:it@romashka.ru');
    expect(ManagedPolicySection.contactUri('https://help.romashka.ru').toString(), 'https://help.romashka.ru');
    expect(ManagedPolicySection.contactUri('Звоните Ивану'), isNull);
  });
}
