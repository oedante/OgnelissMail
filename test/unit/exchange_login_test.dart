// Логин Exchange (07.11.2026, аудит): имя для входа, отличное от адреса,
// идёт на сервер; имя по умолчанию (часть адреса до @) — вход как раньше.
import 'package:flutter_test/flutter_test.dart';
import 'package:mail_engine/mail_engine.dart' as me;

void main() {
  me.AccountConfig cfg({String? username, String? domain}) =>
      me.AccountConfig(email: 'i.ivanov@corp.ru', username: username, domain: domain);

  test('без имени и домена — адрес; с доменом — ДОМЕН\\часть-до-@', () {
    expect(cfg().exchangeLogin, 'i.ivanov@corp.ru');
    expect(cfg(domain: 'CORP').exchangeLogin, r'CORP\i.ivanov');
  });

  test('имя по умолчанию (часть адреса) — как раньше', () {
    expect(cfg(username: 'i.ivanov').exchangeLogin, 'i.ivanov@corp.ru');
    expect(cfg(username: 'I.Ivanov', domain: 'CORP').exchangeLogin, r'CORP\i.ivanov');
  });

  test('своё имя — с доменом или как введено', () {
    expect(cfg(username: 'ivanov_ii', domain: 'CORP').exchangeLogin, r'CORP\ivanov_ii');
    expect(cfg(username: 'ivanov_ii').exchangeLogin, 'ivanov_ii');
    expect(cfg(username: r'MSK\ivanov_ii', domain: 'CORP').exchangeLogin, r'MSK\ivanov_ii');
    expect(cfg(username: 'ivanov_ii@corp.local').exchangeLogin, 'ivanov_ii@corp.local');
  });
}
