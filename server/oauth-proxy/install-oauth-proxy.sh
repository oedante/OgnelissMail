#!/usr/bin/env bash
# =============================================================================
#  Ogneliss Mail — установка, обновление и проверка OAuth-прокси
#  Debian 11 / 12 / 13 (и Ubuntu 22.04+). Запуск от root.
#
#  Два варианта размещения (выбирается автоматически, см. --mode):
#    docker — рядом с почтовым сервером в Docker за Nginx Proxy Manager
#             (/opt/mailserver). Так прокси работает сейчас на ogneliss.ru.
#    native — чистый сервер: Node.js + systemd + nginx + сертификат
#             Let's Encrypt (или свой, например GlobalSign).
#
#  Команды:
#    install   первая установка (по умолчанию)
#    update    обновить код прокси из этого архива, секреты не трогать
#    check     проверить, что прокси работает и доступен снаружи
#    key       вывести OAUTH_PROXY_URL и OAUTH_PROXY_KEY для сборки приложения
#
#  Примеры:
#    sudo bash install-oauth-proxy.sh install --base-url https://www.ogneliss.ru/oauth
#    sudo bash install-oauth-proxy.sh update
#    sudo bash install-oauth-proxy.sh check
#    sudo bash install-oauth-proxy.sh key
#
#  Инструкция: docs/guides/OAUTH_PROXY_DEBIAN.md
#
#  Секреты:
#    ENC_SECRET, PROXY_API_KEY и STATE_SECRET создаются один раз и при
#    обновлении не меняются. Смена ENC_SECRET выкидывает из OAuth-аккаунтов
#    всех пользователей; смена PROXY_API_KEY требует пересобрать приложение.
#    Значения секретов скрипт на экран не выводит (кроме команды key).
# =============================================================================
set -Eeuo pipefail
umask 077

SCRIPT_VERSION="2026.10.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Префикс файловой системы — только для автотестов скрипта. Не задавайте его.
ROOT="${OG_ROOT:-}"

# ── Параметры (флаги перекрывают переменные окружения) ──────────────────────
CMD=""
MODE="${MODE:-auto}"
BASE_URL_ARG="${BASE_URL:-}"
TLS_MODE="${TLS_MODE:-}"
LE_EMAIL="${LE_EMAIL:-}"
CERT_FILE="${CERT_FILE:-}"
CERT_KEY_FILE="${CERT_KEY_FILE:-}"
SECRETS_FILE="${SECRETS_FILE:-}"
MAIL_DIR="${MAIL_DIR:-/opt/mailserver}"
NPM_NETWORK="${NPM_NETWORK:-}"
PORT_GIVEN=0; [ -n "${PROXY_PORT:-}" ] && PORT_GIVEN=1
PROXY_PORT="${PROXY_PORT:-8787}"
NODE_MAJOR="${NODE_MAJOR:-24}"
ASSUME_YES="${ASSUME_YES:-0}"
FORCE_OS=0

# Пути варианта native
N_APP_DIR="$ROOT/opt/ogneliss-oauth-proxy"
N_ETC_DIR="$ROOT/etc/ogneliss-oauth-proxy"
N_ENV_FILE="$N_ETC_DIR/oauth-proxy.env"
N_STATE_DIR="/var/lib/ogneliss-oauth-proxy"
N_SERVICE="ogneliss-oauth-proxy"
N_USER="ogneliss-oauth"
N_UNIT_FILE="$ROOT/etc/systemd/system/$N_SERVICE.service"
NGX_SITE="$ROOT/etc/nginx/sites-available/ogneliss-oauth-proxy.conf"
NGX_SITE_LINK="$ROOT/etc/nginx/sites-enabled/ogneliss-oauth-proxy.conf"
NGX_SNIPPET="$ROOT/etc/nginx/snippets/ogneliss-oauth-proxy.conf"
NGX_LOGFMT="$ROOT/etc/nginx/conf.d/ogneliss-oauth-logformat.conf"

# Ключи, которые скрипт никогда не меняет в существующем .env
PROTECTED_KEYS="ENC_SECRET PROXY_API_KEY STATE_SECRET"
# Ключи, которые можно подгрузить из файла --secrets
SECRET_KEY_RE='^(GOOGLE|MS|YANDEX|MAILRU|YAHOO)_(CLIENT_ID|CLIENT_SECRET|APP_ID|SCOPE)$'
APP_REDIRECT="com.ogneliss.mail://oauth"
DEFAULT_REDIRECTS="com.ogneliss.mail://oauth,com.ogneliss.mail:/oauth2redirect"

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
  sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  cat <<'EOF'
Флаги:
  --mode auto|docker|native   где ставить прокси (auto: docker, если есть
                              /opt/mailserver или контейнер proxy-manager)
  --base-url URL              внешний адрес прокси:
                                https://www.ogneliss.ru/oauth  (путь на домене)
                                https://oauth.ogneliss.ru      (свой поддомен)
  --tls letsencrypt|existing|none
                              (native) откуда сертификат; по умолчанию
                              letsencrypt
  --email ADDR                (native, letsencrypt) почта для Let's Encrypt
  --cert FILE --cert-key FILE (native, existing) свой сертификат и ключ
  --secrets FILE              подгрузить client_id/client_secret провайдеров
                              из файла KEY=VALUE (ENC_SECRET, PROXY_API_KEY,
                              STATE_SECRET из файла не берутся)
  --mail-dir DIR              (docker) каталог почтового сервера,
                              по умолчанию /opt/mailserver
  --network NAME              (docker) сеть Nginx Proxy Manager
  --port N                    локальный порт прокси, по умолчанию 8787
  --node N                    (native) версия Node.js, по умолчанию 24
  --yes                       не задавать вопросов
  --force-os                  не проверять дистрибутив
EOF
}

