// Поля {…} подписей и приветствий (18.11.2026, просьба владельца: «свои
// приветствия с поддержкой {тэгов}; в конструкторе подписи и приветствия —
// набор таких тэгов»).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/l10n/strings_store.dart';
import 'package:ogneliss/services/mail/mail_tags.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await StringsStore.ensure('ru');
    await StringsStore.ensure('en');
  });

  final morning = DateTime(2026, 11, 18, 9, 5);

  test('русские и английские написания, любой регистр; ваши поля — как в подписях раньше', () {
    final v = MailTagValues(
      sender: MailTags.sender(
          displayName: 'Ермишин Олег Андреевич', email: 'o@corp.example', card: const {'title': 'Инженер'}),
      now: morning,
    );
    expect(MailTags.apply('{name}, {Должность}, {ПОЧТА}', v), 'Ермишин Олег Андреевич, Инженер, o@corp.example');
    expect(MailTags.apply('{имя} {дата} {время}', v), 'Ермишин Олег Андреевич 18.11.2026 09:05');
    expect(MailTags.apply('{фио}', v), 'Ермишин Олег Андреевич', reason: 'как в шаблонах ответов');
  });

  test('адресат: обращение как в стандартном приветствии, имя, фамилия', () {
    final r = MailTags.recipient(
        names: ['Кузнецов Максим Геннадьевич'], emails: ['m@corp.example'], lang: 'ru');
    expect(r['to_address'], 'Максим Геннадьевич');
    expect(r['to_first_name'], 'Максим');
    expect(r['to_last_name'], 'Кузнецов');
    final v = MailTagValues(recipient: r, now: morning, lang: 'ru');
    expect(MailTags.apply('{время_суток}, {обращение}!', v, cleanup: true), 'Доброе утро, Максим Геннадьевич!');
    expect(MailTags.apply('Здравствуйте, {имя_адресата} {фамилия_адресата}!', v, cleanup: true),
        'Здравствуйте, Максим Кузнецов!');
  });

  test('без имени адресата поле пропадает вместе с запятой', () {
    final v = MailTagValues(
        recipient: MailTags.recipient(names: [''], emails: ['info@shop.example'], lang: 'ru'), now: morning);
    expect(MailTags.apply('Здравствуйте, {обращение}!', v, cleanup: true), 'Здравствуйте!');
    expect(MailTags.apply('{обращение}, добрый день!', v, cleanup: true), 'Добрый день!');
    expect(MailTags.apply('Привет {неизвестное} !', v, cleanup: true), 'Привет!');
  });

  test('несколько адресатов: до трёх — через запятую, больше трёх коллег — «коллеги»', () {
    final two = MailTags.recipient(
        names: ['Иванов Иван Петрович', 'Сидорова Мария Сергеевна'],
        emails: ['i@corp.example', 'm@corp.example'],
        lang: 'ru');
    expect(two['to_address'], 'Иван Петрович, Мария Сергеевна');
    final many = MailTags.recipient(
      names: ['А Б', 'В Г', 'Д Е', 'Ж З'],
      emails: ['a@corp.example', 'b@corp.example', 'c@corp.example', 'd@corp.example'],
      lang: 'ru',
      ownDomains: {'corp.example'},
    );
    expect(many['to_address'], 'коллеги');
    final outside = MailTags.recipient(
      names: ['А Б', 'В Г', 'Д Е', 'Ж З'],
      emails: ['a@corp.example', 'b@gmail.com', 'c@corp.example', 'd@corp.example'],
      lang: 'ru',
      ownDomains: {'corp.example'},
    );
    expect(outside['to_address'], '');
  });

  test('время суток по часам отправки', () {
    expect(MailTags.partOfDay('ru', DateTime(2026, 1, 1, 7)), 'Доброе утро');
    expect(MailTags.partOfDay('ru', DateTime(2026, 1, 1, 14)), 'Добрый день');
    expect(MailTags.partOfDay('ru', DateTime(2026, 1, 1, 21)), 'Добрый вечер');
    expect(MailTags.partOfDay('en', DateTime(2026, 1, 1, 2)), 'Good evening');
  });

  test('HTML: значения экранируются', () {
    final v = MailTagValues(
        sender: MailTags.sender(displayName: 'R&D <Lab>', email: 'x@corp.example'), now: morning);
    expect(MailTags.apply('<b>{name}</b>', v, html: true), '<b>R&amp;D &lt;Lab&gt;</b>');
  });

  test('кнопки: подпись — ваши поля и дата; вставка — по языку приложения', () {
    expect(MailTags.forSignature.map((t) => t.key),
        ['date', 'name', 'title', 'department', 'company', 'phone', 'email']);
    final t = MailTags.all.firstWhere((t) => t.key == 'to_address');
    expect(t.insertText('ru'), '{обращение}');
    expect(t.insertText('en'), '{to_address}');
  });
}
