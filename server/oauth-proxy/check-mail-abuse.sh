#!/usr/bin/env bash
# =============================================================================
#  Проверка почтового сервера ogneliss.ru (docker-mailserver): не рассылает ли
#  он чужие письма. Только ЧТЕНИЕ — ничего не меняет.
#
#  Повод (07.10.2026): в рабочий ящик приходят отказы «Не удается доставить:
#  Missed Call (0.28 Sec)» от MAILER-DAEMON@localhost.localdomain — письмо
#  «от вас» на адрес рабочего домена отклонил шлюз получателя («blocked
#  due to security reason»). Обычно это фишинг с подделанным обратным
#  адресом (отказ приходит тому, чей адрес подставили). Но «localhost.
#  localdomain» — признак Postfix с ненастроенным именем хоста, и надо
#  исключить, что это наш сервер работает открытым релеем или через него
#  шлёт спам взломанный ящик.
#
#  Запуск:  sudo bash check-mail-abuse.sh [ИМЯ_КОНТЕЙНЕРА] [ДОМЕН_ПОЛУЧАТЕЛЯ]
# =============================================================================
set -uo pipefail

C="${1:-}"
if [ -z "$C" ]; then
  C="$(docker ps --format '{{.Names}} {{.Image}}' | awk 'tolower($0) ~ /docker-mailserver|mailserver/ {print $1; exit}')"
fi
[ -n "$C" ] || { echo "Контейнер почтового сервера не найден — укажите имя: $0 ИМЯ"; exit 1; }
echo "== Контейнер: $C"

pc() { docker exec "$C" postconf -h "$1" 2>/dev/null; }

echo
echo "== 1. Имя сервера (в отказе было localhost.localdomain)"
echo "  myhostname = $(pc myhostname)"
echo "  mydomain   = $(pc mydomain)"
echo "  hostname контейнера: $(docker exec "$C" hostname -f 2>/dev/null)"

echo
echo "== 2. Кому разрешено отправлять без входа (открытый релей?)"
echo "  mynetworks = $(pc mynetworks)"
echo "  smtpd_relay_restrictions = $(pc smtpd_relay_restrictions)"
echo "  smtpd_recipient_restrictions = $(pc smtpd_recipient_restrictions)"
mn="$(pc mynetworks)"
case "$mn" in
  *0.0.0.0/0*|*::/0*) echo "  !!! mynetworks разрешает ВСЕМ — это открытый релей";;
  *172.16.0.0/12*|*192.168.0.0/16*|*10.0.0.0/8*)
    echo "  !  в mynetworks частные сети Docker. Если контейнер видит внешние адреса"
    echo "     как адрес шлюза Docker (NAT без userland-proxy), ЛЮБОЙ из интернета"
    echo "     выглядит «своим». В docker-mailserver: PERMIT_DOCKER=none";;
esac
docker exec "$C" printenv PERMIT_DOCKER 2>/dev/null | sed 's/^/  PERMIT_DOCKER=/'

echo
# Домен получателя отказов — вторым аргументом (например, corp.example).
DOM="${2:-missed call}"
echo "== 3. Следы письма «Missed Call» и адресатов $DOM в журнале"
LOG=/var/log/mail/mail.log
docker exec "$C" sh -c "test -f $LOG" 2>/dev/null || LOG=/var/log/mail.log
docker exec "$C" sh -c "grep -ihE 'missed call|$DOM' $LOG $LOG.1 2>/dev/null | tail -n 30" \
  || echo "  (журнал не найден)"
docker logs --since 72h "$C" 2>&1 | grep -iE "missed call|$DOM" | tail -n 20

echo
echo "== 4. Кто отправлял через сервер с входом (sasl_username) за журнал"
docker exec "$C" sh -c "grep -ho 'sasl_username=[^, ]*' $LOG $LOG.1 2>/dev/null | sort | uniq -c | sort -rn | head -n 15"
echo "  (большое число у одного ящика — подозрение на взлом пароля)"

echo
echo "== 5. Очередь (неотправленные письма)"
docker exec "$C" postqueue -p 2>/dev/null | tail -n 15

echo
echo "== 6. Отказы, которые сервер САМ отправил (bounce) за журнал"
docker exec "$C" sh -c "grep -h 'sender non-delivery notification' $LOG $LOG.1 2>/dev/null | wc -l" \
  | sed 's/^/  уведомлений об отказе: /'

cat <<'EOF'

== Как читать
  · В разделах 3–6 пусто, mynetworks без 0.0.0.0/0 и PERMIT_DOCKER=none —
    наш сервер ни при чём: это чужая рассылка с подделанным адресом
    отправителя (backscatter). Действия — у ИТ организации (SPF/DMARC
    её домена с политикой reject), а отказ можно удалить.
  · Нашлись «Missed Call» в журнале или много писем у одного sasl_username —
    смените пароль этого ящика, проверьте очередь (postsuper -d ALL deferred
    после проверки) и пришлите вывод — разберём.
  · Убедиться наверняка: заголовки Received внутри вложенного в отказ письма
    (в Outlook: «Свойства» вложения) — первый Received показывает, откуда
    письмо на самом деле ушло.
EOF