# ── Разбор аргументов ───────────────────────────────────────────────────────
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      install|update|check|key|help) CMD="$1" ;;
      -h|--help) CMD=help ;;
      --mode) MODE="${2:?}"; shift ;;
      --base-url) BASE_URL_ARG="${2:?}"; shift ;;
      --tls) TLS_MODE="${2:?}"; shift ;;
      --email) LE_EMAIL="${2:?}"; shift ;;
      --cert) CERT_FILE="${2:?}"; shift ;;
      --cert-key) CERT_KEY_FILE="${2:?}"; shift ;;
      --secrets) SECRETS_FILE="${2:?}"; shift ;;
      --mail-dir) MAIL_DIR="${2:?}"; shift ;;
      --network) NPM_NETWORK="${2:?}"; shift ;;
      --port) PROXY_PORT="${2:?}"; PORT_GIVEN=1; shift ;;
      --node) NODE_MAJOR="${2:?}"; shift ;;
      -y|--yes) ASSUME_YES=1 ;;
      --force-os) FORCE_OS=1 ;;
      *) die "неизвестный параметр: $1 (см. --help)" ;;
    esac
    shift
  done
  [ -n "$CMD" ] || CMD=install
  case "$MODE" in auto|docker|native) ;; *) die "--mode: auto, docker или native" ;; esac
  case "${TLS_MODE:-letsencrypt}" in letsencrypt|existing|none) ;; *) die "--tls: letsencrypt, existing или none" ;; esac
  [[ "$PROXY_PORT" =~ ^[0-9]{2,5}$ ]] || die "--port: число"
  [[ "$NODE_MAJOR" =~ ^[0-9]{2}$ ]] || die "--node: номер версии, например 24"
}

# ── Утилиты ─────────────────────────────────────────────────────────────────
need_root() { [ -n "$ROOT" ] || [ "$(id -u)" -eq 0 ] || die "запустите от root: sudo bash $0 ${CMD}"; }
have() { command -v "$1" >/dev/null 2>&1; }
gen_secret() {
  if have openssl; then openssl rand -hex 32
  else head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; fi
}
confirm() {  # confirm "вопрос" → 0 да / 1 нет
  [ "$ASSUME_YES" = 1 ] && return 0
  [ -t 0 ] || return 0
  local a; read -r -p "$1 [Y/n] " a || true
  case "${a:-y}" in y|Y|д|Д|yes|да) return 0 ;; *) return 1 ;; esac
}
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
env_set() {  # env_set KEY VALUE FILE — заменить или дописать, права файла сохраняются
  local tmp; tmp="$(mktemp "$3.XXXXXX")"
  K="$1" V="$2" awk '
    index($0, ENVIRON["K"] "=") == 1 { if (!done) { print ENVIRON["K"] "=" ENVIRON["V"]; done = 1 }; next }
    { print }
    END { if (!done) print ENVIRON["K"] "=" ENVIRON["V"] }' "$3" > "$tmp"
  chmod --reference="$3" "$tmp" 2>/dev/null || true
  chown --reference="$3" "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$3"
}
env_add_missing() { env_has "$1" "$3" || { env_set "$1" "$2" "$3"; ok "добавлено в .env: $1"; }; }
is_protected() { case " $PROTECTED_KEYS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ── Адрес прокси ────────────────────────────────────────────────────────────
parse_base_url() {  # задаёт BASE_URL, BASE_HOST, BASE_PATH, CALLBACK_URL
  BASE_URL="${1%/}"
  if [[ "$BASE_URL" =~ ^https://([A-Za-z0-9.-]+)(/[A-Za-z0-9/_-]*)?$ ]]; then
    BASE_HOST="${BASH_REMATCH[1]}"; BASE_PATH="${BASH_REMATCH[2]:-}"
  elif [[ "$BASE_URL" =~ ^http://(127\.0\.0\.1|localhost)(:[0-9]+)?(/[A-Za-z0-9/_-]*)?$ ]]; then
    # Только для проверки на этом же сервере.
    BASE_HOST="${BASH_REMATCH[1]}"; BASE_PATH="${BASH_REMATCH[3]:-}"
  else
    die "адрес прокси должен быть вида https://домен или https://домен/путь, получено: $1"
  fi
  BASE_PATH="${BASE_PATH%/}"
  if [ -n "$BASE_PATH" ]; then CALLBACK_URL="$BASE_URL/callback"; else CALLBACK_URL="$BASE_URL/oauth/callback"; fi
}

# ── Дистрибутив ─────────────────────────────────────────────────────────────
check_os() {
  [ -n "$ROOT" ] && return 0
  [ -r /etc/os-release ] || die "не найден /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    debian)
      case "${VERSION_ID:-}" in
        11) warn "Debian 11 (bullseye): бесплатная поддержка (LTS) закончилась 31.08.2026."
            warn "Прокси работает, но обновлений безопасности ОС больше нет — планируйте переход на Debian 12." ;;
        12|13) ok "Debian ${VERSION_ID}" ;;
        *) [ "$FORCE_OS" = 1 ] || die "Debian ${VERSION_ID:-?} не проверялся (поддерживаются 11–13; --force-os — без проверки)" ;;
      esac ;;
    ubuntu) ok "Ubuntu ${VERSION_ID:-}" ;;
    *) [ "$FORCE_OS" = 1 ] || die "скрипт рассчитан на Debian/Ubuntu (обнаружено: ${ID:-?}); --force-os — без проверки" ;;
  esac
}

# ── Выбор варианта ──────────────────────────────────────────────────────────
docker_npm_present() {
  have docker || return 1
  docker inspect proxy-manager >/dev/null 2>&1 && return 0
  return 1
}
detect_mode() {
  if [ "$MODE" = auto ]; then
    if [ -f "$ROOT$MAIL_DIR/oauth-proxy/.env" ] || [ -d "$ROOT$MAIL_DIR" ] || docker_npm_present; then
      MODE=docker
    else
      MODE=native
    fi
  fi
  if [ "$MODE" = docker ]; then
    APP_DIR="$ROOT$MAIL_DIR/oauth-proxy"; ENV_FILE="$APP_DIR/.env"
  else
    APP_DIR="$N_APP_DIR"; ENV_FILE="$N_ENV_FILE"
  fi
}

resolve_base_url() {
  local url="$BASE_URL_ARG"
  [ -n "$url" ] || url="$(env_get BASE_URL "$ENV_FILE")"
  if [ -z "$url" ]; then
    [ "$CMD" = install ] || die "не найден BASE_URL в $ENV_FILE — укажите --base-url"
    if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then die "укажите --base-url (например https://www.ogneliss.ru/oauth)"; fi
    echo "Внешний адрес прокси. Два варианта:" >&2
    echo "  https://www.ogneliss.ru/oauth — путь на сайте, годится существующий сертификат www" >&2
    echo "  https://oauth.ogneliss.ru     — свой поддомен, нужна DNS-запись и сертификат на него" >&2
    url="$(ask "Адрес" "https://www.ogneliss.ru/oauth")"
  fi
  parse_base_url "$url"
}

