# Тестовые образцы S/MIME

Сделаны OpenSSL 3 для `test/unit/smime_test.dart`. Ключ и сертификат —
только для тестов (самоподписанный «Ivan Ivanov <ivanov@corp.test>»),
пароль .p12 — `secret`.

- `aes.p12` — PBES2 + AES-256-CBC (OpenSSL 3 по умолчанию);
- `legacy.p12` — PBE-SHA1-3DES (как старые экспорты Windows);
- `signed.eml` — multipart/signed, SHA-256;
- `encrypted*.eml` — enveloped-data: AES-256, 3DES, AES-128 с RSA-OAEP.
