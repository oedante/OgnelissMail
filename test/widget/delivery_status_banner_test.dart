// test/widget/delivery_status_banner_test.dart
// Строка доставки своего письма (1.9.x, просьба владельца 31.10.2026):
// «Не доставлено: … — адрес не существует (5.1.1)» с действиями, «Доставлено
// на сервер получателя» с оговоркой, чип «Отчёт о доставке» на отчёте.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/features/mail/providers/delivery_status_provider.dart';
import 'package:ogneliss/features/mail/widgets/delivery_status_banner.dart';
import 'package:ogneliss/l10n/app_localizations.dart';

final _now = DateTime(2026, 10, 31, 12);

EmailModel _mail({String id = 'Sent:5', String? mid = '<orig-1@example.com>'}) => EmailModel(
      id: id,
      accountId: 'a1',
      folderId: 'Sent',
      internetMessageId: mid,
      from: const EmailAddress(email: 'me@example.com'),
      to: const [EmailAddress(email: 'nobody@example.net')],
      subject: 'Отчёт',
      receivedAt: _now,
    );

DeliveryStatus _row(String recipient, String action, {String? status, String? diagnostic}) => DeliveryStatus(
      accountId: 'a1',
      messageId: 'orig-1@example.com',
      recipient: recipient,
      action: action,
      status: status,
      diagnostic: diagnostic,
      reportedAt: _now,
    );

Future<void> _pump(WidgetTester t, EmailModel email, {List<DeliveryStatus> rows = const [], Email? original}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      deliveryStatusesProvider.overrideWith((ref, k) => Stream.value(rows)),
      deliveryReportOriginalProvider.overrideWith((ref, k) async => original),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: DeliveryStatusBanner(email: email)),
    ),
  ));
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('не доставлено: причина простыми словами, код, ответ сервера и действия', (t) async {
    await _pump(t, _mail(), rows: [
      _row('nobody@example.net', 'failed', status: '5.1.1', diagnostic: '550 5.1.1 User unknown'),
    ]);
    expect(find.text('Не доставлено: nobody@example.net — адрес не существует (5.1.1)'), findsOneWidget);
    expect(find.text('550 5.1.1 User unknown'), findsOneWidget);
    expect(find.text('Отправить снова'), findsOneWidget);
    expect(find.text('Изменить адрес'), findsOneWidget);
  });

  testWidgets('задержка и доставка: без действий, с оговоркой «не уведомление о прочтении»', (t) async {
    await _pump(t, _mail(), rows: [
      _row('ok@example.net', 'relayed', status: '2.0.0'),
      _row('slow@example.net', 'delayed', status: '4.4.1'),
    ]);
    expect(find.text('Доставлено на сервер получателя: ok@example.net'), findsOneWidget);
    expect(find.textContaining('Задерживается: slow@example.net — сервер получателя пока не отвечает'), findsOneWidget);
    expect(find.textContaining('не уведомление о прочтении'), findsOneWidget);
    expect(find.text('Отправить снова'), findsNothing);
  });

  testWidgets('письмо-отчёт: чип «Отчёт о доставке»; обычное письмо — ничего', (t) async {
    final original = Email(
      id: 'Sent:5',
      accountId: 'a1',
      folderId: 'Sent',
      fromEmail: 'me@example.com',
      toRecipients: '[]',
      subject: 'Отчёт',
      receivedAt: _now,
      isRead: true,
      isFlagged: false,
      isDraft: false,
      isReplied: false,
      isForwarded: false,
      hasAttachments: false,
      priority: 1,
      status: 3,
      readReceiptRequested: false,
      isLocallyModified: false,
      loadedLevel: 0,
      controlState: 0,
      laterState: 0,
    );
    await _pump(t, _mail(id: 'INBOX:9', mid: '<bounce@mail.example.org>'), original: original);
    expect(find.text('Отчёт о доставке'), findsOneWidget);

    await _pump(t, _mail(id: 'INBOX:10', mid: null));
    expect(find.text('Отчёт о доставке'), findsNothing);
    expect(find.textContaining('Не доставлено'), findsNothing);
  });
}