# ── Файлы прокси из архива ──────────────────────────────────────────────────
check_sources() {
  local f
  for f in server.js package.json package-lock.json; do
    [ -f "$SCRIPT_DIR/$f" ] || die "нет $SCRIPT_DIR/$f — копируйте на сервер всю папку server/oauth-proxy, а не только скрипт"
  done
  grep -q "router.post('/exchange'" "$SCRIPT_DIR/server.js" \
    || die "$SCRIPT_DIR/server.js — старая версия (нет /exchange). Возьмите папку из свежего архива."
}

backup_dir() {
  BACKUP_DIR="$APP_DIR/backup-$(date +%Y%m%d-%H%M%S)"
  install -d -m 700 "$BACKUP_DIR"
  local f
  for f in server.js package.json package-lock.json Dockerfile docker-compose.oauth.yml .env; do
    [ -f "$APP_DIR/$f" ] && cp -p "$APP_DIR/$f" "$BACKUP_DIR/"
  done
  if [ "$MODE" = native ] && [ -f "$ENV_FILE" ]; then cp -p "$ENV_FILE" "$BACKUP_DIR/oauth-proxy.env"; fi
  ok "резервная копия: $BACKUP_DIR"
}

# ── .env ────────────────────────────────────────────────────────────────────
write_new_env() {
  local f="$1"
  [ -d "$(dirname "$f")" ] || install -d -m 750 "$(dirname "$f")"
  : > "$f"; chmod 600 "$f"
  cat > "$f" <<EOF
# Ogneliss OAuth-прокси. Создано install-oauth-proxy.sh $(date +%F).
# Права 600. В git и в почту не отправлять.
BASE_URL=$BASE_URL
PORT=$PROXY_PORT
# Ключ приложения (заголовок x-api-key). Совпадает с OAUTH_PROXY_KEY в сборке.
PROXY_API_KEY=$(gen_secret)
# Подпись state. Не менять без необходимости.
STATE_SECRET=$(gen_secret)
# Шифрование refresh-токенов. Смена = все пользователи OAuth входят заново.
ENC_SECRET=$(gen_secret)
ALLOWED_REDIRECTS=$DEFAULT_REDIRECTS
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_SCOPE=https://mail.google.com/ https://www.googleapis.com/auth/gmail.settings.basic https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/carddav openid email profile
MS_CLIENT_ID=
MS_CLIENT_SECRET=
MS_SCOPE=https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access openid email profile
YANDEX_CLIENT_ID=
YANDEX_CLIENT_SECRET=
YANDEX_SCOPE=mail:imap_full mail:smtp calendar:all addressbook:all login:email login:info
MAILRU_CLIENT_ID=
MAILRU_CLIENT_SECRET=
MAILRU_SCOPE=openid email profile mail.imap offline_access
YAHOO_APP_ID=
YAHOO_CLIENT_ID=
YAHOO_CLIENT_SECRET=
YAHOO_SCOPE=openid email profile mail-w
EOF
  if [ "$MODE" = native ]; then
    printf 'STORE_PATH=%s/store.json\n' "$N_STATE_DIR" >> "$f"
  fi
  ok "создан $f с новыми секретами"
}

