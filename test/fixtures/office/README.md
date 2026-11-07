# Образцы документов для тестов

Свои образцы делают скрипты в `tool/dev/office_fixtures/` (тексты — свои).

Из тестовых данных Apache POI (Apache License 2.0,
https://github.com/apache/poi/tree/trunk/test-data/spreadsheet), без изменений:

| Файл здесь | Файл POI | Зачем |
|---|---|---|
| `poi_password.xls` | `password.xls` | книга Excel, RC4, пароль «password» |
| `poi_cryptoapi.xls` | `35897-type4.xls` | книга Excel, RC4 CryptoAPI, пароль «freedom» |
| `poi_excel5.xls` | `testEXCEL_5.xls` | Excel 5 (BIFF5) из Excel для Mac |
| `poi_book_caps.xls` | `BOOK_in_capitals.xls` | книга BIFF8 в потоке «BOOK» |

Copyright The Apache Software Foundation; лицензия —
https://www.apache.org/licenses/LICENSE-2.0. Файлы только для тестов, в
приложение не входят.
