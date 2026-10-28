# Валидный TLS для почты mail.ogneliss.ru (docker-mailserver)

## Проблема

Gmail-app и другие клиенты не подключаются к `mail.ogneliss.ru` по **993 (SSL/TLS)** —
«Не удалось подключиться к серверу». Работает только без шифрования (143/587, «Нет»).

**Причина:** docker-mailserver по умолчанию генерирует **самоподписанный** сертификат
(`SSL_TYPE` не задан). Клиенты его отвергают.

**Почему NPM не помогает:** Nginx Proxy Manager терминирует только HTTP(S) на 80/443.
IMAP (993/143) и SMTP (587/465) идут **напрямую в контейнер mailserver**, мимо NPM —
поэтому сертификат для почты нужно ставить в сам mailserver.

## Решение

Есть валидный сертификат **GlobalSign GCC R3 DV TLS CA 2020**, покрывающий:

| Домен | |
|---|---|
| `ogneliss.ru` | |
| `www.ogneliss.ru` | (CN) |
| **`mail.ogneliss.ru`** | ← нужен для почты |
| `autodiscover.ogneliss.ru` | (пригодится для автонастройки) |
| `owa.ogneliss.ru` | |

Срок: **14.07.2026 → 29.01.2027**. Let's Encrypt не требуется.

### Шаг 1. Скопировать файлы на сервер

```bash
# с локальной машины
scp certificate.crt certificate_key.p8 certificate_ca.crt root@217.114.43.126:/root/certs/
```

### Шаг 2. Запустить установщик

```bash
cd /root/certs
sudo bash setup-mail-tls-ogneliss.sh          # найдёт файлы сам
# либо явно:
sudo bash setup-mail-tls-ogneliss.sh certificate.crt certificate_key.p8 certificate_ca.crt
```

**Папка почтового сервера определяется автоматически** — скрипт ищет `docker-compose.yml`
с сервисом `mailserver` (в `/opt/mailserver`, `/root`, `/opt`, `/srv`, текущей папке) и
печатает найденный путь — **сверьте его**. Если определилось неверно:
```bash
MAILSERVER_DIR=/путь/к/почте bash setup-mail-tls-ogneliss.sh
```

**Имена файлов не важны** — скрипт ищет их по содержимому (в текущей папке, рядом с собой,
в `/root` и `/root/certs`): сертификат домена определяется по SAN с `mail.ogneliss.ru`,
цепочка — по флагу `CA:TRUE`, ключ — по PEM-заголовку `BEGIN ... PRIVATE KEY`.
Панели хостинга часто отдают ключ как `certificate.key` / `private.key` — это нормально.

Если чего-то не хватает, скрипт покажет, **что именно** и **что нашёл** в папках.

Скрипт:
1. проверит, что **ключ соответствует сертификату** (сверка modulus);
2. проверит, что в SAN есть `mail.ogneliss.ru`;
3. проверит срок и цепочку;
4. соберёт `fullchain.pem` = сертификат домена + **промежуточный** GlobalSign
   (корневой не нужен — он в доверенных хранилищах клиентов);
5. разложит в `/opt/mailserver/ssl/` с правами (`privkey.pem` → 0600);
6. напечатает готовый фрагмент для `docker-compose.yml`.

### Шаг 3. Прописать в docker-compose.yml

В `/opt/mailserver/docker-compose.yml`, сервис `mailserver`:

```yaml
  mailserver:
    # ...существующее...
    environment:
      # ...существующее...
      - SSL_TYPE=manual
      - SSL_CERT_PATH=/tmp/dms/custom-certs/fullchain.pem
      - SSL_KEY_PATH=/tmp/dms/custom-certs/privkey.pem
    volumes:
      # ...существующее...
      - ./ssl:/tmp/dms/custom-certs:ro
```

> `/tmp/dms/custom-certs` — штатный путь docker-mailserver для своих сертификатов
> (не удаляется, несмотря на `/tmp` в имени).

### Шаг 4. Применить

```bash
cd /opt/mailserver
docker-compose up -d mailserver     # пересоздаст контейнер с новым сертификатом
```

### Шаг 5. Проверить

```bash
# IMAPS
openssl s_client -connect mail.ogneliss.ru:993 -servername mail.ogneliss.ru </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer -subject -dates
# ожидается: issuer=... GlobalSign ..., subject=CN=www.ogneliss.ru, срок до 29.01.2027

# SMTP submission (STARTTLS)
openssl s_client -starttls smtp -connect mail.ogneliss.ru:587 -servername mail.ogneliss.ru </dev/null 2>/dev/null \
  | openssl x509 -noout -issuer -dates
```

### Настройки в почтовом клиенте (после установки)

| | Сервер | Порт | Шифрование |
|---|---|---|---|
| **IMAP** | `mail.ogneliss.ru` | 993 | SSL/TLS |
| **SMTP** | `mail.ogneliss.ru` | 587 | STARTTLS |
| SMTP (альт.) | `mail.ogneliss.ru` | 465 | SSL/TLS |

Имя пользователя — полный адрес (`oedante@ogneliss.ru`).

## Обновление сертификата (до 29.01.2027)

GlobalSign не продлевается автоматически (в отличие от Let's Encrypt). Порядок:

```bash
# 1) получить новые файлы у GlobalSign
# 2) переустановить
sudo bash setup-mail-tls-ogneliss.sh <новый.crt> <новый_key.p8> <новый_ca.crt>
# 3) перезапустить
cd /opt/mailserver && docker-compose restart mailserver
```

Поставьте напоминание на **начало января 2027** (за 3–4 недели до истечения).

## Заметки

- **Тот же сертификат** можно поставить в NPM для `mail.ogneliss.ru` / `ogneliss.ru`
  (SSL Certificates → Add → **Custom**), если нужен веб-доступ (roundcube) по HTTPS без
  Let's Encrypt.
- `autodiscover.ogneliss.ru` в SAN — при желании можно поднять автонастройку клиентов.
- **Ключ**: файл `certificate_key.p8` в формате PKCS#1 (`BEGIN RSA PRIVATE KEY`),
  несмотря на расширение `.p8`. Postfix/Dovecot читают и PKCS#1, и PKCS#8 — работает.
- Если после перезапуска клиент всё ещё ругается — проверьте, что контейнер видит файлы:
  `docker exec mailserver ls -l /tmp/dms/custom-certs`.
- **Приватный ключ** — секрет: права 0600, в git не коммитить (`server/**/ssl/` в
  .gitignore), при передаче по незащищённым каналам — перевыпустить.

## Если ключа нет

Приватный ключ создаётся **в момент выпуска CSR** и у удостоверяющего центра его нет —
GlobalSign не сможет прислать ключ повторно. Варианты:

1. **Ищите там, где выпускали.** Если сертификат заказан через панель хостинга/регистратора
   — ключ обычно скачивается там же (раздел SSL → скачать → `private.key`).
2. **Проверьте, не под другим именем.** На сервере:
   ```bash
   grep -rl "PRIVATE KEY" /root /etc/ssl 2>/dev/null
   ```
3. **Если ключ утерян** — сертификат бесполезен, нужен **перевыпуск** (reissue) у
   GlobalSign с новым CSR. Перевыпуск в рамках оплаченного срока обычно бесплатный.

Проверить, что ключ подходит к сертификату:
```bash
openssl x509 -in certificate.crt -noout -modulus | openssl md5
openssl rsa  -in certificate_key.p8 -noout -modulus | openssl md5
# хэши должны совпасть
```