update_env() {
  local f="$ENV_FILE" old v state_regenerated=0
  old="$(env_get BASE_URL "$f")"
  if [ "$old" != "$BASE_URL" ]; then
    env_set BASE_URL "$BASE_URL" "$f"
    warn "BASE_URL изменён: ${old:-<нет>} → $BASE_URL"
    warn "поменяйте redirect_uri в консолях провайдеров на $CALLBACK_URL и пересоберите приложение"
  fi
  env_add_missing PORT "$PROXY_PORT" "$f"

  # Секреты — только если их нет вовсе (иначе сервер не запустится).
  v="$(env_get STATE_SECRET "$f")"
  if [ "${#v}" -lt 16 ]; then
    env_set STATE_SECRET "$(gen_secret)" "$f"; state_regenerated=1
    warn "STATE_SECRET не было — создан (незавершённые входы придётся повторить)"
  fi
  v="$(env_get PROXY_API_KEY "$f")"
  if [ "${#v}" -lt 16 ]; then
    env_set PROXY_API_KEY "$(gen_secret)" "$f"
    warn "PROXY_API_KEY не было — создан. Приложение нужно собрать с новым ключом (команда key)."
  fi
  if [ -z "$(env_get ENC_SECRET "$f")" ]; then
    if [ "$state_regenerated" = 1 ]; then
      env_set ENC_SECRET "$(gen_secret)" "$f"
      ok "ENC_SECRET создан"
    else
      # Без ENC_SECRET ключ шифрования берётся из STATE_SECRET. Если добавить его
      # сейчас, все сохранённые в приложениях refresh-токены станут недействительны.
      warn "ENC_SECRET не задан — ключ шифрования берётся из STATE_SECRET; оставляю как есть,"
      warn "иначе всем пользователям OAuth придётся войти заново"
    fi
  fi

  env_add_missing ALLOWED_REDIRECTS "$DEFAULT_REDIRECTS" "$f"
  v="$(env_get ALLOWED_REDIRECTS "$f")"
  case ",$v," in
    *",$APP_REDIRECT,"*) ;;
    *) env_set ALLOWED_REDIRECTS "${v:+$v,}$APP_REDIRECT" "$f"; ok "в ALLOWED_REDIRECTS добавлен $APP_REDIRECT" ;;
  esac
  env_add_missing GOOGLE_SCOPE "https://mail.google.com/ https://www.googleapis.com/auth/gmail.settings.basic https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/carddav openid email profile" "$f"
  env_add_missing MS_SCOPE "https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access openid email profile" "$f"
  env_add_missing YANDEX_SCOPE "mail:imap_full mail:smtp calendar:all addressbook:all login:email login:info" "$f"
  env_add_missing MAILRU_SCOPE "openid email profile mail.imap offline_access" "$f"
  # Mail.ru (документация OAuth Mail, 2025): openid обязателен, refresh_token —
  # только с offline_access. Прежний набор «userinfo mail.imap» заменяем.
  if [ "$(env_get MAILRU_SCOPE "$f")" = "userinfo mail.imap" ]; then
    env_set MAILRU_SCOPE "openid email profile mail.imap offline_access" "$f"; ok "MAILRU_SCOPE обновлён: openid email profile mail.imap offline_access"
  fi
  env_add_missing YAHOO_SCOPE "openid email profile mail-w" "$f"
  if [ "$MODE" = native ]; then env_add_missing STORE_PATH "$N_STATE_DIR/store.json" "$f"; fi
  # Старые установки: в GOOGLE_SCOPE нет календаря и контактов — дописываем
  # (CalDAV/CardDAV Gmail отвечали 403). Пользователям Google нужно войти заново.
  v="$(env_get GOOGLE_SCOPE "$f")"
  for sc in https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/carddav profile; do
    case " $v " in
      *" $sc "*) ;;
      *) v="$v $sc"; env_set GOOGLE_SCOPE "$v" "$f"; ok "в GOOGLE_SCOPE добавлен $sc" ;;
    esac
  done
  # Яндекс: календарь и контакты по CalDAV/CardDAV. Права calendar:all и
  # addressbook:all нужно отметить и в приложении на oauth.yandex.ru, иначе
  # Яндекс ответит invalid_scope при входе.
  v="$(env_get YANDEX_SCOPE "$f")"
  for sc in calendar:all addressbook:all; do
    case " $v " in
      *" $sc "*) ;;
      *) v="$v $sc"; env_set YANDEX_SCOPE "$v" "$f"; ok "в YANDEX_SCOPE добавлен $sc (отметьте право в приложении Яндекса)" ;;
    esac
  done
  # Яндекс: адрес и имя владельца (ящики Яндекс 360 на своём домене).
  v="$(env_get YANDEX_SCOPE "$f")"
  for sc in login:email login:info; do
    case " $v " in
      *" $sc "*) ;;
      *) v="$v $sc"; env_set YANDEX_SCOPE "$v" "$f"; ok "в YANDEX_SCOPE добавлен $sc (отметьте право в приложении Яндекса)" ;;
    esac
  done
  # Yahoo: без mail-w IMAP/SMTP не принимают токен (прежнее значение «openid email»).
  v="$(env_get YAHOO_SCOPE "$f")"
  case " $v " in
    *" mail-w "*|*" mail-r "*) ;;
    *) env_set YAHOO_SCOPE "$v mail-w" "$f"; ok "в YAHOO_SCOPE добавлен mail-w (права Mail в Yahoo Developer)" ;;
  esac
  # Microsoft: прежний установщик записывал права EWS, а Outlook.com и
  # Office 365 в приложении работают по IMAP/SMTP — вход проходил, почта нет.
  v="$(env_get MS_SCOPE "$f")"
  case "$v" in
    *IMAP.AccessAsUser.All*) ;;
    *EWS.AccessAsUser.All*)
      env_set MS_SCOPE "https://outlook.office.com/IMAP.AccessAsUser.All https://outlook.office.com/SMTP.Send offline_access openid email profile" "$f"
      warn "MS_SCOPE: права EWS заменены на IMAP/SMTP (в Entra: IMAP.AccessAsUser.All и SMTP.Send)" ;;
  esac
  case "$(env_get YANDEX_SCOPE "$f")" in
    *mail:smtp*) ;;
    *) warn "в YANDEX_SCOPE нет mail:smtp — отправка писем через Яндекс работать не будет" ;;
  esac
}

