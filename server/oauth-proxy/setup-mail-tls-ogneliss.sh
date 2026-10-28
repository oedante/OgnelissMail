#!/usr/bin/env bash
# setup-mail-tls-ogneliss.sh
# Установка валидного TLS-сертификата (GlobalSign) в docker-mailserver для
# mail.ogneliss.ru. Решает проблему: клиенты (Gmail-app и др.) не подключаются
# по 993/465 из-за самоподписанного сертификата docker-mailserver.
#
# Скрипт НЕ правит ваш docker-compose.yml автоматически — он проверяет
# сертификат, раскладывает файлы и печатает готовый фрагмент для вставки.
#
# Запуск:
#   sudo bash setup-mail-tls-ogneliss.sh                       # файлы в текущей папке
#   sudo bash setup-mail-tls-ogneliss.sh /path/certificate.crt /path/certificate_key.p8 /path/certificate_ca.crt

set -euo pipefail

MAIL_DOMAIN="${MAIL_DOMAIN:-mail.ogneliss.ru}"
# MAILSERVER_DIR определяется автоматически (см. ниже), либо задайте вручную:
#   MAILSERVER_DIR=/root bash setup-mail-tls-ogneliss.sh
MAILSERVER_DIR="${MAILSERVER_DIR:-}"

say()  { echo -e "==> $*"; }
err()  { echo -e "ОШИБКА: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "запустите через sudo"
command -v openssl >/dev/null || err "нужен openssl (apt install -y openssl)"

# ── Автоопределение папки docker-mailserver ───────────────────────────────
# Ищем docker-compose.yml, в котором объявлен сервис/образ mailserver.
if [ -z "$MAILSERVER_DIR" ]; then
  for d in /opt/mailserver /root /opt /srv "$(pwd)"; do
    for cf in "$d/docker-compose.yml" "$d/docker-compose.yaml" "$d/compose.yml"; do
      [ -f "$cf" ] || continue
      if grep -qiE "docker-mailserver|mailserver:" "$cf"; then
        MAILSERVER_DIR="$d"
        break 2
      fi
    done
  done
fi
if [ -z "$MAILSERVER_DIR" ]; then
  err "не найден docker-compose.yml с сервисом mailserver.
Укажите папку явно:  MAILSERVER_DIR=/путь bash $0"
fi
SSL_DIR="$MAILSERVER_DIR/ssl"
say "Папка почтового сервера: $MAILSERVER_DIR"

say "Сертификат для $MAIL_DOMAIN"

CRT="${1:-}"
KEY="${2:-}"
CA="${3:-}"

# Папка поиска: где лежит скрипт, плюс текущая.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIRS=("." "$SCRIPT_DIR" "/root" "/root/certs")

is_cert() { openssl x509 -in "$1" -noout >/dev/null 2>&1; }
is_key()  { openssl pkey -in "$1" -noout >/dev/null 2>&1 || openssl rsa -in "$1" -noout >/dev/null 2>&1; }
cert_mod() { openssl x509 -in "$1" -noout -modulus 2>/dev/null | openssl md5; }
key_mod()  { openssl pkey -in "$1" -noout -modulus 2>/dev/null | openssl md5 || openssl rsa -in "$1" -noout -modulus 2>/dev/null | openssl md5; }
is_ca_cert() { openssl x509 -in "$1" -noout -text 2>/dev/null | grep -q "CA:TRUE"; }
covers_domain() {
  openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null | tr -d ' ' | grep -q "DNS:$MAIL_DOMAIN" \
    || openssl x509 -in "$1" -noout -subject 2>/dev/null | grep -q "$MAIL_DOMAIN"
}

# ── Автопоиск по СОДЕРЖИМОМУ (имена файлов не важны) ──────────────────────
if [ -z "$CRT" ] || [ -z "$KEY" ] || [ -z "$CA" ]; then
  say "Автопоиск файлов сертификата (имена не важны — смотрим содержимое)"
  CANDIDATES=()
  for d in "${SEARCH_DIRS[@]}"; do
    [ -d "$d" ] || continue
    while IFS= read -r f; do CANDIDATES+=("$f"); done < <(find "$d" -maxdepth 1 -type f -size -100k 2>/dev/null)
  done

  for f in "${CANDIDATES[@]}"; do
    if [ -z "$KEY" ] && is_key "$f"; then KEY="$f"; continue; fi
    if is_cert "$f"; then
      if [ -z "$CRT" ] && covers_domain "$f" && ! is_ca_cert "$f"; then CRT="$f"; continue; fi
      if [ -z "$CA" ] && is_ca_cert "$f"; then CA="$f"; continue; fi
    fi
  done

  [ -n "$CRT" ] && echo "    сертификат домена: $CRT"
  [ -n "$KEY" ] && echo "    приватный ключ:    $KEY"
  [ -n "$CA" ]  && echo "    цепочка CA:        $CA"
fi

# ── Понятная диагностика, если чего-то нет ────────────────────────────────
if [ -z "$CRT" ] || [ -z "$KEY" ] || [ -z "$CA" ]; then
  echo "" >&2
  echo "Не хватает файлов:" >&2
  [ -z "$CRT" ] && echo "  ✗ сертификат домена (с $MAIL_DOMAIN в SAN)" >&2
  [ -z "$KEY" ] && echo "  ✗ приватный ключ (PEM: BEGIN ... PRIVATE KEY)" >&2
  [ -z "$CA" ]  && echo "  ✗ цепочка CA (промежуточный сертификат)" >&2
  echo "" >&2
  echo "Что найдено в ${SEARCH_DIRS[*]}:" >&2
  for d in "${SEARCH_DIRS[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      [ -f "$f" ] || continue
      kind="—"
      is_cert "$f" && { kind="сертификат"; is_ca_cert "$f" && kind="сертификат (CA)"; }
      is_key "$f" && kind="приватный ключ"
      [ "$kind" = "—" ] || echo "    $f  →  $kind" >&2
    done
  done
  echo "" >&2
  SRV_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "Скопируйте недостающее НА ЭТОТ СЕРВЕР (команда для вашего компьютера):" >&2
  echo "  scp certificate.crt certificate_key.p8 certificate_ca.crt root@${SRV_IP:-<IP-сервера>}:/root/" >&2
  echo "или укажите пути явно:" >&2
  echo "  sudo bash $0 <cert> <key> <ca>" >&2
  exit 1
fi

for f in "$CRT" "$KEY" "$CA"; do
  [ -f "$f" ] || err "не найден файл: $f"
done

# ── 1. Проверки ────────────────────────────────────────────────────────────
say "Проверка: ключ соответствует сертификату"
CM=$(openssl x509 -in "$CRT" -noout -modulus 2>/dev/null | openssl md5)
KM=$(openssl rsa  -in "$KEY" -noout -modulus 2>/dev/null | openssl md5 || true)
if [ -z "$KM" ] || [ "$KM" = "$(printf '' | openssl md5)" ]; then
  # возможно PKCS#8 — пробуем универсальный pkey
  KM=$(openssl pkey -in "$KEY" -noout -modulus 2>/dev/null | openssl md5 || true)
fi
[ -n "$KM" ] || err "не удалось прочитать приватный ключ: $KEY"
[ "$CM" = "$KM" ] || err "ключ НЕ соответствует сертификату (modulus не совпал)"
echo "    ключ подходит"

say "Проверка: сертификат покрывает $MAIL_DOMAIN"
SAN=$(openssl x509 -in "$CRT" -noout -ext subjectAltName 2>/dev/null | tr -d ' ' || true)
SUBJ=$(openssl x509 -in "$CRT" -noout -subject 2>/dev/null || true)
if echo "$SAN" | grep -q "DNS:$MAIL_DOMAIN" || echo "$SUBJ" | grep -q "$MAIL_DOMAIN"; then
  echo "    домен присутствует"
else
  err "в сертификате нет $MAIL_DOMAIN
SAN: $SAN
Subject: $SUBJ"
fi

say "Проверка: срок действия"
openssl x509 -in "$CRT" -noout -dates | sed 's/^/    /'
if ! openssl x509 -in "$CRT" -noout -checkend 0 >/dev/null; then
  err "сертификат ПРОСРОЧЕН"
fi

say "Проверка: цепочка"
if openssl verify -CAfile "$CA" "$CRT" >/dev/null 2>&1; then
  echo "    цепочка валидна"
else
  echo "    ВНИМАНИЕ: openssl verify не подтвердил цепочку — проверьте порядок в $CA"
fi

# ── 2. Сборка fullchain ────────────────────────────────────────────────────
# fullchain = сертификат домена + промежуточный CA (корневой не обязателен).
say "Сборка fullchain.pem"
mkdir -p "$SSL_DIR"
TMP_CHAIN=$(mktemp)
cat "$CRT" > "$TMP_CHAIN"
# берём ТОЛЬКО первый (промежуточный) сертификат из CA-файла
awk 'BEGIN{n=0} /-----BEGIN CERTIFICATE-----/{n++} n==1{print} /-----END CERTIFICATE-----/{if(n==1) exit}' "$CA" >> "$TMP_CHAIN"
CERTS_IN_CHAIN=$(grep -c "BEGIN CERTIFICATE" "$TMP_CHAIN")
echo "    сертификатов в цепочке: $CERTS_IN_CHAIN (домен + промежуточный)"

install -m 0644 "$TMP_CHAIN" "$SSL_DIR/fullchain.pem"
install -m 0600 "$KEY"       "$SSL_DIR/privkey.pem"
install -m 0644 "$CA"        "$SSL_DIR/ca.pem"
rm -f "$TMP_CHAIN"
say "Файлы установлены:"
ls -l "$SSL_DIR" | sed 's/^/    /'

# ── 3. Фрагмент для docker-compose ─────────────────────────────────────────
COMPOSE_FILE="$MAILSERVER_DIR/docker-compose.yml"
cat <<EOF

────────────────────────────────────────────────────────────────────────
ЧТО ДОБАВИТЬ в $COMPOSE_FILE (сервис mailserver):

  mailserver:
    # ...существующие настройки...
    environment:
      # ...существующие...
      - SSL_TYPE=manual
      - SSL_CERT_PATH=/tmp/dms/custom-certs/fullchain.pem
      - SSL_KEY_PATH=/tmp/dms/custom-certs/privkey.pem
    volumes:
      # ...существующие...
      - ./ssl:/tmp/dms/custom-certs:ro

Затем применить:
  cd $MAILSERVER_DIR
  docker-compose up -d mailserver        # пересоздаст контейнер

Проверить:
  openssl s_client -connect $MAIL_DOMAIN:993 -servername $MAIL_DOMAIN </dev/null 2>/dev/null \\
    | openssl x509 -noout -issuer -subject -dates
  # ожидается issuer=GlobalSign, subject содержит $MAIL_DOMAIN

В почтовом клиенте после этого:
  IMAP: $MAIL_DOMAIN : 993 : SSL/TLS
  SMTP: $MAIL_DOMAIN : 587 : STARTTLS   (или 465 : SSL/TLS)
────────────────────────────────────────────────────────────────────────
EOF

# ── 4. Подсказка по текущему compose ───────────────────────────────────────
if [ -f "$COMPOSE_FILE" ]; then
  say "Текущее состояние $COMPOSE_FILE:"
  if grep -q "SSL_TYPE" "$COMPOSE_FILE"; then
    echo "    SSL_TYPE уже задан:"
    grep -n "SSL_TYPE\|SSL_CERT_PATH\|SSL_KEY_PATH" "$COMPOSE_FILE" | sed 's/^/      /'
    echo "    → замените значения на указанные выше"
  else
    echo "    SSL_TYPE не найден → добавьте блок environment выше"
  fi
  if grep -q "custom-certs" "$COMPOSE_FILE"; then
    echo "    том custom-certs уже смонтирован"
  else
    echo "    → не забудьте добавить том: - ./ssl:/tmp/dms/custom-certs:ro"
  fi
else
  echo "    (файл $COMPOSE_FILE не найден — укажите MAILSERVER_DIR=/путь)"
fi

cat <<EOF

ОБНОВЛЕНИЕ СЕРТИФИКАТА (GlobalSign, истекает $(openssl x509 -in "$CRT" -noout -enddate | cut -d= -f2)):
  1) получите новые certificate.crt / certificate_key.p8 / certificate_ca.crt
  2) sudo bash $0 <новые пути>
  3) cd $MAILSERVER_DIR && docker-compose restart mailserver

EOF
say "Готово."
