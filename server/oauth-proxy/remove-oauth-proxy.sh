#!/usr/bin/env bash
# =============================================================================
#  Ogneliss Mail — снять сервер входа (OAuth-прокси) с сервера (15.11.2026).
#
#  С 2.5.5 вход и обновление токенов идут только из приложений напрямую у
#  Google, Microsoft и Яндекса (решение владельца 15.11.2026). Логотипы
#  отправителей перенесены в службу погоды (server/weather-proxy). Сигналы о
#  почте (push-relay) и погода остаются.
#
#  Порядок: сначала выйти версии 2.5.5 и обновить службу погоды
#  (install-weather-proxy.sh install — в ней теперь /weather/bimi), потом —
#  этот скрипт. Приложения до 2.5.5 после снятия попросят войти заново и
#  не смогут: у них вход только через сервер.
#
#  Что делает:
#    1. Сохраняет .env, docker-compose.yml и том данных прокси в
#       /root/oauth-proxy-removed-<дата> (права 700).
#    2. Останавливает и удаляет контейнер oauth-proxy, его образ и том.
#    3. Отключает службы systemd oauth-proxy / ogneliss-oauth-proxy, если
#       остались от старых установок.
#    4. Переименовывает каталог /opt/mailserver/oauth-proxy в
#       oauth-proxy.removed-<дата> (секреты — только в копии из шага 1).
#    5. Подсказывает, что удалить в Nginx Proxy Manager (раздел /oauth).
#
#  Запуск:
#    sudo bash remove-oauth-proxy.sh --dry-run    # только показать план
#    sudo bash remove-oauth-proxy.sh              # выполнить
#  Параметры: --dir DIR (по умолчанию /opt/mailserver/oauth-proxy), --yes.
# =============================================================================
set -Eeuo pipefail
umask 077

ROOT="${OG_ROOT:-}"            # префикс ФС — только для автотестов
APP_DIR="/opt/mailserver/oauth-proxy"
CONTAINER="oauth-proxy"
PROJECT="oauth-proxy"
VOLUME="oauth-proxy_oauth-proxy-data"
IMAGE="ogneliss/oauth-proxy:latest"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$ROOT/root/oauth-proxy-removed-$STAMP"
DRY=0; YES=0

c_g=$'\e[32m'; c_y=$'\e[33m'; c_r=$'\e[31m'; c_b=$'\e[1m'; c_0=$'\e[0m'
[ -t 1 ] || { c_g=; c_y=; c_r=; c_b=; c_0=; }
ok()   { printf '  %s✓%s %s\n' "$c_g" "$c_0" "$*"; }
info() { printf '  · %s\n' "$*"; }
warn() { printf '  %s!%s %s\n' "$c_y" "$c_0" "$*"; }
die()  { printf '\n%s✗ %s%s\n' "$c_r" "$*" "$c_0" >&2; exit 1; }
run()  { if [ "$DRY" = 1 ]; then info "был бы выполнен: $*"; else "$@"; fi; }
done_() { [ "$DRY" = 1 ] || ok "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) APP_DIR="${2:?--dir: нужен каталог}"; shift ;;
    --dry-run) DRY=1 ;;
    --yes|-y) YES=1 ;;
    -h|--help) awk 'NR > 2 && /^# =+$/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) die "непонятный параметр: $1 (справка: --help)" ;;
  esac
  shift
done
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || [ -n "$ROOT" ] || die "нужны права root: sudo bash $0"
command -v docker >/dev/null || die "нет docker"

have_container=0; docker inspect "$CONTAINER" >/dev/null 2>&1 && have_container=1
have_volume=0; docker volume inspect "$VOLUME" >/dev/null 2>&1 && have_volume=1
have_dir=0; [ -d "$ROOT$APP_DIR" ] && have_dir=1
printf '%sСнятие сервера входа%s\n' "$c_b" "$c_0"
info "контейнер $CONTAINER: $([ $have_container = 1 ] && echo есть || echo нет)"
info "том $VOLUME: $([ $have_volume = 1 ] && echo есть || echo нет)"
info "каталог ${APP_DIR}: $([ $have_dir = 1 ] && echo есть || echo нет)"
[ $have_container = 1 ] || [ $have_volume = 1 ] || [ $have_dir = 1 ] || { ok "сервера входа на этом сервере нет — делать нечего"; exit 0; }

if [ "$DRY" != 1 ] && [ "$YES" != 1 ] && [ -t 0 ]; then
  read -r -p "  Снять сервер входа (копия — в ${BACKUP#$ROOT})? [y/N] " a
  [[ "$a" =~ ^[YyДд] ]] || die "отменено"
fi

# 1. Копия
run mkdir -p "$BACKUP"
[ "$DRY" = 1 ] || chmod 700 "$BACKUP"
if [ $have_dir = 1 ]; then
  for f in .env docker-compose.yml; do
    [ -f "$ROOT$APP_DIR/$f" ] && run cp -p "$ROOT$APP_DIR/$f" "$BACKUP/"
  done
fi
if [ $have_volume = 1 ]; then
  run docker run --rm -v "$VOLUME:/data:ro" -v "$BACKUP:/backup" alpine:3 sh -c 'cp -a /data/. /backup/data/ 2>/dev/null || (mkdir -p /backup/data && cp -a /data/. /backup/data/)'
fi
done_ "копия: ${BACKUP#$ROOT}"

# 2. Контейнер, образ, том
if [ $have_container = 1 ]; then
  run docker stop "$CONTAINER" >/dev/null
  run docker rm "$CONTAINER" >/dev/null
  done_ "контейнер $CONTAINER удалён"
fi
docker image inspect "$IMAGE" >/dev/null 2>&1 && { run docker image rm "$IMAGE" >/dev/null || warn "образ $IMAGE не удалён"; }
[ $have_volume = 1 ] && { run docker volume rm "$VOLUME" >/dev/null && done_ "том $VOLUME удалён"; }

# 3. Старые службы systemd
for u in oauth-proxy ogneliss-oauth-proxy; do
  if systemctl list-unit-files "$u.service" >/dev/null 2>&1 && systemctl list-unit-files "$u.service" | grep -q "^$u.service"; then
    run systemctl disable --now "$u.service" || warn "служба $u не остановлена"
    done_ "служба systemd $u отключена"
  fi
done

# 4. Каталог
if [ $have_dir = 1 ]; then
  run mv "$ROOT$APP_DIR" "$ROOT$APP_DIR.removed-$STAMP"
  done_ "каталог переименован: $APP_DIR.removed-$STAMP"
fi

printf '\n%sГотово.%s\n' "$c_b" "$c_0"
cat <<EOF
  Копия секретов и данных: ${BACKUP#$ROOT} (удалите, когда убедитесь, что всё работает).

  Осталось вручную в Nginx Proxy Manager (хост ogneliss.ru → Edit → Advanced):
    удалить раздел «location /oauth …» (или «location ^~ /oauth/ …»).
    Разделы /push/ и /weather/ не трогайте: сигналы, погода и логотипы.

  Проверка: https://www.ogneliss.ru/oauth/healthz — 404,
            https://www.ogneliss.ru/weather/healthz — 200 (в ответе есть "bimi").
EOF