apply_secrets_file() {
  [ -n "$SECRETS_FILE" ] || return 0
  [ -f "$SECRETS_FILE" ] || die "нет файла $SECRETS_FILE"
  log "Подгружаю client_id/client_secret из $SECRETS_FILE"
  local line key val n=0 skipped=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    key="${line%%=*}"; val="${line#*=}"
    # Кавычки вокруг значения убираем: env_file в Docker воспринял бы их буквально.
    case "$val" in \"*\") val="${val:1:${#val}-2}" ;; \'*\') val="${val:1:${#val}-2}" ;; esac
    if is_protected "$key"; then
      warn "$key из файла пропущен: этот секрет скрипт не меняет"; skipped=$((skipped + 1)); continue
    fi
    if ! [[ "$key" =~ $SECRET_KEY_RE ]]; then
      warn "$key пропущен (не похож на параметр провайдера)"; skipped=$((skipped + 1)); continue
    fi
    env_set "$key" "$val" "$ENV_FILE"; n=$((n + 1))
  done < "$SECRETS_FILE"
  ok "применено параметров: $n, пропущено: $skipped (значения не показываются)"
  warn "удалите исходный файл с секретами: shred -u $SECRETS_FILE"
}

provider_status() {
  local p id sec name
  for p in GOOGLE:Google MS:Microsoft YANDEX:Яндекс MAILRU:Mail.ru YAHOO:Yahoo; do
    id="$(env_get "${p%%:*}_CLIENT_ID" "$ENV_FILE")"
    sec="$(env_get "${p%%:*}_CLIENT_SECRET" "$ENV_FILE")"
    name="${p#*:}"
    if [ -n "$id" ] && [ -n "$sec" ]; then ok "$name: настроен"
    elif [ -n "$id" ]; then warn "$name: есть client_id, нет client_secret"
    else printf '  - %s: не настроен\n' "$name" >&2; fi
  done
}

# ── Вариант docker (рядом с почтой, за Nginx Proxy Manager) ─────────────────
compose_cmd() {
  if docker compose version >/dev/null 2>&1; then DC=(docker compose)
  elif have docker-compose; then DC=(docker-compose)
  else die "нет docker compose / docker-compose"; fi
}

docker_install() {
  have docker || die "Docker не найден. Для сервера без Docker: --mode native"
  compose_cmd
  if [ -z "$NPM_NETWORK" ]; then
    NPM_NETWORK="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' proxy-manager 2>/dev/null | awk '{print $1}')" || true
  fi
  [ -n "$NPM_NETWORK" ] || NPM_NETWORK="mailserver_default"
  docker network inspect "$NPM_NETWORK" >/dev/null 2>&1 \
    || die "сеть Docker «$NPM_NETWORK» не найдена. Укажите сеть Nginx Proxy Manager: --network ИМЯ (docker network ls)"
  ok "сеть Nginx Proxy Manager: $NPM_NETWORK"

  install -d -m 750 "$APP_DIR"
  local first=1
  [ -f "$ENV_FILE" ] && first=0
  [ "$first" = 1 ] || backup_dir

  install -m 644 "$SCRIPT_DIR/server.js" "$SCRIPT_DIR/package.json" "$SCRIPT_DIR/package-lock.json" "$APP_DIR/"
  install -m 644 "$SCRIPT_DIR/Dockerfile" "$APP_DIR/Dockerfile"
  printf '.env\n*.env\nbackup-*\nnode_modules\n' > "$APP_DIR/.dockerignore"; chmod 644 "$APP_DIR/.dockerignore"

  cat > "$APP_DIR/docker-compose.oauth.yml" <<EOF
# Создано install-oauth-proxy.sh. Контейнер в сети Nginx Proxy Manager.
version: "2.1"
services:
  oauth-proxy:
    build: .
    image: ogneliss/oauth-proxy:latest
    container_name: oauth-proxy
    env_file:
      - ./.env
    environment:
      - HOST=0.0.0.0
      - PORT=$PROXY_PORT
    expose:
      - "$PROXY_PORT"
    restart: always
    read_only: true
    tmpfs:
      - /tmp
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:$PROXY_PORT$BASE_PATH/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - npm
networks:
  npm:
    external:
      name: $NPM_NETWORK
EOF
  chmod 644 "$APP_DIR/docker-compose.oauth.yml"

  if [ "$first" = 1 ]; then write_new_env "$ENV_FILE"; else update_env; fi
  apply_secrets_file
  chmod 600 "$ENV_FILE"

  log "Сборка и запуск контейнера"
  # Без --remove-orphans: имя проекта compose берётся из имени папки
  # («oauth-proxy»), и если на сервере есть другой стек из папки с тем же
  # именем (например, старый /opt/oauth-proxy), его контейнеры были бы
  # удалены как «сироты».
  (cd "$APP_DIR" && "${DC[@]}" -f docker-compose.oauth.yml up -d --build)
  wait_local_health || { docker logs --tail 30 oauth-proxy >&2 || true; die "прокси не отвечает внутри контейнера (журнал выше)"; }
  ok "контейнер oauth-proxy запущен"
  [ "$first" = 1 ] && print_npm_steps
  return 0
}

print_npm_steps() {
  echo >&2
  log "Настройте Nginx Proxy Manager (панель http://IP-сервера:81)"
  if [ -n "$BASE_PATH" ]; then
    cat >&2 <<EOF
  1. Hosts → Proxy Hosts → откройте хост $BASE_HOST (сертификат на него уже есть).
  2. Вкладка Custom locations → Add location:
       Define location:  $BASE_PATH
       Scheme: http   Forward Hostname: oauth-proxy   Forward Port: $PROXY_PORT
  3. Save. Затем: sudo bash $0 check
EOF
  else
    cat >&2 <<EOF
  1. DNS: A-запись $BASE_HOST → IP этого сервера.
  2. Hosts → Proxy Hosts → Add Proxy Host:
       Domain Names: $BASE_HOST
       Scheme: http   Forward Hostname: oauth-proxy   Forward Port: $PROXY_PORT
       [x] Block Common Exploits
  3. Вкладка SSL: Request a new SSL Certificate (Let's Encrypt), Force SSL, HTTP/2.
  4. Save. Затем: sudo bash $0 check
EOF
  fi
}

# ── Вариант native (systemd + nginx) ────────────────────────────────────────
node_major() { if have node; then node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0; else echo 0; fi; }

install_node() {
  local cur np; cur="$(node_major)"; np="$(command -v node 2>/dev/null || true)"
  # Подходит только системный Node 18+ с npm. Node из Debian 12 (18) ставится без
  # npm; Node из nvm лежит в /root или /home — служба его не увидит (ProtectHome).
  if [ "$cur" -ge 18 ] && have npm && case "$np" in /root/*|/home/*) false ;; *) true ;; esac; then
    ok "Node.js $(node -v) уже установлен ($np)"; return 0
  fi
  log "Установка Node.js $NODE_MAJOR (репозиторий NodeSource)"
  # В Debian 11 из коробки Node.js 12 — для прокси нужен 18+ (встроенный fetch).
  install -d -m 755 "$ROOT/etc/apt/keyrings" "$ROOT/etc/apt/sources.list.d" "$ROOT/etc/apt/preferences.d"
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor --yes -o "$ROOT/etc/apt/keyrings/nodesource.gpg"
  chmod 644 "$ROOT/etc/apt/keyrings/nodesource.gpg"
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    > "$ROOT/etc/apt/sources.list.d/nodesource.list"
  chmod 644 "$ROOT/etc/apt/sources.list.d/nodesource.list"
  printf 'Package: nodejs\nPin: origin deb.nodesource.com\nPin-Priority: 600\n' > "$ROOT/etc/apt/preferences.d/nodejs"
  chmod 644 "$ROOT/etc/apt/preferences.d/nodejs"
  apt-get update -q
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q nodejs
  [ "$(node_major)" -ge 18 ] || die "не удалось установить Node.js 18+"
  ok "Node.js $(node -v)"
}

check_ports_free() {
  # 80/443 занимает кто-то кроме nginx (например, docker-proxy от NPM) — тогда native не подходит.
  have ss || return 0
  local who
  who="$(ss -ltnpH '( sport = :80 or sport = :443 )' 2>/dev/null | grep -v nginx || true)"
  if [ -n "$who" ]; then
    echo "$who" >&2
    die "порты 80/443 заняты не nginx (см. выше). Если это Nginx Proxy Manager в Docker — запустите с --mode docker"
  fi
}

ngx_host_defined() {  # есть ли в nginx уже server_name для нашего хоста (кроме нашего файла)
  local d re="${BASE_HOST//./\\.}"
  for d in "$ROOT/etc/nginx/sites-enabled" "$ROOT/etc/nginx/conf.d"; do
    [ -d "$d" ] || continue
    if grep -RlsE "server_name[^;]*[[:space:]]$re([[:space:];]|$)" "$d" 2>/dev/null \
        | grep -v "ogneliss-oauth-proxy.conf" | grep -q .; then return 0; fi
  done
  return 1
}

write_nginx_snippet() {
  install -d -m 755 "$(dirname "$NGX_SNIPPET")" "$(dirname "$NGX_LOGFMT")"
  # Журнал без строки запроса: в ней код авторизации и state.
  [ -f "$NGX_LOGFMT" ] || cat > "$NGX_LOGFMT" <<'EOF'
# Ogneliss OAuth-прокси: формат журнала без параметров запроса (там коды OAuth).
log_format ogneliss_noquery '$remote_addr - [$time_local] "$request_method $uri $server_protocol" $status $body_bytes_sent "$http_user_agent" $request_time';
EOF
  local loc="/" exact=""
  if [ -n "$BASE_PATH" ]; then loc="$BASE_PATH/"; exact="location = $BASE_PATH { return 301 $BASE_PATH/; }"; fi
  cat > "$NGX_SNIPPET" <<EOF
# Ogneliss OAuth-прокси. Подключается внутри server { } для $BASE_HOST:
#     include snippets/ogneliss-oauth-proxy.conf;
$exact
location ^~ $loc {
    proxy_pass http://127.0.0.1:$PROXY_PORT;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header Connection "";
    proxy_connect_timeout 5s;
    proxy_read_timeout 60s;
    client_max_body_size 32k;
    access_log /var/log/nginx/ogneliss-oauth.access.log ogneliss_noquery;
}
EOF
  chmod 644 "$NGX_SNIPPET" "$NGX_LOGFMT"
}

write_nginx_site() {
  local tls="${TLS_MODE:-letsencrypt}" body
  # Пакет nginx из Debian подключает sites-enabled; пакет с nginx.org — только conf.d.
  if grep -qs "sites-enabled" "$ROOT/etc/nginx/nginx.conf"; then
    install -d -m 755 "$(dirname "$NGX_SITE")" "$(dirname "$NGX_SITE_LINK")"
  else
    NGX_SITE="$ROOT/etc/nginx/conf.d/ogneliss-oauth-proxy.conf"; NGX_SITE_LINK=""
  fi
  body="    include snippets/ogneliss-oauth-proxy.conf;"
  if [ -n "$BASE_PATH" ]; then body="$body
    location / { return 404; }"; fi
  case "$tls" in
    existing)
      [ -f "$CERT_FILE" ] && [ -f "$CERT_KEY_FILE" ] || die "--tls existing требует --cert и --cert-key (файлы должны существовать)"
      cat > "$NGX_SITE" <<EOF
# Ogneliss OAuth-прокси — $BASE_HOST (свой сертификат)
server {
    listen 80;
    listen [::]:80;
    server_name $BASE_HOST;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $BASE_HOST;
    ssl_certificate     $CERT_FILE;
    ssl_certificate_key $CERT_KEY_FILE;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:ogneliss_oauth:1m;
    add_header Strict-Transport-Security "max-age=31536000" always;
    server_tokens off;
$body
}
EOF
      ;;
    letsencrypt|none)
      cat > "$NGX_SITE" <<EOF
# Ogneliss OAuth-прокси — $BASE_HOST
# HTTPS (порт 443) добавляет certbot; при --tls none TLS завершается выше по цепочке.
server {
    listen 80;
    listen [::]:80;
    server_name $BASE_HOST;
    server_tokens off;
    location ^~ /.well-known/acme-challenge/ { root /var/www/html; }
$body
}
EOF
      ;;
  esac
  chmod 644 "$NGX_SITE"
  [ -z "$NGX_SITE_LINK" ] || ln -sfn "$NGX_SITE" "$NGX_SITE_LINK"
}

native_install() {
  have apt-get || die "нет apt-get"
  if docker_npm_present; then die "на сервере работает Nginx Proxy Manager в Docker — используйте --mode docker"; fi
  local first=1
  [ -f "$ENV_FILE" ] && first=0

  if [ "$first" = 1 ]; then
    check_ports_free
    log "Пакеты"
    apt-get update -q
    local pkgs=(ca-certificates curl gnupg openssl nginx)
    [ "${TLS_MODE:-letsencrypt}" = letsencrypt ] && pkgs+=(certbot python3-certbot-nginx)
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${pkgs[@]}"
  fi
  install_node

  id "$N_USER" >/dev/null 2>&1 || useradd --system --home-dir /nonexistent --no-create-home --shell /usr/sbin/nologin "$N_USER"

  [ "$first" = 1 ] || backup_dir
  install -d -m 755 "$APP_DIR"
  install -m 644 "$SCRIPT_DIR/server.js" "$SCRIPT_DIR/package.json" "$SCRIPT_DIR/package-lock.json" "$APP_DIR/"
  log "Зависимости (npm ci)"
  # umask 022: иначе (umask 077 скрипта) node_modules читает только root,
  # и служба от ogneliss-oauth не найдёт express.
  (umask 022; cd "$APP_DIR" && npm ci --omit=dev --no-audit --no-fund --loglevel=error)
  chown -R root:root "$APP_DIR/node_modules" "$APP_DIR/server.js" "$APP_DIR/package.json" "$APP_DIR/package-lock.json"
  chmod -R go-w,a+rX "$APP_DIR/node_modules"
  chmod 755 "$APP_DIR"

  install -d -m 750 -g "$N_USER" "$N_ETC_DIR"
  if [ "$first" = 1 ]; then write_new_env "$ENV_FILE"; else update_env; fi
  apply_secrets_file
  chown root:"$N_USER" "$ENV_FILE"; chmod 640 "$ENV_FILE"

  cat > "$N_UNIT_FILE" <<EOF
[Unit]
Description=Ogneliss Mail OAuth proxy
Documentation=file://$APP_DIR/server.js
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$N_USER
Group=$N_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=$N_ENV_FILE
Environment=HOST=127.0.0.1
Environment=NODE_ENV=production
ExecStart=$(command -v node || echo /usr/bin/node) $APP_DIR/server.js
Restart=on-failure
RestartSec=5
StateDirectory=ogneliss-oauth-proxy
StateDirectoryMode=0700
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
ProtectClock=yes
RestrictNamespaces=yes
RestrictRealtime=yes
RestrictSUIDSGID=yes
LockPersonality=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=
SystemCallArchitectures=native
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$N_UNIT_FILE"
  systemctl daemon-reload
  systemctl enable "$N_SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$N_SERVICE"
  wait_local_health || { journalctl -u "$N_SERVICE" -n 30 --no-pager >&2 || true; die "служба $N_SERVICE не отвечает (журнал выше)"; }
  ok "служба $N_SERVICE работает на 127.0.0.1:$PROXY_PORT"

  write_nginx_snippet
  if ngx_host_defined; then
    warn "в nginx уже есть сайт $BASE_HOST — его файл не трогаю."
    warn "Добавьте в его блок server { } (тот, что слушает 443) строку:"
    warn "    include snippets/ogneliss-oauth-proxy.conf;"
    warn "затем: nginx -t && systemctl reload nginx && sudo bash $0 check"
  elif [ "$first" = 1 ] || { [ ! -f "$NGX_SITE" ] && [ ! -f "$ROOT/etc/nginx/conf.d/ogneliss-oauth-proxy.conf" ]; }; then
    write_nginx_site
  fi
  nginx -t >/dev/null 2>&1 || { nginx -t || true; die "ошибка в конфигурации nginx (см. выше)"; }
  systemctl reload nginx

  if [ "$first" = 1 ] && [ "${TLS_MODE:-letsencrypt}" = letsencrypt ] && [ -f "$NGX_SITE" ]; then
    log "Сертификат Let's Encrypt для $BASE_HOST"
    local mail_args=(--register-unsafely-without-email)
    [ -n "$LE_EMAIL" ] && mail_args=(-m "$LE_EMAIL")
    if certbot --nginx -d "$BASE_HOST" --non-interactive --agree-tos "${mail_args[@]}" --redirect; then
      ok "сертификат получен, продление — автоматически (certbot.timer)"
    else
      warn "certbot не смог получить сертификат. Проверьте: DNS $BASE_HOST указывает на этот сервер,"
      warn "порт 80 открыт снаружи. Повтор: certbot --nginx -d $BASE_HOST"
    fi
  fi
  if have ufw && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow 'Nginx Full' >/dev/null && ok "ufw: открыты 80 и 443"
  fi
}

# ── Проверка ────────────────────────────────────────────────────────────────
local_health_url() { printf 'http://127.0.0.1:%s%s/healthz' "$PROXY_PORT" "$BASE_PATH"; }
local_health_once() {
  if [ "$MODE" = docker ]; then
    docker exec oauth-proxy wget -qO- "$(local_health_url)" 2>/dev/null | grep -q '"ok":true'
  else
    curl -fsS --max-time 3 "$(local_health_url)" 2>/dev/null | grep -q '"ok":true'
  fi
}
wait_local_health() {
  local _
  for _ in $(seq 1 20); do local_health_once && return 0; sleep 1; done
  return 1
}

http_code() {  # http_code METHOD URL [header-file] [json] → код ответа
  local args=(-sS -o /dev/null -w '%{http_code}' --max-time 10 -X "$1")
  [ -n "${3:-}" ] && args+=(-H "@$3")
  [ -n "${4:-}" ] && args+=(-H 'Content-Type: application/json' --data "$4")
  curl "${args[@]}" "$2" 2>/dev/null || true
}

# Почему адрес прокси не отвечает снаружи: DNS, соединение, сертификат или HTTP.
explain_external() {
  local ip mine err code
  ip="$(getent hosts "$BASE_HOST" 2>/dev/null | awk '{print $1; exit}')"
  if [ -z "$ip" ]; then
    warn "DNS: имя $BASE_HOST не разрешается"
    return 0
  fi
  mine="$(hostname -I 2>/dev/null) $(ip -o addr show 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' ')"
  if ! printf ' %s ' "$mine" | grep -q " $ip "; then
    warn "DNS: $BASE_HOST → $ip, а у этого сервера адреса: $(hostname -I 2>/dev/null)"
    warn "похоже, сайт $BASE_HOST обслуживается НЕ этим сервером — путь /oauth на нём настроить нельзя;"
    warn "используйте имя, которое указывает сюда (например mail.ogneliss.ru/oauth или oauth.ogneliss.ru)"
  else
    ok "DNS: $BASE_HOST → $ip (этот сервер)"
  fi
  err="$(curl -sS -o /dev/null --max-time 10 "$BASE_URL/healthz" 2>&1 | head -1)"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE_URL/healthz" 2>/dev/null || true)"
  [ -n "$err" ] && warn "curl: $err"
  case "$code" in
    000|'') ;;
    404) warn "HTTP 404: сайт отвечает, но путь ${BASE_PATH:-/} не передаётся прокси (нет location в NPM/nginx)" ;;
    502|503|504) warn "HTTP $code: NPM/nginx не достучался до oauth-proxy:$PROXY_PORT (контейнер не в сети NPM?)" ;;
    *) warn "HTTP $code" ;;
  esac
  return 0
}

cmd_check() {
  [ -f "$ENV_FILE" ] || die "нет $ENV_FILE — прокси не установлен (вариант $MODE)"
  resolve_base_url
  PROXY_PORT="$(env_get PORT "$ENV_FILE")"; PROXY_PORT="${PROXY_PORT:-8787}"
  local fails=0 code hdr key body
  log "Проверка OAuth-прокси: $BASE_URL (вариант $MODE)"

  if [ "$MODE" = native ] && [ -z "$ROOT" ]; then
    systemctl is-active --quiet "$N_SERVICE" && ok "служба $N_SERVICE активна" || { bad "служба $N_SERVICE не запущена"; fails=$((fails + 1)); }
  elif [ "$MODE" = docker ]; then
    docker ps --filter name=^oauth-proxy$ --format '{{.Status}}' 2>/dev/null | grep -q . \
      && ok "контейнер oauth-proxy: $(docker ps --filter name=^oauth-proxy$ --format '{{.Status}}')" \
      || { bad "контейнер oauth-proxy не запущен"; fails=$((fails + 1)); }
  fi
  if local_health_once; then ok "локально отвечает ($(local_health_url))"
  else bad "локально не отвечает: $(local_health_url)"; fails=$((fails + 1)); fi

  body="$(curl -fsS --max-time 10 "$BASE_URL/healthz" 2>/dev/null || true)"
  if printf '%s' "$body" | grep -q '"ok":true'; then ok "снаружи отвечает: $BASE_URL/healthz"
  else
    bad "снаружи не отвечает: $BASE_URL/healthz"
    explain_external
    [ "$MODE" = docker ] && warn "проверьте Nginx Proxy Manager: location ${BASE_PATH:-/} → oauth-proxy:$PROXY_PORT"
    [ "$MODE" = native ] && warn "проверьте nginx (include snippets/ogneliss-oauth-proxy.conf), DNS и сертификат"
    fails=$((fails + 1))
  fi

  code="$(http_code POST "$BASE_URL/exchange" "" '{}')"
  case "$code" in
    401) ok "POST /exchange без ключа → 401 (версия с PKCE)" ;;
    404) bad "POST /exchange → 404: на сервере старая версия прокси. Выполните: sudo bash $0 update"; fails=$((fails + 1)) ;;
    *) bad "POST /exchange без ключа → $code (ожидалось 401)"; fails=$((fails + 1)) ;;
  esac

  key="$(env_get PROXY_API_KEY "$ENV_FILE")"
  if [ -n "$key" ]; then
    hdr="$(mktemp)"; chmod 600 "$hdr"
    printf 'x-api-key: %s\n' "$key" > "$hdr"
    code="$(http_code POST "$BASE_URL/exchange" "$hdr" '{"oc":"check","cv":"check"}')"
    rm -f "$hdr"
    case "$code" in
      400) ok "ключ PROXY_API_KEY принимается (тестовый код → 400)" ;;
      401) bad "ключ из .env не принят — контейнер/служба запущены со старым .env, перезапустите"; fails=$((fails + 1)) ;;
      *) bad "POST /exchange с ключом → $code (ожидалось 400)"; fails=$((fails + 1)) ;;
    esac
  else
    bad "в .env нет PROXY_API_KEY"; fails=$((fails + 1))
  fi

  code="$(http_code GET "$BASE_URL/callback?state=check")"
  [ "$code" = 400 ] && ok "callback отклоняет поддельный state (400)" || { bad "callback → $code (ожидалось 400)"; fails=$((fails + 1)); }

  if [[ "$BASE_URL" == https://* ]] && have openssl; then
    local end days
    end="$(echo | openssl s_client -servername "$BASE_HOST" -connect "$BASE_HOST:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
    if [ -n "$end" ]; then
      days=$(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
      if [ "$days" -lt 14 ]; then bad "сертификат $BASE_HOST истекает через $days дн."; fails=$((fails + 1))
      else ok "сертификат $BASE_HOST действует ещё $days дн."; fi
    else
      warn "не удалось прочитать сертификат $BASE_HOST:443"
    fi
  fi

  log "Провайдеры"
  provider_status
  echo >&2
  log "redirect_uri для консолей провайдеров: $CALLBACK_URL"
  log "Для сборки приложения: OAUTH_PROXY_URL=$BASE_URL, ключ — команда: sudo bash $0 key"
  if [ "$fails" -gt 0 ]; then bad "проблем: $fails"; return 1; fi
  ok "всё в порядке"
}

cmd_key() {
  [ -f "$ENV_FILE" ] || die "нет $ENV_FILE — прокси не установлен (вариант $MODE)"
  resolve_base_url
  local key; key="$(env_get PROXY_API_KEY "$ENV_FILE")"
  [ -n "$key" ] || die "в $ENV_FILE нет PROXY_API_KEY"
  warn "Это содержимое config/dart_defines.json для Android Studio. Не пересылайте его открыто"
  warn "(мессенджеры, почта): передайте на флешке или через защищённое хранилище."
  printf '{\n  "OAUTH_PROXY_URL": "%s",\n  "OAUTH_PROXY_KEY": "%s"\n}\n' "$BASE_URL" "$key"
}

# ── Главная ─────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"
  if [ "$CMD" = help ]; then usage; return 0; fi
  need_root
  detect_mode
  # Порт существующей установки берём из .env, иначе обновление «переедет» на 8787.
  if [ "$PORT_GIVEN" = 0 ] && [ -n "$(env_get PORT "$ENV_FILE")" ]; then
    PROXY_PORT="$(env_get PORT "$ENV_FILE")"
  fi
  case "$CMD" in
    check) if cmd_check; then return 0; else exit 1; fi ;;
    key) cmd_key; return 0 ;;
  esac

  log "Ogneliss OAuth-прокси, установщик $SCRIPT_VERSION"
  check_os
  check_sources
  if [ "$CMD" = update ] && [ ! -f "$ENV_FILE" ]; then
    die "прокси не найден ($ENV_FILE). Для первой установки: sudo bash $0 install --base-url ..."
  fi
  if [ "$CMD" = install ] && [ -f "$ENV_FILE" ]; then
    warn "прокси уже установлен — выполняю обновление; секреты сохраняются"
    CMD=update
  fi
  resolve_base_url
  cat >&2 <<EOF
  Вариант:     $MODE ($( [ "$MODE" = docker ] && echo "Docker за Nginx Proxy Manager" || echo "systemd + nginx"))
  Каталог:     $APP_DIR
  Настройки:   $ENV_FILE
  Адрес:       $BASE_URL
  redirect_uri $CALLBACK_URL
EOF
  confirm "Продолжить?" || die "отменено"

  if [ "$MODE" = docker ]; then docker_install; else native_install; fi

  echo >&2
  log "Провайдеры"
  provider_status
  cat >&2 <<EOF

Дальше:
  1. Заполните client_id и client_secret провайдеров: nano $ENV_FILE
     (или: sudo bash $0 update --secrets файл-с-секретами.env)
  2. Перезапустите прокси: $( [ "$MODE" = docker ] && echo "cd $APP_DIR && ${DC[*]:-docker compose} -f docker-compose.oauth.yml up -d" || echo "systemctl restart $N_SERVICE" )
  3. В консолях провайдеров укажите redirect_uri: $CALLBACK_URL
  4. Проверка: sudo bash $0 check
  5. Ключ для сборки приложения: sudo bash $0 key
EOF
  # Проверку снаружи при первой установке через NPM запускать рано — NPM ещё не настроен.
  if [ "$CMD" = update ] || [ "$MODE" = native ]; then echo >&2; cmd_check || true; fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then main "$@"; fi
