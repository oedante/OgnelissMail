#!/usr/bin/env bash
# =============================================================================
#  Ogneliss Mail — «будильник» для iPhone (push-relay): установка, обновление
#  и проверка. Сервер с Docker и Nginx Proxy Manager — тот же, где OAuth-прокси
#  и сайт (/opt/mailserver). Запуск от root.
#
#  Команды:
#    install   первая установка (по умолчанию); повторный запуск — как update
#    update    обновить код службы из этого архива; .env, ключи и токены
#              остаются
#    key       поставить или заменить ключ APNs (.p8) и Team ID
#    check     проверить: контейнер, ключ (пробный сигнал Apple), адрес снаружи
#    remove    остановить и удалить контейнер (каталог с .env, ключом и
#              токенами остаётся)
#
#  Примеры:
#    sudo bash install-push-relay.sh install --team ABCDE12345 --key /root/AuthKey_XYZ1234567.p8
#    sudo bash install-push-relay.sh key --key /root/AuthKey_NEW1234567.p8
#    sudo bash install-push-relay.sh update
#    sudo bash install-push-relay.sh check
#
#  Подробно: README.md рядом и docs/guides/IOS_PUSH_SETUP.md (раздел 3).
#
#  Что хранит служба: только токены уведомлений Apple (случайные
#  идентификаторы установок), окружение, интервал и время последнего сигнала.
#  Ни адресов, ни паролей, ни писем. Значения ключей скрипт на экран не выводит.
# =============================================================================
set -Eeuo pipefail
umask 077

SCRIPT_VERSION="2026.10.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Префикс файловой системы — только для автотестов скрипта. Не задавайте его.
ROOT="${OG_ROOT:-}"

# ── Параметры (флаги перекрывают переменные окружения) ──────────────────────
CMD=""
MAIL_DIR="${MAIL_DIR:-/opt/mailserver}"
NPM_NETWORK="${NPM_NETWORK:-}"
BASE_URL_ARG="${BASE_URL:-}"
TEAM_ARG="${APNS_TEAM_ID:-}"
KEY_SRC=""
KEY_ID_ARG=""
KEY_SANDBOX=0
ASSUME_YES="${ASSUME_YES:-0}"
PORT=8788
CONTAINER=push-relay
COMPOSE_FILE=docker-compose.push.yml
DEFAULT_BASE_URL="https://www.ogneliss.ru/push"
# Пользователь node в образе node:alpine.
APP_UID=1000

# ── Вывод ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_B=$'\e[1m'; C_0=$'\e[0m'
else C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""; fi
log()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*" >&2; }
ok()   { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$*" >&2; }
warn() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
bad()  { printf '  %s✗%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { printf '%sОШИБКА:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
trap 'printf "%sОШИБКА%s в строке %s: %s\n" "$C_R" "$C_0" "$LINENO" "$BASH_COMMAND" >&2' ERR

usage() {
  sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'
Флаги:
  --team TEAMID         Team ID учётной записи Apple Developer (10 символов)
  --key FILE            ключ APNs AuthKey_<KEYID>.p8 (Key ID берётся из имени)
  --key-id KEYID        Key ID, если файл назван иначе
  --sandbox             ключ из --key — только для Sandbox (сборки из Xcode);
                        без флага ключ работает для Production, а если
                        отдельного ключа Sandbox нет — и для Sandbox
  --base-url URL        внешний адрес службы, по умолчанию
                        https://www.ogneliss.ru/push
  --mail-dir DIR        каталог почтового сервера, по умолчанию /opt/mailserver
  --network NAME        сеть Docker Nginx Proxy Manager (по умолчанию — общая
                        с контейнерами proxy-manager и oauth-proxy)
  --yes                 не задавать вопросов
EOF
}

# ── Разбор аргументов ───────────────────────────────────────────────────────
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      install|update|key|check|remove|help) CMD="$1" ;;
      -h|--help) CMD=help ;;
      --team) TEAM_ARG="${2:?}"; shift ;;
      --key) KEY_SRC="${2:?}"; shift ;;
      --key-id) KEY_ID_ARG="${2:?}"; shift ;;
      --sandbox) KEY_SANDBOX=1 ;;
      --base-url) BASE_URL_ARG="${2:?}"; shift ;;
      --mail-dir) MAIL_DIR="${2:?}"; shift ;;
      --network) NPM_NETWORK="${2:?}"; shift ;;
      -y|--yes) ASSUME_YES=1 ;;
      *) die "неизвестный параметр: $1 (см. --help)" ;;
    esac
    shift
  done
  [ -n "$CMD" ] || CMD=install
  if [ -n "$TEAM_ARG" ]; then
    TEAM_ARG="$(printf '%s' "$TEAM_ARG" | tr '[:lower:]' '[:upper:]')"
    [[ "$TEAM_ARG" =~ ^[A-Z0-9]{10}$ ]] || die "--team: 10 латинских букв и цифр (Membership details на developer.apple.com)"
    # Образец из инструкции, а не настоящий Team ID (24.10.2026: Apple
    # ответила 403 InvalidProviderToken — в команду попал образец).
    [ "$TEAM_ARG" != ABCDE12345 ] || die "--team ABCDE12345 — это образец из инструкции. Свой Team ID: developer.apple.com → Account → Membership details → Team ID"
  fi
  APP_DIR="$ROOT$MAIL_DIR/push-relay"
  ENV_FILE="$APP_DIR/.env"
  KEYS_DIR="$APP_DIR/keys"
  DATA_DIR="$APP_DIR/data"
  OAUTH_ENV="$ROOT$MAIL_DIR/oauth-proxy/.env"
}

