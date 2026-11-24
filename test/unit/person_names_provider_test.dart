// Словарь «адрес → полное имя» (personNamesProvider), 2.7.1: микрофризы
// 24.11.2026 — «Новое сообщение» открылось, но ~1,5 с не реагировало на
// нажатия. Провайдер читал все поля всех контактов (с фото CardDAV в базе
// текстом data:image — мегабайты) и разбирал JSON адресатов в главном
// потоке. Теперь — только адрес и имена, адресатов разбирает SQLite, много
// данных — в отдельном изоляте; правила выбора имени — прежние.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/security/secure_storage_service.dart';
import 'package:ogneliss/data/database/app_database.dart';
import 'package:ogneliss/data/providers/database_provider.dart';
import 'package:ogneliss/features/contacts/person_names.dart';
import 'package:ogneliss/features/mail/providers/mail_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer c;

  Future<void> email(String id, {String folder = 'INBOX', String from = 'x@corp.ru', String? fromName, Object? to, Object? cc, int at = 0}) =>
      db.customStatement(
          'INSERT INTO emails (id, account_id, folder_id, from_email, from_name, to_recipients, cc_json, subject, received_at) '
          "VALUES (?, 'a1', ?, ?, ?, ?, ?, 's', ?)",
          [id, folder, from, fromName, to is String ? to : jsonEncode(to ?? []), cc == null ? null : (cc is String ? cc : jsonEncode(cc)), at]);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement(
        "INSERT INTO accounts (id, type, email, display_name, username, created_at) VALUES ('a1', 0, 'me@corp.ru', 'Ермишин Олег Андреевич', 'me', 0)");
    await db.customStatement("INSERT INTO folders (id, account_id, display_name, type) VALUES ('INBOX','a1','Входящие',0)");
    await db.customStatement("INSERT INTO folders (id, account_id, display_name, type) VALUES ('Junk','a1','Спам',4)");
    c = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      accountsProvider.overrideWith((ref) => AccountsNotifier(db, SecureStorageService())),
    ]);
    await c.read(accountsProvider.notifier).loaded;
  });

  tearDown(() async {
    c.dispose();
    await db.close();
  });

  test('контакты, отправители, «Кому» и «Копия»; спам и свой адрес — по правилам', () async {
    // Контакт с фото из CardDAV (data:image в базе) — имя берётся, фото не нужно.
    await db.customStatement(
        'INSERT INTO contacts (id, email, display_name, first_name, middle_name, last_name, avatar_url) '
        "VALUES ('c1', 'Smirnov@Corp.ru', 'Смирнов Андрей', 'Андрей', 'Викторович', 'Смирнов', ?)",
        ['data:image/jpeg;base64,${'A' * 200000}']);
    await email('e1', from: 'petrov@corp.ru', fromName: 'Петров Иван Сергеевич');
    await email('e2', to: [
      {'email': 'sidorov@corp.ru', 'displayName': 'Сидоров Олег'},
      {'email': 'kuz@corp.ru', 'name': 'Кузнецова Мария Петровна'},
      {'email': 'one@corp.ru', 'displayName': 'Одно'},
      'не объект',
    ], cc: [
      {'email': 'cc@corp.ru', 'displayName': 'Копиев Пётр'},
    ]);
    // Битый JSON адресатов — пропускается, остальное читается.
    await email('e3', to: '[{"email": "broken@corp.ru"', fromName: 'Битый Отправитель Иванович', from: 'b@corp.ru');
    // Спам: имена не берутся ни у отправителя, ни у адресатов.
    await email('e4', folder: 'Junk', from: 'spam@corp.ru', fromName: 'Вам Перевод Получить',
        to: [{'email': 'victim@corp.ru', 'displayName': 'Жертва Спама'}]);
    // Свой адрес подписан чужим текстом — побеждает имя ящика.
    await email('e5', to: [{'email': 'me@corp.ru', 'displayName': 'Кто Угодно Ещё'}]);
    // Имя, разорванное посреди буквы, не вытесняет правильное.
    await email('e6', from: 'petrov@corp.ru', fromName: 'Петров Ив� 5г Сергеевич Длинный');

    final names = await c.read(personNamesProvider.future);
    expect(names['smirnov@corp.ru'], 'Смирнов Андрей Викторович');
    expect(names['petrov@corp.ru'], 'Петров Иван Сергеевич');
    expect(names['sidorov@corp.ru'], 'Сидоров Олег');
    expect(names['kuz@corp.ru'], 'Кузнецова Мария Петровна');
    expect(names['cc@corp.ru'], 'Копиев Пётр');
    expect(names['b@corp.ru'], 'Битый Отправитель Иванович');
    expect(names.containsKey('one@corp.ru'), isFalse);
    expect(names.containsKey('spam@corp.ru'), isFalse);
    expect(names.containsKey('victim@corp.ru'), isFalse);
    expect(names['me@corp.ru'], 'Ермишин Олег Андреевич');
  });

  test('новый счётчик непрочитанных у ящика не пересчитывает словарь', () async {
    await email('e1', from: 'petrov@corp.ru', fromName: 'Петров Иван Сергеевич');
    final sub = c.listen(personNamesProvider, (_, __) {});
    final first = await c.read(personNamesProvider.future);
    await c.read(accountsProvider.notifier).updateUnreadCount('a1', 42);
    await Future<void>.delayed(Duration.zero);
    expect(identical(await c.read(personNamesProvider.future), first), isTrue);
    sub.close();
  });

  test('много писем — словарь собирается в отдельном изоляте с тем же результатом', () async {
    await db.batch((b) {
      for (var i = 0; i < 4000; i++) {
        b.customStatement(
            'INSERT INTO emails (id, account_id, folder_id, from_email, from_name, to_recipients, subject, received_at) '
            "VALUES (?, 'a1', 'INBOX', ?, ?, '[]', 's', ?)",
            ['m$i', 's$i@corp.ru', 'Смирнов Андрей Викторович', i]);
      }
    });
    final names = await c.read(personNamesProvider.future);
    expect(names.length, 4001); // 4000 отправителей и свой ящик
    expect(names['s3999@corp.ru'], 'Смирнов Андрей Викторович');
  });

  test('buildPersonNames: из двух имён — полнее; свой ящик без имени — убирается', () {
    final out = buildPersonNames([
      ('a@x.ru', 'Иванов Иван'),
      ('A@x.ru', 'Иванов Иван Иванович'),
      ('a@x.ru', 'Иванов И.'),
      ('me@x.ru', 'Кто-то Чужой'),
    ], [
      (['me@x.ru'], 'me@x.ru'),
    ]);
    expect(out['a@x.ru'], 'Иванов Иван Иванович');
    expect(out.containsKey('me@x.ru'), isFalse);
  });
}
