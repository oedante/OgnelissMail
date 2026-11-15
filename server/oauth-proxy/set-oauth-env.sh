#!/usr/bin/env bash
# =============================================================================
#  Ogneliss Mail — правка /opt/mailserver/oauth-proxy/.env и перезапуск прокси
#  (15.11.2026).
#
#  Что делает:
#    1. Копирует .env в .env.bak-<дата> (права 600).
#    2. Меняет или добавляет строки KEY=VALUE, удаляет ключи из --unset.
#    3. Пересоздаёт контейнер oauth-proxy: docker restart .env не
#       перечитывает, нужен docker compose up -d --force-recreate. Хранилище
#       сессий (том oauth-proxy-data) остаётся — вход у пользователей не
#       пропадает.
#    4. Ждёт ответа /healthz и сверяет значения внутри контейнера.
#       Прокси не поднялся — возвращает прежний .env и пересоздаёт контейнер
#       ещё раз.
#
#  Запуск на сервере (из каталога server/oauth-proxy архива или откуда угодно):
#    sudo bash set-oauth-env.sh --google-scope        # права Google (ниже)
#    sudo bash set-oauth-env.sh KEY=VALUE [KEY=VALUE…] # любые ключи
#    sudo bash set-oauth-env.sh --unset KEY            # удалить ключ
#    sudo bash set-oauth-env.sh --show                 # показать (секреты скрыты)
#    sudo bash set-oauth-env.sh --dry-run …            # только показать изменения
#
#  Параметры:
#    --dir DIR        каталог прокси (по умолчанию /opt/mailserver/oauth-proxy)
#    --google-scope   GOOGLE_SCOPE — права, заявленные в Google Cloud
#                     (15.11.2026: без gmail.settings.basic): почта (IMAP и
#                     SMTP), календарь, контакты, openid, адрес и профиль
#    --no-restart     только записать .env
#    --yes            не спрашивать подтверждения
#
#  Лимит пользователей Google (100 из 100 в Cloud Console, «OAuth user cap»):
#    sudo bash set-oauth-env.sh GOOGLE_USER_CAP=1          # закрыть новый вход
#    sudo bash set-oauth-env.sh --unset GOOGLE_USER_CAP    # открыть снова
#  Нужен server.js от 15.11.2026 и новее (в /healthz — "googleUserCap").
#
#  Значения с пробелами — одним аргументом в кавычках:
#    sudo bash set-oauth-env.sh "GOOGLE_SCOPE=openid email profile"
#  В .env они пишутся без кавычек (так читает env_file у docker-compose 1.x).
# =============================================================================
set -Eeuo pipefail
umask 077

ROOT="${OG_ROOT:-}"            # префикс ФС — только для автотестов
APP_DIR="/opt/mailserver/oauth-proxy"
CONTAINER="oauth-proxy"
PROJECT="oauth-proxy"
GOOGLE_SCOPE_VALUE='https://mail.google.com/ https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/carddav openid email profile'

c_g=$'\e[32m'; c_y=$'\e[33m'; c_r=$'\e[31m'; c_b=$'\e[1m'; c_0=$'\e[0m'
[ -t 1 ] || { c_g=; c_y=; c_r=; c_b=; c_0=; }
ok()   { printf '  %s✓%s %s\n' "$c_g" "$c_0" "$*"; }
info() { printf '  · %s\n' "$*"; }
warn() { printf '  %s!%s %s\n' "$c_y" "$c_0" "$*"; }
die()  { printf '\n%s✗ %s%s\n' "$c_r" "$*" "$c_0" >&2; exit 1; }

SETS=()      # KEY=VALUE
UNSETS=()    # KEY
SHOW=0; DRY=0; YES=0; RESTART=1
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) APP_DIR="${2:?--dir: нужен каталог}"; shift ;;
    --google-scope) SETS+=("GOOGLE_SCOPE=$GOOGLE_SCOPE_VALUE") ;;
    --unset) UNSETS+=("${2:?--unset: нужен ключ}"); shift ;;
    --show) SHOW=1 ;;
    --dry-run) DRY=1 ;;
    --no-restart) RESTART=0 ;;
    --yes|-y) YES=1 ;;
    -h|--help) awk 'NR > 2 && /^# =+$/ { exit } NR > 2 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *=*) SETS+=("$1") ;;
    *) die "непонятный параметр: $1 (справка: --help)" ;;
  esac
  shift