# ── Утилиты ─────────────────────────────────────────────────────────────────
need_root() { [ -n "$ROOT" ] || [ "$(id -u)" -eq 0 ] || die "запустите от root: sudo bash $0 ${CMD}"; }
have() { command -v "$1" >/dev/null 2>&1; }
ask() {  # ask "вопрос" "по умолчанию" → ответ
  local a=""
  if [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then read -r -p "$1 [$2]: " a || true; fi
  printf '%s' "${a:-$2}"
}

# Чтение и запись KEY=VALUE в .env без интерпретации значения.
env_get() {  # env_get KEY FILE → значение (последнее вхождение)
  [ -f "$2" ] || return 0
  K="$1" awk 'index($0, ENVIRON["K"] "=") == 1 { v = substr($0, length(ENVIRON["K"]) + 2) } END { sub(/\r$/, "", v); printf "%s", v }' "$2"
}
env_has() { [ -f "$2" ] && grep -q "^$1=" "$2"; }
env_set() {  # env_set KEY VALUE FILE — заменить (в том числе строку «#KEY=») или дописать
  local tmp; tmp="$(mktemp "$3.XXXXXX")"
  K="$1" V="$2" awk '
    index($0, ENVIRON["K"] "=") == 1 || index($0, "#" ENVIRON["K"] "=") == 1 {
      if (!done) { print ENVIRON["K"] "=" ENVIRON["V"]; done = 1 }; next }
    { print }
    END { if (!done) print ENVIRON["K"] "=" ENVIRON["V"] }' "$3" > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$3"
}

# Короткое значение из JSON ответа службы: json_val '"keys":{' production
json_obj() {  # json_obj JSON NAME → содержимое {…} у поля NAME (без вложенных)
  printf '%s' "$1" | sed -n "s/.*\"$2\":{\([^}]*\)}.*/\1/p"
}
json_val() {  # json_val FRAGMENT NAME → значение поля (число, true/false или строка без кавычек)
  printf '%s' "$1" | sed -n "s/.*\"$2\":\(\"[^\"]*\"\|[^,}]*\).*/\1/p" | sed 's/^"//; s/"$//'
}

parse_base_url() {  # задаёт BASE_URL, BASE_HOST, BASE_PATH
  BASE_URL="${1%/}"
  if [[ "$BASE_URL" =~ ^https://([A-Za-z0-9.-]+)(/[A-Za-z0-9/_-]*)$ ]]; then
    BASE_HOST="${BASH_REMATCH[1]}"; BASE_PATH="${BASH_REMATCH[2]%/}"
  else
    die "адрес службы должен быть вида https://домен/путь (например $DEFAULT_BASE_URL), получено: $1"
  fi
  [ -n "$BASE_PATH" ] || die "в адресе нужен путь, например $DEFAULT_BASE_URL"
}

resolve_base_url() {
  local url="$BASE_URL_ARG"
  [ -n "$url" ] || url="$(env_get PUBLIC_URL "$ENV_FILE")"
  [ -n "$url" ] || url="$DEFAULT_BASE_URL"
  parse_base_url "$url"
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then DC=(docker compose); DC_V2=1
  elif have docker-compose; then DC=(docker-compose); DC_V2=0
  else die "нет docker compose / docker-compose"; fi
}

# Сеть Nginx Proxy Manager: общая у proxy-manager и oauth-proxy (через неё
# уже работает вход /oauth), иначе первая сеть proxy-manager.
detect_network() {
  [ -n "$NPM_NETWORK" ] && return 0
  local npm_nets oauth_nets n
  npm_nets="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' proxy-manager 2>/dev/null || true)"
  oauth_nets="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' oauth-proxy 2>/dev/null || true)"
  for n in $npm_nets; do
    case " $oauth_nets " in *" $n "*) NPM_NETWORK="$n"; return 0 ;; esac
  done
  NPM_NETWORK="$(printf '%s' "$npm_nets" | awk '{print $1}')"
  [ -n "$NPM_NETWORK" ] || NPM_NETWORK="mailserver_default"
}

check_sources() {
  local f
  for f in server.js package.json Dockerfile .env.example; do
    [ -f "$SCRIPT_DIR/$f" ] || die "нет $SCRIPT_DIR/$f — копируйте на сервер всю папку server/push-relay, а не только скрипт"
  done
  grep -q "async function probe()" "$SCRIPT_DIR/server.js" \
    || die "$SCRIPT_DIR/server.js — старая версия. Возьмите папку из свежего архива."
}

# ── Файлы службы ────────────────────────────────────────────────────────────
copy_code() {
  install -d -m 750 "$APP_DIR"
  install -d -m 700 "$DATA_DIR"
  install -d -m 750 "$KEYS_DIR"
  if [ -z "$ROOT" ]; then
    chown "$APP_UID:$APP_UID" "$DATA_DIR"
    chown "root:$APP_UID" "$KEYS_DIR"
  fi
  install -m 644 "$SCRIPT_DIR/server.js" "$SCRIPT_DIR/package.json" "$SCRIPT_DIR/Dockerfile" "$APP_DIR/"
  install -m 644 "$SCRIPT_DIR/.env.example" "$APP_DIR/.env.example"
  [ -f "$SCRIPT_DIR/README.md" ] && install -m 644 "$SCRIPT_DIR/README.md" "$APP_DIR/README.md"
  printf '.env\n*.env\nkeys\ndata\n*.p8\nbackup-*\n' > "$APP_DIR/.dockerignore"; chmod 644 "$APP_DIR/.dockerignore"
  write_compose
  ok "файлы службы: $APP_DIR"
}

write_compose() {
  local nets
  if [ "${DC_V2:-1}" = 1 ]; then
    nets="networks:
  npm:
    external: true
    name: $NPM_NETWORK"
  else
    nets="networks:
  npm:
    external:
      name: $NPM_NETWORK"
  fi
  {
    echo "# Создано install-push-relay.sh $SCRIPT_VERSION. Контейнер в сети Nginx Proxy Manager."
    [ "${DC_V2:-1}" = 1 ] || echo 'version: "2.1"'
    cat <<EOF
services:
  $CONTAINER:
    build: .
    image: ogneliss/push-relay:latest
    container_name: $CONTAINER
    env_file:
      - ./.env
    environment:
      - HOST=0.0.0.0
      - PORT=$PORT
      - DATA_FILE=/data/tokens.json
    expose:
      - "$PORT"
    volumes:
      - ./data:/data
      - ./keys:/keys:ro
    restart: always
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    mem_limit: 256m
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:$PORT$BASE_PATH/healthz"]
      interval: 60s
      timeout: 5s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "5m"
        max-file: "2"
    networks:
      - npm
$nets
EOF
  } > "$APP_DIR/$COMPOSE_FILE"
  chmod 644 "$APP_DIR/$COMPOSE_FILE"
}

# .env: первый раз — из .env.example; потом только дописываются новые ключи
# образца, заданные значения не меняются.
prepare_env() {
  local first=0 k line
  if [ ! -f "$ENV_FILE" ]; then
    first=1
    { echo "# Создано install-push-relay.sh $(date +%F). Права 600. В git и в почту не отправлять."
      cat "$SCRIPT_DIR/.env.example"; } > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  else
    while IFS= read -r line; do
      k="${line%%=*}"
      [[ "$line" =~ ^[A-Z_]+= ]] || continue
      env_has "$k" "$ENV_FILE" || { printf '%s\n' "$line" >> "$ENV_FILE"; ok "добавлено в .env: $k"; }
    done < "$SCRIPT_DIR/.env.example"
  fi
  env_set PUBLIC_URL "$BASE_URL" "$ENV_FILE"
  env_set BASE_PATH "$BASE_PATH" "$ENV_FILE"

  # Ключ приложения — тот же, что у OAuth-прокси (OAUTH_PROXY_KEY в сборке).
  if [ -z "$(env_get PUSH_API_KEY "$ENV_FILE")" ]; then
    local pk; pk="$(env_get PROXY_API_KEY "$OAUTH_ENV")"
    if [ -n "$pk" ]; then
      env_set PUSH_API_KEY "$pk" "$ENV_FILE"
      ok "ключ приложения взят из $OAUTH_ENV (PROXY_API_KEY)"
    else
      warn "не найден PROXY_API_KEY в $OAUTH_ENV — регистрация будет без ключа приложения"
      warn "задайте PUSH_API_KEY в $ENV_FILE (= OAUTH_PROXY_KEY из сборки) и выполните: sudo bash $0 update"
    fi
  fi

  if [ -n "$TEAM_ARG" ]; then
    env_set APNS_TEAM_ID "$TEAM_ARG" "$ENV_FILE"; ok "Team ID: $TEAM_ARG"
  elif [ -z "$(env_get APNS_TEAM_ID "$ENV_FILE")" ] && [ "$ASSUME_YES" != 1 ] && [ -t 0 ]; then
    local t; t="$(ask "Team ID Apple Developer (Enter — позже)" "")"
    t="$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')"
    if [[ "$t" =~ ^[A-Z0-9]{10}$ ]]; then env_set APNS_TEAM_ID "$t" "$ENV_FILE"; ok "Team ID: $t"
    elif [ -n "$t" ]; then warn "Team ID пропущен: нужно 10 латинских букв и цифр"; fi
  fi
  chmod 600 "$ENV_FILE"
  [ "$first" = 1 ] && ok "создан $ENV_FILE" || true
}

# Ключ APNs: проверка до любых изменений на сервере; Key ID — из имени файла
# AuthKey_<KEYID>.p8 (так его выдаёт Apple) или из --key-id.
KEY_ID=""
check_key() {
  [ -n "$KEY_SRC" ] || return 0
  [ -f "$KEY_SRC" ] || die "нет файла ключа: $KEY_SRC"
  grep -q -- "-----BEGIN PRIVATE KEY-----" "$KEY_SRC" || die "$KEY_SRC — не ключ APNs (.p8 из developer.apple.com → Keys)"
  if have openssl && ! openssl pkey -in "$KEY_SRC" -noout >/dev/null 2>&1; then
    die "$KEY_SRC: файл повреждён (openssl не читает ключ)"
  fi
  local id="$KEY_ID_ARG" base
  base="$(basename "$KEY_SRC")"
  # Браузер или Windows иногда дописывают расширение: AuthKey_X.p8.pem,
  # AuthKey_X.pem, AuthKey_X.p8.txt (24.10.2026 — .p8.pem) — тоже годится.
  if [ -z "$id" ] && [[ "$base" =~ ^AuthKey_([A-Za-z0-9]{10})(\.p8)?(\.pem|\.txt)?$ ]] && [ "$base" != "AuthKey_${BASH_REMATCH[1]}" ]; then
    id="${BASH_REMATCH[1]}"
  fi
  id="$(printf '%s' "$id" | tr '[:lower:]' '[:upper:]')"
  [[ "$id" =~ ^[A-Z0-9]{10}$ ]] || die "не понятен Key ID: назовите файл AuthKey_<KEYID>.p8, как его выдаёт Apple, или укажите --key-id"
  KEY_ID="$id"
}

# Копия ключа в keys/AuthKey_<KEYID>.p8: читать может только служба.
put_key() {
  [ -n "$KEY_SRC" ] || return 0
  local id="$KEY_ID"
  install -d -m 750 "$KEYS_DIR"
  install -m 640 "$KEY_SRC" "$KEYS_DIR/AuthKey_$id.p8"
  if [ -z "$ROOT" ]; then chown "root:$APP_UID" "$KEYS_DIR" "$KEYS_DIR/AuthKey_$id.p8"; fi
  if [ "$KEY_SANDBOX" = 1 ]; then
    env_set APNS_SANDBOX_KEY_ID "$id" "$ENV_FILE"
    env_set APNS_SANDBOX_KEY_FILE "/keys/AuthKey_$id.p8" "$ENV_FILE"
    ok "ключ Sandbox: Key ID $id"
  else
    env_set APNS_KEY_ID "$id" "$ENV_FILE"
    env_set APNS_KEY_FILE "/keys/AuthKey_$id.p8" "$ENV_FILE"
    ok "ключ Production: Key ID $id"
  fi
  chmod 600 "$ENV_FILE"
  warn "исходный файл $KEY_SRC можно удалить: копия — в $KEYS_DIR (храните оригинал в надёжном месте, Apple второй раз его не выдаст)"
}

backup_env() {
  [ -f "$ENV_FILE" ] || return 0
  local b; b="$APP_DIR/backup-$(date +%Y%m%d-%H%M%S)"
  install -d -m 700 "$b"
  cp -p "$ENV_FILE" "$b/.env"
  [ -f "$APP_DIR/$COMPOSE_FILE" ] && cp -p "$APP_DIR/$COMPOSE_FILE" "$b/"
  ok "резервная копия .env: $b"
}

# ── Контейнер ───────────────────────────────────────────────────────────────
up() {
  log "Сборка и запуск контейнера $CONTAINER"
  [ -n "$ROOT" ] && { ok "(тест) docker compose up пропущен"; return 0; }
  (cd "$APP_DIR" && "${DC[@]}" -f "$COMPOSE_FILE" up -d --build --force-recreate)
  wait_local_health || { docker logs --tail 30 "$CONTAINER" >&2 || true; die "служба не отвечает внутри контейнера (журнал выше)"; }
  ok "контейнер $CONTAINER запущен"
}

local_get() {  # local_get PATH → ответ службы изнутри контейнера
  docker exec "$CONTAINER" wget -qO- "http://127.0.0.1:$PORT$BASE_PATH$1" 2>/dev/null || true
}
local_post() {
  docker exec "$CONTAINER" wget -qO- --post-data= "http://127.0.0.1:$PORT$BASE_PATH$1" 2>/dev/null || true
}
wait_local_health() {
  local _
  for _ in $(seq 1 20); do local_get /healthz | grep -q '"ok":true' && return 0; sleep 1; done
  return 1
}

print_npm_steps() {
  echo >&2
  log "Осталось открыть адрес $BASE_PATH снаружи — Nginx Proxy Manager (панель http://IP-сервера:81)"
  cat >&2 <<EOF
  Хост ogneliss.ru → Edit → вкладка Advanced: замените содержимое поля
  целиком на site/nginx-landing.conf из этого архива (в нём новый раздел
  «Сигналы для iPhone» — location $BASE_PATH/ → $CONTAINER:$PORT без журнала
  запросов). Сначала скопируйте прежнее содержимое — чтобы вернуть при ошибке.
  Save. Затем: sudo bash $0 check
EOF
}

# ── Команды ─────────────────────────────────────────────────────────────────
cmd_install() {
  need_root; check_sources; check_key
  if [ -z "$ROOT" ]; then have docker || die "Docker не найден"; fi
  [ -n "$ROOT" ] && DC_V2=1 || compose_cmd
  resolve_base_url
  local first=1
  [ -f "$ENV_FILE" ] && first=0
  log "push-relay $SCRIPT_VERSION → $APP_DIR (адрес $BASE_URL)"
  if [ -z "$ROOT" ]; then
    detect_network
    docker network inspect "$NPM_NETWORK" >/dev/null 2>&1 \
      || die "сеть Docker «$NPM_NETWORK» не найдена. Укажите сеть Nginx Proxy Manager: --network ИМЯ (docker network ls)"
  else
    NPM_NETWORK="${NPM_NETWORK:-mailserver_default}"
  fi
  ok "сеть Nginx Proxy Manager: $NPM_NETWORK"
  [ "$first" = 1 ] || backup_env
  copy_code
  prepare_env
  put_key
  up
  key_summary
  [ "$first" = 1 ] && print_npm_steps
  return 0
}

cmd_key() {
  need_root
  [ -f "$ENV_FILE" ] || die "служба не установлена: sudo bash $0 install --team … --key …"
  [ -n "$KEY_SRC" ] || [ -n "$TEAM_ARG" ] || die "укажите --key AuthKey_<KEYID>.p8 и/или --team TEAMID"
  check_key
  [ -n "$ROOT" ] && DC_V2=1 || compose_cmd
  resolve_base_url
  backup_env
  if [ -n "$TEAM_ARG" ]; then env_set APNS_TEAM_ID "$TEAM_ARG" "$ENV_FILE"; ok "Team ID: $TEAM_ARG"; fi
  put_key
  up
  key_summary
}

cmd_remove() {
  need_root
  [ -f "$APP_DIR/$COMPOSE_FILE" ] || die "нет $APP_DIR/$COMPOSE_FILE — служба не установлена"
  compose_cmd
  (cd "$APP_DIR" && "${DC[@]}" -f "$COMPOSE_FILE" down)
  ok "контейнер $CONTAINER удалён; каталог $APP_DIR (ключ, .env, токены) оставлен"
  warn "уберите и раздел «Сигналы для iPhone» из Advanced хоста в NPM, иначе $BASE_PATH отвечает 502"
}

key_summary() {
  [ -n "$ROOT" ] && return 0
  local h keys
  h="$(local_get /healthz)"; keys="$(json_obj "$h" keys)"
  if [ "$(json_val "$keys" team)" != true ]; then
    warn "нет Team ID — сигналы не отправляются. sudo bash $0 key --team TEAMID"
  elif [ "$(json_val "$keys" production)" != true ]; then
    warn "нет ключа APNs — регистрации принимаются, сигналы не отправляются."
    warn "  sudo bash $0 key --key /путь/AuthKey_<KEYID>.p8"
  else
    probe_report || true
  fi
}

# Пробный сигнал Apple на несуществующий токен (POST /probe внутри контейнера).
probe_report() {
  local r env part status reason fails=0
  r="$(local_post /probe)"
  [ -n "$r" ] || { bad "пробный сигнал: служба не ответила"; return 1; }
  for env in production sandbox; do
    part="$(json_obj "$r" "$env")"
    if [ "$(json_val "$part" ready)" != true ]; then
      [ "$env" = production ] && { bad "ключ Production не задан"; fails=$((fails + 1)); }
      continue
    fi
    status="$(json_val "$part" status)"; reason="$(json_val "$part" reason)"
    if [ "$(json_val "$part" keyOk)" = true ]; then
      ok "ключ $env принят Apple (пробный токен, как и ожидалось, отклонён: $reason)"
      continue
    fi
    fails=$((fails + 1))
    case "$reason" in
      InvalidProviderToken) bad "$env: Apple не принимает ключ — неверны Key ID, Team ID или ключ отозван (403 $reason)" ;;
      ExpiredProviderToken) bad "$env: Apple считает подпись просроченной — часы сервера расходятся (сейчас $(date -u +%FT%TZ)); проверьте timedatectl" ;;
      TopicDisallowed|DeviceTokenNotForTopic|BadTopic|MissingTopic)
        bad "$env: ключ не для Bundle ID приложения ($reason) — APNS_TOPIC или ограничения ключа" ;;
      *) if [ "${status:-0}" = 0 ]; then bad "$env: нет связи с Apple (${reason:-нет ответа}) — исходящий HTTPS из Docker к api.push.apple.com"
         else bad "$env: ответ Apple $status ${reason:-}"; fi ;;
    esac
  done
  [ "$fails" = 0 ]
}

