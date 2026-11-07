# Письма Outlook (.msg) для тестов

Настоящие письма Outlook из тестовых данных Apache POI (Apache License 2.0,
https://github.com/apache/poi/tree/trunk/test-data/hsmf), без изменений:

| Файл здесь | Файл POI | Зачем |
|---|---|---|
| `poi_cyrillic_message.msg` | `cyrillic_message.msg` | 8-битные строки в Windows-1251 |
| `poi_attachment_test_msg.msg` | `attachment_test_msg.msg` | два вложения, тема с «è», имя в кавычках |
| `poi_example_received_unicode.msg` | `example_received_unicode.msg` | Unicode, HTML из RTF, картинка по Content-ID |
| `poi_outlook_30_msg.msg` | `outlook_30_msg.msg` | Exchange, 18 получателей, HTML |
| `poi_quick.msg` | `quick.msg` | Exchange-отправитель без SMTP-адреса |

Copyright The Apache Software Foundation; лицензия —
https://www.apache.org/licenses/LICENSE-2.0. Файлы только для тестов, в
приложение не входят. Собранные письма для крайних случаев —
`test/unit/msg_builder.dart`.