done

ENV_FILE="$ROOT$APP_DIR/.env"
[ -f "$ENV_FILE" ] || die "нет файла $ENV_FILE (каталог прокси — параметр --dir)"
[ "$DRY" = 1 ] || [ "$SHOW" = 1 ] || [ "$(id -u)" = 0 ] || [ -n "$ROOT" ] || die "нужны права root: sudo bash $0 …"

key_ok() { [[ "$1" =~ ^[A-Z][A-Z0-9_]*$ ]]; }
secret_key() { [[ "$1" =~ (SECRET|_KEY|TOKEN|PASS|PRIVATE) ]]; }
# Значение ключа в файле (последняя строка KEY=…, как у docker-compose).
env_get() { grep -E "^$1=" "$2" 2>/dev/null | tail -n 1 | cut -d= -f2- || true; }
fp() { printf '%s' "$1" | sha256sum | cut -c1-8; }
shown() {   # значение для экрана: секреты — длиной и отпечатком
  local k="$1" v="$2"
  if [ -z "$v" ]; then printf '(пусто)'
  elif secret_key "$k"; then printf '(скрыто: %s симв., отпечаток %s)' "${#v}" "$(fp "$v")"
  else printf '%s' "$v"; fi
}

if [ "$SHOW" = 1 ]; then
  printf '%s%s%s\n' "$c_b" "${ENV_FILE#$ROOT}" "$c_0"
  grep -E '^[A-Z][A-Z0-9_]*=' "$ENV_FILE" | while IFS= read -r line; do
    k="${line%%=*}"; printf '  %s = %s\n' "$k" "$(shown "$k" "${line#*=}")"
  done
  [ ${#SETS[@]} -eq 0 ] && [ ${#UNSETS[@]} -eq 0 ] && exit 0
fi

[ ${#SETS[@]} -gt 0 ] || [ ${#UNSETS[@]} -gt 0 ] || die "нечего менять (справка: --help)"
for s in "${SETS[@]}"; do
  k="${s%%=*}"; v="${s#*=}"
  key_ok "$k" || die "неверное имя ключа: $k"
  [[ "$v" != *$'\n'* ]] || die "$k: перевод строки в значении недопустим"
done
for k in "${UNSETS[@]}"; do key_ok "$k" || die "неверное имя ключа: $k"; done

# ── Новый .env во временном файле ────────────────────────────────────────────
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$ENV_FILE" "$TMP/new.env"
CHANGED=()
for k in "${UNSETS[@]}"; do
  if grep -qE "^$k=" "$TMP/new.env"; then
    grep -vE "^$k=" "$TMP/new.env" > "$TMP/x" || true; mv "$TMP/x" "$TMP/new.env"
    CHANGED+=("$k"); printf '  − %s\n' "$k"
  else
    info "$k: в .env нет — пропуск"
  fi
done
for s in "${SETS[@]}"; do
  k="${s%%=*}"; v="${s#*=}"
  old="$(env_get "$k" "$TMP/new.env")"
  if grep -qE "^$k=" "$TMP/new.env"; then
    [ "$old" = "$v" ] && { info "$k: уже $(shown "$k" "$v")"; continue; }
    # Все строки ключа заменяются одной — на месте первой.
    K="$k" V="$v" awk 'BEGIN{k=ENVIRON["K"]; v=ENVIRON["V"]; n=length(k)+1}
      substr($0,1,n)==k"=" { if (!done) { print k"="v; done=1 }; next } { print }' \
      "$TMP/new.env" > "$TMP/x"
    mv "$TMP/x" "$TMP/new.env"
  else
    [ -z "$(tail -c1 "$TMP/new.env")" ] || echo >> "$TMP/new.env"
    printf '%s=%s\n' "$k" "$v" >> "$TMP/new.env"
  fi
  CHANGED+=("$k")
  printf '  %s:\n    было:  %s\n    стало: %s\n' "$k" "$(shown "$k" "$old")" "$(shown "$k" "$v")"
done

if [ ${#CHANGED[@]} -eq 0 ]; then ok "изменений нет"; exit 0; fi
if [ "$DRY" = 1 ]; then info "--dry-run: .env не изменён"; exit 0; fi
if [ "$YES" != 1 ] && [ -t 0 ]; then
  read -r -p "  Записать .env$([ "$RESTART" = 1 ] && printf ' и пересоздать контейнер %s' "$CONTAINER")? [y/N] " a
  [[ "$a" =~ ^[YyДд] ]] || die "отменено"
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$ENV_FILE.bak-$STAMP"
cp -p "$ENV_FILE" "$BACKUP"; chmod 600 "$BACKUP"
ok "копия: ${BACKUP#$ROOT}"
cat "$TMP/new.env" > "$ENV_FILE"     # тот же файл: владелец и права прежние
chmod 600 "$ENV_FILE"
ok ".env записан"

[ "$RESTART" = 1 ] || { info "--no-restart: контейнер не пересоздан"; exit 0; }

# ── Пересоздание контейнера ──────────────────────────────────────────────────
if docker compose version >/dev/null 2>&1; then DC=(docker compose)
elif command -v docker-compose >/dev/null; then DC=(docker-compose)
else die "нет docker compose — .env записан, перезапустите прокси вручную (копия: $BACKUP)"; fi
COMPOSE=""
for f in docker-compose.yml compose.yml docker-compose.yaml compose.yaml; do
  [ -f "$ROOT$APP_DIR/$f" ] && { COMPOSE="$f"; break; }
done
[ -n "$COMPOSE" ] || die "в ${APP_DIR} нет docker-compose.yml — .env записан; прокси ставится заново: sudo bash reinstall-oauth-proxy.sh"

BASE_URL="$(env_get BASE_URL "$ENV_FILE")"; BASE_URL="${BASE_URL:-https://www.ogneliss.ru/oauth}"; BASE_URL="${BASE_URL%/}"
HZ_PATH="$(printf '%s' "$BASE_URL" | sed -E 's#^https?://[^/]+##')/healthz"

recreate() {
  (cd "$ROOT$APP_DIR" && "${DC[@]}" -p "$PROJECT" -f "$COMPOSE" up -d --no-build --force-recreate) >"$TMP/compose.log" 2>&1
}
healthy() {
  for _ in $(seq 1 30); do
    docker exec "$CONTAINER" node -e \
      "fetch('http://127.0.0.1:8787$HZ_PATH').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))" \
      >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}
rollback() {
  warn "$1 — возвращаю прежний .env"
  cat "$BACKUP" > "$ENV_FILE"
  if recreate && healthy; then die "$1. Прежний .env восстановлен, прокси работает (журнал: docker logs $CONTAINER)"; fi
  die "$1, и с прежним .env прокси тоже не поднялся: docker logs $CONTAINER; копия .env: $BACKUP"
}

info "пересоздаю контейнер $CONTAINER (${DC[*]} -p $PROJECT up -d --force-recreate)"
recreate || { tail -n 30 "$TMP/compose.log" >&2; rollback "docker compose не пересоздал контейнер"; }
healthy || { docker logs --tail 30 "$CONTAINER" >&2 || true; rollback "прокси не отвечает на $HZ_PATH"; }
ok "прокси отвечает ($HZ_PATH)"

# Значения внутри контейнера — те, что записаны.
bad=0
for k in "${CHANGED[@]}"; do
  want="$(env_get "$k" "$ENV_FILE")"
  got="$(docker exec "$CONTAINER" printenv "$k" 2>/dev/null || true)"
  if [ "$got" = "$want" ]; then ok "$k в контейнере: $(shown "$k" "$got")"
  else warn "$k в контейнере: $(shown "$k" "$got") — ожидалось $(shown "$k" "$want")"; bad=1; fi
done
[ "$bad" = 0 ] || warn "значения не совпали: проверьте environment: в ${APP_DIR}/$COMPOSE (он сильнее .env)"

printf '\n%sГотово.%s Копия прежнего .env: %s\n' "$c_b" "$c_0" "${BACKUP#$ROOT}"
printf '  Вернуть: sudo cp %s %s && cd %s && %s -p %s up -d --force-recreate\n' \
  "${BACKUP#$ROOT}" "${ENV_FILE#$ROOT}" "$APP_DIR" "${DC[*]}" "$PROJECT"