cmd_check() {
  need_root
  [ -f "$ENV_FILE" ] || die "нет $ENV_FILE — служба не установлена (sudo bash $0 install)"
  resolve_base_url
  detect_network
  local fails=0 h keys tok code body
  log "Проверка push-relay: $BASE_URL"
  if docker ps --filter "name=^$CONTAINER\$" --format '{{.Status}}' 2>/dev/null | grep -q .; then
    ok "контейнер $CONTAINER: $(docker ps --filter "name=^$CONTAINER\$" --format '{{.Status}}')"
  else
    bad "контейнер $CONTAINER не запущен: cd $APP_DIR && docker compose -f $COMPOSE_FILE up -d"
    return 1
  fi
  h="$(local_get /healthz)"
  if printf '%s' "$h" | grep -q '"ok":true'; then
    tok="$(json_obj "$h" tokens)"; keys="$(json_obj "$h" keys)"
    ok "служба отвечает: установок $(json_val "$tok" total) (production $(json_val "$tok" production), sandbox $(json_val "$tok" sandbox)); сигналов отправлено $(json_val "$h" sent), ошибок $(json_val "$h" failed), токенов удалено $(json_val "$h" removed)"
    local le; le="$(json_val "$h" lastError)"
    [ -n "$le" ] && [ "$le" != null ] && warn "последняя ошибка отправки: $le"
    [ "$(json_val "$h" apiKey)" = true ] && ok "ключ приложения (x-api-key) задан" || warn "PUSH_API_KEY пуст — регистрация без ключа приложения"
    if [ "$(json_val "$keys" team)" != true ]; then bad "нет APNS_TEAM_ID: sudo bash $0 key --team TEAMID"; fails=$((fails + 1))
    elif [ "$(json_val "$keys" production)" != true ]; then bad "нет ключа APNs: sudo bash $0 key --key AuthKey_<KEYID>.p8"; fails=$((fails + 1))
    else probe_report || fails=$((fails + 1)); fi
  else
    bad "служба не отвечает внутри контейнера"; docker logs --tail 20 "$CONTAINER" >&2 || true
    fails=$((fails + 1))
  fi

  body="$(curl -sS --max-time 10 "$BASE_URL/healthz" 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q '"ok":true'; then
    ok "снаружи отвечает: $BASE_URL/healthz"
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST -H 'Content-Type: application/json' --data '{}' "$BASE_URL/register" 2>/dev/null || true)"
    case "$code" in
      401) ok "регистрация без ключа приложения → 401 (как и должно быть)" ;;
      400) ok "регистрация отвечает (400 на пустой запрос)" ;;
      *) bad "POST $BASE_PATH/register → $code (ожидалось 401)"; fails=$((fails + 1)) ;;
    esac
  else
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE_URL/healthz" 2>/dev/null || true)"
    bad "снаружи не отвечает: $BASE_URL/healthz (HTTP ${code:-нет связи})"
    case "$code" in
      301|302|404) warn "запрос ушёл в правила сайта — в Advanced хоста $BASE_HOST нет раздела location $BASE_PATH/ (вставьте site/nginx-landing.conf)" ;;
      502|503|504) warn "NPM не достучался до $CONTAINER:$PORT — контейнер не в сети NPM ($NPM_NETWORK)? docker network connect" ;;
      000|'') warn "нет связи с $BASE_HOST: DNS или сертификат" ;;
    esac
    fails=$((fails + 1))
  fi
  echo >&2
  if [ "$fails" = 0 ]; then log "${C_G}Всё в порядке.${C_0} На iPhone: Настройки → Уведомления → Сигналы сервера (iPhone)"
  else log "${C_R}Проблем: $fails${C_0} (подробно — README.md, раздел «Если не работает»)"; return 1; fi
}

main() {
  parse_args "$@"
  case "$CMD" in
    help) usage ;;
    install|update) cmd_install ;;
    key) cmd_key ;;
    check) cmd_check || exit 1 ;;
    remove) resolve_base_url; cmd_remove ;;
  esac
}

main "$@"
