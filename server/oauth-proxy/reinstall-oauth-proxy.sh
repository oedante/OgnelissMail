#!/usr/bin/env bash
# =============================================================================
#  Ogneliss Mail — очистка сервера от всех установок OAuth-прокси и установка
#  заново: Docker-контейнер в сети Nginx Proxy Manager, СТАРЫЕ секреты.
#
#  Что делает (по шагам, каждый печатается):
#    1. Проверяет окружение и файлы прокси рядом со скриптом.
#    2. Ищет все прежние установки и их секреты: .env в /opt/mailserver,
#       /opt/oauth-proxy, /etc/ogneliss-oauth-proxy, юниты systemd, окружение
#       контейнера oauth-proxy. Показывает отпечатки ключей (не сами ключи).
#    3. Делает резервную копию всего найденного в /root/oauth-proxy-backup-*.
#    4. Удаляет: службы systemd (oauth-proxy, ogneliss-oauth-proxy), контейнер
#       и образ, правила iptables для порта 8787, старые каталоги.
#    5. Ставит прокси в /opt/mailserver/oauth-proxy и запускает контейнер
#       oauth-proxy в сети NPM (порт наружу не открывается).
#    6. Проверяет прокси изнутри и из контейнера NPM.
#    7. Подсказывает, что поменять в NPM, и проверяет адрес снаружи.
#
#  Секреты (ENC_SECRET/STATE_SECRET, PROXY_API_KEY, *_CLIENT_ID/SECRET)
#  переносятся как есть: пользователи не теряют вход, приложение не нужно
#  пересобирать. Новые секреты создаются, только если старых нет совсем.
#
#  Запуск (из каталога server/oauth-proxy архива):
#    sudo bash reinstall-oauth-proxy.sh --dry-run          # только показать план
#    sudo bash reinstall-oauth-proxy.sh                    # выполнить
#
#  Параметры:
#    --base-url URL     внешний адрес прокси (по умолчанию из старого .env,
#                       иначе https://www.ogneliss.ru/oauth)
#    --env FILE         взять секреты из этого файла (если найдено несколько
#                       разных наборов — обязателен)
#    --mail-dir DIR     каталог почтового сервера (по умолчанию /opt/mailserver)
#    --npm NAME         имя контейнера Nginx Proxy Manager (по умолчанию ищется)
#    --network NET      сеть Docker NPM (по умолчанию — сеть контейнера NPM)
#    --dry-run          ничего не менять, только показать
#    --yes              не задавать вопросов
#    --status           только проверить: контейнер, журнал, NPM, адрес снаружи
#
#  После установки:
#    · автозапуск — Docker (restart: unless-stopped) + docker.service включён;
#    · журнал — docker logs oauth-proxy (ротация 10 МБ × 5 файлов);
#    · проверка в любой момент: sudo bash reinstall-oauth-proxy.sh --status
#    · порт 8787 открыт ТОЛЬКО на адресе шлюза сети NPM (172.x.0.1) — по
#      нему NPM уже пересылает /oauth; из интернета порт не виден.
# =============================================================================
set -Eeuo pipefail
umask 077

ROOT="${OG_ROOT:-}"            # префикс ФС — только для автотестов
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"

BASE_URL=""
ENV_ARG=""
MAIL_DIR="/opt/mailserver"
NPM=""
NET=""
DRY=0
YES=0
STATUS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url) BASE_URL="${2:?}"; shift ;;
    --env) ENV_ARG="${2:?}"; shift ;;
    --mail-dir) MAIL_DIR="${2:?}"; shift ;;
    --npm) NPM="${2:?}"; shift ;;
    --network) NET="${2:?}"; shift ;;
    --dry-run) DRY=1 ;;
    --yes|-y) YES=1 ;;
    --status) STATUS=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "Неизвестный параметр: $1" >&2; exit 2 ;;
  esac
  shift
done

APP_DIR="$ROOT$MAIL_DIR/oauth-proxy"
BACKUP="$ROOT/root/oauth-proxy-backup-$STAMP"
CONTAINER="oauth-proxy"
IMAGE="ogneliss/oauth-proxy:latest"

# ── Вывод ────────────────────────────────────────────────────────────────────
c_b=$'\e[1m'; c_g=$'\e[32m'; c_y=$'\e[33m'; c_r=$'\e[31m'; c_0=$'\e[0m'
[ -t 1 ] || { c_b=""; c_g=""; c_y=""; c_r=""; c_0=""; }
STEP=0
step() { STEP=$((STEP + 1)); printf '\n%s== Шаг %d/7. %s ==%s\n' "$c_b" "$STEP" "$*" "$c_0"; }
ok()   { printf '  %s✓%s %s\n' "$c_g" "$c_0" "$*"; }
info() { printf '  · %s\n' "$*"; }
warn() { printf '  %s!%s %s\n' "$c_y" "$c_0" "$*"; }
die()  { printf '\n%s✗ %s%s\n' "$c_r" "$*" "$c_0" >&2; exit 1; }
# BASH_LINENO[0] — строка ВЫЗОВА: при сбое внутри run() печатается место,
# откуда её вызвали, а не строка 87 с "$@" (так было в октябре 2026).
on_err() {  # $1 — LINENO места сбоя
  local ln="$1"
  [ ${#FUNCNAME[@]} -gt 2 ] && ln="${BASH_LINENO[1]}"
  die "Ошибка в строке $ln: $BASH_COMMAND"
}
trap 'on_err $LINENO' ERR

# Изменяющие команды — только через run: в --dry-run они печатаются.
run() {
  if [ "$DRY" = 1 ]; then printf '  %s[dry-run]%s %s\n' "$c_y" "$c_0" "$*"; return 0; fi
  "$@"
}
# Необязательные шаги: сбой — предупреждение, а не остановка посреди удаления.
try() {
  if [ "$DRY" = 1 ]; then printf '  %s[dry-run]%s %s\n' "$c_y" "$c_0" "$*"; return 0; fi
  "$@" || { warn "не удалось (продолжаем): $*"; return 0; }
}
ask() {
  [ "$YES" = 1 ] && return 0
  [ "$DRY" = 1 ] && return 0
  local a=""; read -r -p "  $* [y/N] " a || true; [[ "$a" =~ ^[yYдД] ]]
}

env_get() {  # env_get KEY FILE → значение без кавычек
  local v
  v="$(grep -E "^[[:space:]]*(export[[:space:]]+)?$1=" "$2" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  v="${v%$'\r'}"; v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
  printf '%s' "$v"
}
fp() { [ -n "$1" ] && printf '%s' "$1" | sha256sum | cut -c1-8 || printf 'нет'; }
enc_fp() {  # ключ шифрования blob: ENC_SECRET, иначе STATE_SECRET (как в server.js)
  local e s; e="$(env_get ENC_SECRET "$1")"; s="$(env_get STATE_SECRET "$1")"
  fp "${e:-$s}"
}

# ═════════════════════════════════════════════════════════════════════════════
step "Проверка окружения"
[ "$(id -u)" = 0 ] || [ -n "$ROOT" ] || die "Запустите от root: sudo bash $0"
command -v docker >/dev/null || die "Нет docker"
if docker compose version >/dev/null 2>&1; then DC=(docker compose)
elif command -v docker-compose >/dev/null; then DC=(docker-compose)
else die "Нет docker compose"; fi
for f in server.js package.json package-lock.json Dockerfile; do
  [ -f "$SCRIPT_DIR/$f" ] || die "Рядом со скриптом нет $f — запускайте из каталога server/oauth-proxy архива"
done
grep -q "authStyle: 'basic'" "$SCRIPT_DIR/server.js" || die "server.js рядом со скриптом — старый (нет Basic для Яндекса)"
ok "docker, ${DC[*]}, файлы прокси на месте"
[ "$DRY" = 1 ] && warn "Режим --dry-run: ничего не меняется"

# Контейнер Nginx Proxy Manager и его сеть
if [ -z "$NPM" ]; then
  NPM="$(docker ps --format '{{.Names}} {{.Image}}' \
    | awk 'tolower($0) ~ /nginx-proxy-manager|proxy-manager|jc21/ {print $1; exit}')"
fi
[ -n "$NPM" ] || die "Не найден контейнер Nginx Proxy Manager — укажите --npm ИМЯ"
if [ -z "$NET" ]; then
  NET="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$NPM" \
    | awk '{print $1}')"
fi
[ -n "$NET" ] || die "Не удалось определить сеть контейнера $NPM — укажите --network"
ok "NPM: контейнер $NPM, сеть $NET"
GW="$(docker network inspect "$NET" -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}' 2>/dev/null | awk '{print $1}')"
[ -n "$GW" ] && ok "шлюз сети $NET: $GW (сюда NPM пересылал /oauth в варианте systemd)"

# Проверка установленного прокси: контейнер, журнал, связь с NPM, снаружи.
status_report() {
  local base_url="$1" hz_path="$2"
  printf '\n%s== Состояние OAuth-прокси ==%s\n' "$c_b" "$c_0"
  if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    warn "контейнера $CONTAINER нет"; return 1
  fi
  info "контейнер: $(docker inspect -f '{{.State.Status}} (здоровье: {{if .State.Health}}{{.State.Health.Status}}{{else}}нет проверки{{end}}), перезапусков: {{.RestartCount}}, запущен {{.State.StartedAt}}' "$CONTAINER")"
  info "автозапуск: restart=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER"), docker.service: $(systemctl is-enabled docker 2>/dev/null || echo ?)"
  info "журнал: $(docker inspect -f '{{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}' "$CONTAINER")"
  local hz
  if hz="$(docker exec "$CONTAINER" node -e "fetch('http://127.0.0.1:8787$hz_path').then(r=>r.text()).then(t=>console.log(t)).catch(e=>{console.error(e.message);process.exit(1)})" 2>&1)"; then
    ok "изнутри контейнера: $hz"
  else
    warn "изнутри контейнера не отвечает: $hz"
  fi
  if docker exec "$NPM" sh -c "command -v curl >/dev/null && curl -fsS -m 5 http://$CONTAINER:8787$hz_path || wget -qO- -T 5 http://$CONTAINER:8787$hz_path" >/dev/null 2>&1; then
    ok "из NPM по имени: http://$CONTAINER:8787 — работает"
  else
    warn "из NPM по имени http://$CONTAINER:8787 — НЕ отвечает (сеть $NET?)"
  fi
  if [ -n "${GW:-}" ] && command -v curl >/dev/null; then
    if curl -fsS -m 5 "http://$GW:8787$hz_path" >/dev/null 2>&1; then
      ok "по адресу шлюза: http://$GW:8787 — работает (старая настройка NPM тоже подходит)"
    else
      warn "по адресу шлюза http://$GW:8787 — не отвечает"
    fi
  fi
  # Как NPM сейчас пересылает /oauth. Каталог данных NPM — из точки
  # монтирования /data его контейнера (не обязательно $MAIL_DIR/data).
  local npm_data conf_dir found=0
  npm_data="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$NPM" 2>/dev/null || true)"
  conf_dir="${npm_data:-$ROOT$MAIL_DIR/data}/nginx/proxy_host"
  [ -d "$conf_dir" ] || conf_dir="$ROOT$MAIL_DIR/data/nginx/proxy_host"
  info "конфигурация NPM: $conf_dir"
  if [ -d "$conf_dir" ]; then
    for f in "$conf_dir"/*.conf; do
      [ -f "$f" ] || continue
      if grep -qE "location[[:space:]]+${BASE_PATH:-/oauth}([[:space:]/{]|$)" "$f"; then
        found=1
        info "NPM ${f#$ROOT}: $(grep -E 'server_name' "$f" | head -n1 | sed 's/^[[:space:]]*//')"
        awk -v loc="${BASE_PATH:-/oauth}" '$0 ~ "location[ \t]+"loc {p=1} p && /proxy_pass|set \$server|set \$port|set \$forward_scheme/ {gsub(/^[ \t]+/,""); print "      " $0} p && /}/ {p=0}' "$f"
      fi
    done
    if [ $found = 0 ]; then
      warn "в конфигурации NPM нет location ${BASE_PATH:-/oauth} — NPM не знает, куда пересылать /oauth"
      local host_conf
      host_conf="$(grep -lE "server_name[^;]*${BASE_HOST//./\\.}" "$conf_dir"/*.conf 2>/dev/null | head -n1 || true)"
      [ -n "$host_conf" ] && info "хост ${BASE_HOST} в NPM: ${host_conf#$ROOT}"
    fi
  else
    warn "каталог конфигурации NPM не найден: $conf_dir"
  fi
  if command -v curl >/dev/null; then
    local code body local_code
    # Через сам NPM на этом сервере (минуя внешний IP: часть хостингов не
    # пропускает обращение сервера к собственному внешнему адресу).
    local_code="$(curl -sk -o /dev/null -m 10 -w '%{http_code}' --resolve "${BASE_HOST}:443:127.0.0.1" "$base_url/healthz" 2>/dev/null || true)"
    if [ "$local_code" = 200 ]; then
      ok "через NPM на этом сервере: $base_url/healthz → 200"
    else
      warn "через NPM на этом сервере: $base_url/healthz → HTTP ${local_code:-нет ответа}"
    fi
    # 000 — на 443 вообще никто не отвечает: дело не в /oauth, а в самом NPM
    # (его nginx не запустился из-за ошибки в конфигурации, контейнер
    # остановлен или после перезагрузки пропали правила Docker для портов).
    if [ "${local_code:-000}" = 000 ]; then
      warn "порт 443 на этом сервере не отвечает — не работает весь сайт, а не только /oauth"
      info "контейнер NPM: $(docker inspect -f '{{.State.Status}} (перезапусков: {{.RestartCount}})' "$NPM" 2>/dev/null || echo 'не найден')"
      info "порты NPM: $(docker port "$NPM" 2>/dev/null | tr '\n' ' ')"
      if command -v ss >/dev/null; then
        info "слушают 80/443: $(ss -ltnH 2>/dev/null | awk '{print $4}' | grep -E ':(80|443)$' | tr '\n' ' ')"
      fi
      local t
      t="$(docker exec "$NPM" nginx -t 2>&1 | tail -n 4 || true)"
      if printf '%s' "$t" | grep -q 'successful'; then
        ok "nginx в NPM: конфигурация верна"
        cat <<HINT
  Конфигурация верна, но порт закрыт. Чаще всего после перезагрузки сервера
  пропали правила Docker для портов (их стёр файрвол). Помогает:
    sudo systemctl restart docker      # контейнеры с restart=unless-stopped поднимутся сами
HINT
      else
        warn "nginx в NPM не принимает конфигурацию:"
        printf '%s\n' "$t" | sed 's/^/      /'
        cat <<HINT
  Исправьте строку, на которую указывает ошибка (обычно — «Advanced» хоста
  в NPM: повтор location или незакрытая скобка), затем:
    docker exec $NPM nginx -t && docker exec $NPM nginx -s reload
HINT
      fi
    fi
    body="$(curl -sS -m 10 -w '\n%{http_code}' "$base_url/healthz" 2>&1 || true)"; code="${body##*$'\n'}"; body="${body%$'\n'*}"
    if [ "$code" = 200 ] && printf '%s' "$body" | grep -q '"ok":true'; then
      ok "снаружи $base_url/healthz → 200"
      local want; want="$(fp "$(env_get PROXY_API_KEY "$APP_DIR/.env")")"
      printf '%s' "$body" | grep -q "\"api\":\"$want\"" && ok "снаружи отвечает ЭТОТ прокси (ключ $want)" \
        || warn "снаружи отвечает прокси с ДРУГИМ ключом — NPM пересылает не сюда"
    else
      warn "снаружи $base_url/healthz → HTTP ${code:-нет ответа}: $(printf '%s' "$body" | tr '\n' ' ' | head -c 200)"
      [ "${local_code:-000}" = 000 ] || cat <<HINT
  Добавьте в NPM (веб-интерфейс, обычно http://IP-сервера:81):
    Hosts → Proxy Hosts → ${BASE_HOST} → Edit → вкладка Custom Locations → Add location
      Define location:        ${BASE_PATH:-/oauth}
      Scheme:                 http
      Forward Hostname / IP:  $CONTAINER
      Forward Port:           8787
    → Save. Затем снова: sudo bash $0 --status
HINT
    fi
  fi
  printf '\n  Последние строки журнала (docker logs --tail 25 %s):\n' "$CONTAINER"
  docker logs --tail 25 "$CONTAINER" 2>&1 | sed 's/^/    /' || true
}

# ═════════════════════════════════════════════════════════════════════════════
step "Поиск прежних установок и секретов"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
declare -a CANDS=()
add_cand() { [ -f "$1" ] && CANDS+=("$1") || true; }

[ -n "$ENV_ARG" ] && { [ -f "$ENV_ARG" ] || die "Нет файла $ENV_ARG"; add_cand "$ENV_ARG"; }
for f in "$APP_DIR/.env" "$ROOT/opt/oauth-proxy/.env" \
         "$ROOT/etc/ogneliss-oauth-proxy/oauth-proxy.env" "$ROOT/opt/ogneliss-oauth-proxy/.env"; do
  add_cand "$f"
done
UNITS=()
for u in oauth-proxy ogneliss-oauth-proxy; do
  if [ -f "$ROOT/etc/systemd/system/$u.service" ]; then
    UNITS+=("$u")
    ef="$(grep -E '^EnvironmentFile=' "$ROOT/etc/systemd/system/$u.service" | head -n1 | cut -d= -f2- | sed 's/^-//' || true)"
    [ -n "$ef" ] && add_cand "$ROOT$ef"
  fi
done
HAVE_CONTAINER=0
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  HAVE_CONTAINER=1
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" > "$TMP/container.env"
  add_cand "$TMP/container.env"
fi

# Уникальные файлы, у которых есть ключи
declare -a GOOD=()
declare -A SEEN=()
for f in "${CANDS[@]}"; do
  real="$(readlink -f "$f")"; [ -n "${SEEN[$real]:-}" ] && continue; SEEN[$real]=1
  api="$(env_get PROXY_API_KEY "$f")"
  printf '  %-52s api=%s enc=%s google=%s yandex=%s\n' "${f#$ROOT}" \
    "$(fp "$api")" "$(enc_fp "$f")" \
    "$([ -n "$(env_get GOOGLE_CLIENT_SECRET "$f")" ] && echo да || echo нет)" \
    "$([ -n "$(env_get YANDEX_CLIENT_SECRET "$f")" ] && echo да || echo нет)"
  [ -n "$api" ] && [ -n "$(env_get STATE_SECRET "$f")" ] && GOOD+=("$f")
done
[ ${#CANDS[@]} -eq 0 ] && info "прежних файлов с настройками не найдено"
info "службы systemd: ${UNITS[*]:-нет}; контейнер $CONTAINER: $([ $HAVE_CONTAINER = 1 ] && echo есть || echo нет)"

SRC=""
if [ -n "$ENV_ARG" ]; then
  SRC="$ENV_ARG"
elif [ ${#GOOD[@]} -gt 0 ]; then
  SRC="${GOOD[0]}"
  # Разные ключи шифрования — разные «вселенные» входов: выбрать за
  # пользователя нельзя, ошибка выкинет всех из OAuth-ящиков.
  first_enc="$(enc_fp "$SRC")"
  for f in "${GOOD[@]}"; do
    if [ "$(enc_fp "$f")" != "$first_enc" ]; then
      die "Найдено несколько наборов секретов с разными ключами шифрования.
  Укажите нужный: --env ФАЙЛ. Нужен тот, с которым входили ящики в приложении
  (его api-отпечаток совпадает с отпечатком в диагностике приложения)."
    fi
  done
fi
if [ -n "$SRC" ]; then
  ok "секреты берутся из ${SRC#$ROOT} (api=$(fp "$(env_get PROXY_API_KEY "$SRC")"), enc=$(enc_fp "$SRC"))"
  cp "$SRC" "$TMP/source.env"
else
  warn "старых секретов нет — будут созданы новые (приложение придётся собрать с новым ключом)"
  : > "$TMP/source.env"
fi
# Хранилище сессий старого режима (/token?session=…). Основной вход —
# stateless (rt в приложении), но сессии тоже переносим, чтобы никого не выкинуть.
OLD_STORE=""
for f in "$ROOT$(env_get STORE_PATH "$TMP/source.env")" "$ROOT/var/lib/oauth-proxy/store.json" \
         "$APP_DIR/data/store.json" "$ROOT/opt/oauth-proxy/data/store.json"; do
  [ -n "${f#$ROOT}" ] && [ -s "$f" ] && { OLD_STORE="$f"; break; }
done
if [ -z "$OLD_STORE" ] && [ $HAVE_CONTAINER = 1 ]; then
  docker cp "$CONTAINER:/data/store.json" "$TMP/store.json" >/dev/null 2>&1 && OLD_STORE="$TMP/store.json" || true
fi
[ -n "$OLD_STORE" ] && cp "$OLD_STORE" "$TMP/store.json" 2>/dev/null || true
[ -n "$OLD_STORE" ] && ok "хранилище сессий: ${OLD_STORE#$ROOT} (будет перенесено)" || info "хранилища сессий нет (нужно только для старого режима)"

[ -z "$BASE_URL" ] && BASE_URL="$(env_get BASE_URL "$TMP/source.env")"
BASE_URL="${BASE_URL:-https://www.ogneliss.ru/oauth}"; BASE_URL="${BASE_URL%/}"
BASE_PATH="$(printf '%s' "$BASE_URL" | sed -E 's#^https?://[^/]+##')"
BASE_HOST="$(printf '%s' "$BASE_URL" | sed -E 's#^https?://([^/:]+).*#\1#')"
ok "внешний адрес: $BASE_URL (путь «${BASE_PATH:-/}»)"

if [ "$STATUS" = 1 ]; then
  status_report "$BASE_URL" "${BASE_PATH}/healthz"
  exit 0
fi

# Сайт до переустановки: если 443 уже не отвечает, переустановка прокси
# этого не исправит (и не она это сломала) — сначала NPM.
if command -v curl >/dev/null; then
  pre="$(curl -sk -o /dev/null -m 8 -w '%{http_code}' --resolve "${BASE_HOST}:443:127.0.0.1" "https://${BASE_HOST}/" 2>/dev/null || true)"
  if [ "${pre:-000}" = 000 ]; then
    warn "https://${BASE_HOST}/ уже сейчас не отвечает (порт 443) — сайт лежит ДО переустановки прокси."
    warn "Причина в Nginx Proxy Manager: sudo bash $0 --status покажет подробности."
  else
    ok "сайт https://${BASE_HOST}/ отвечает (HTTP $pre)"
  fi
fi

ask "Продолжить: резервная копия, удаление старого, установка?" || die "Отменено"

# ═════════════════════════════════════════════════════════════════════════════
step "Резервная копия → ${BACKUP#$ROOT}"
run mkdir -p "$BACKUP"
i=0
for f in "${CANDS[@]}"; do i=$((i + 1)); run cp -a "$f" "$BACKUP/env-$i-$(basename "$f")"; done
[ -s "$TMP/store.json" ] && run cp -a "$TMP/store.json" "$BACKUP/store.json"
for u in "${UNITS[@]}"; do run cp -a "$ROOT/etc/systemd/system/$u.service" "$BACKUP/"; done
for d in "$APP_DIR" "$ROOT/opt/oauth-proxy" "$ROOT/opt/ogneliss-oauth-proxy" "$ROOT/etc/ogneliss-oauth-proxy"; do
  [ -d "$d" ] && run tar -C "$(dirname "$d")" -czf "$BACKUP/$(basename "$d").tgz" \
    --exclude=node_modules "$(basename "$d")"
done
command -v iptables-save >/dev/null && { [ "$DRY" = 1 ] || iptables-save > "$BACKUP/iptables.rules"; }
NPM_CONF_DIR="$ROOT$MAIL_DIR/data/nginx/proxy_host"
NPM_CONFS=()
if [ -d "$NPM_CONF_DIR" ]; then
  while IFS= read -r f; do NPM_CONFS+=("$f"); run cp -a "$f" "$BACKUP/"; done \
    < <(grep -l ':8787' "$NPM_CONF_DIR"/*.conf 2>/dev/null || true)
fi
[ "$DRY" = 1 ] || chmod 700 "$BACKUP"
ok "сохранено: .env (${#CANDS[@]}), юниты (${#UNITS[@]}), каталоги, iptables, конфиги NPM (${#NPM_CONFS[@]})"

# ═════════════════════════════════════════════════════════════════════════════
step "Удаление прежних установок"
for u in "${UNITS[@]}"; do
  try systemctl disable --now "$u"
  run rm -f "$ROOT/etc/systemd/system/$u.service"
  ok "служба $u удалена"
done
[ ${#UNITS[@]} -gt 0 ] && try systemctl daemon-reload
if [ $HAVE_CONTAINER = 1 ]; then run docker rm -f "$CONTAINER"; ok "контейнер $CONTAINER удалён"; fi
if docker image inspect "$IMAGE" >/dev/null 2>&1; then try docker rmi "$IMAGE"; ok "образ $IMAGE удалён"; fi
# Правила iptables для 8787 (открывались для варианта systemd)
if command -v iptables >/dev/null; then
  n=0
  while IFS= read -r rule; do
    [ -z "$rule" ] && continue
    # shellcheck disable=SC2086
    try iptables ${rule/-A /-D }; n=$((n + 1))
  done < <(iptables -S INPUT 2>/dev/null | grep -- '--dport 8787' || true)
  if [ $n -gt 0 ]; then
    if command -v netfilter-persistent >/dev/null; then try netfilter-persistent save >/dev/null; fi
    ok "правил iptables для 8787 удалено: $n"
  fi
fi
# Сайт nginx варианта native (только файлы прокси, остальное не трогаем)
NGX_CHANGED=0
for f in "$ROOT"/etc/nginx/sites-enabled/*oauth-proxy* "$ROOT"/etc/nginx/sites-available/*oauth-proxy*; do
  [ -e "$f" ] || continue; run rm -f "$f"; NGX_CHANGED=1; ok "удалён ${f#$ROOT}"
done
# Системный nginx на этом сервере обычно выключен (снаружи работает NPM):
# перезагружаем его, только если он запущен. Раньше здесь падал скрипт —
# «nginx.service is not active, cannot reload» на полпути удаления.
if [ $NGX_CHANGED = 1 ] && command -v nginx >/dev/null; then
  if systemctl is-active --quiet nginx 2>/dev/null; then
    if run nginx -t; then try systemctl reload nginx; else warn "nginx -t не прошёл — проверьте /etc/nginx вручную"; fi
  else
    info "системный nginx не запущен — перезагрузка не нужна"
  fi
fi
for d in "$ROOT/opt/oauth-proxy" "$ROOT/opt/ogneliss-oauth-proxy" "$ROOT/etc/ogneliss-oauth-proxy" "$APP_DIR"; do
  [ -d "$d" ] && { run rm -rf "$d"; ok "удалён каталог ${d#$ROOT}"; }
done
# Старый файл compose из каталога почтового сервера больше не нужен
if [ -f "$ROOT$MAIL_DIR/docker-compose.oauth.yml" ]; then
  run mv "$ROOT$MAIL_DIR/docker-compose.oauth.yml" "$ROOT$MAIL_DIR/docker-compose.oauth.yml.disabled-$STAMP"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "Установка в ${APP_DIR#$ROOT}"
gen() { head -c 48 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-48; }
run mkdir -p "$APP_DIR"
for f in server.js package.json package-lock.json Dockerfile; do run cp "$SCRIPT_DIR/$f" "$APP_DIR/"; done
# umask 077 (ради .env) дал бы файлам кода права 600: в контейнере Node
# работает от пользователя node и не прочитал бы их («Cannot read package
# config /app/package.json: permission denied», 07.10.2026). Код — 644,
# каталог — 755; секреты — только .env (600), в образ он не попадает.
run chmod 755 "$APP_DIR"
for f in server.js package.json package-lock.json Dockerfile; do run chmod 644 "$APP_DIR/$f"; done
printf '.env\n*.env\nnode_modules\n' > "$TMP/dockerignore"
run cp "$TMP/dockerignore" "$APP_DIR/.dockerignore"
[ "$DRY" = 1 ] || chmod 644 "$APP_DIR/.dockerignore"

# .env: все прежние переменные, кроме сетевых (их задаёт compose), + обязательные
{
  echo "# OAuth-прокси Ogneliss — создано reinstall-oauth-proxy.sh $STAMP"
  echo "# Секреты перенесены из ${SRC#$ROOT}"
  grep -E '^[[:space:]]*(export[[:space:]]+)?[A-Z_][A-Z0-9_]*=' "$TMP/source.env" \
    | sed -E 's/^[[:space:]]*export[[:space:]]+//' \
    | grep -vE '^(HOST|PORT|BASE_URL|STORE_PATH|NODE_ENV|PATH|HOSTNAME|HOME|NODE_VERSION|YARN_VERSION)=' || true
  echo "BASE_URL=$BASE_URL"
  echo "STORE_PATH=/data/store.json"
} > "$TMP/new.env"
for k in STATE_SECRET PROXY_API_KEY ENC_SECRET; do
  if [ -z "$(env_get "$k" "$TMP/new.env")" ]; then
    # ENC_SECRET не добавляем к старым секретам: без него ключ берётся из
    # STATE_SECRET, и новый ENC_SECRET сделал бы старые входы нечитаемыми.
    if [ "$k" = ENC_SECRET ] && [ -n "$(env_get STATE_SECRET "$TMP/source.env")" ]; then continue; fi
    echo "$k=$(gen)" >> "$TMP/new.env"; warn "создан новый $k"
  fi
done
grep -q '^ALLOWED_REDIRECTS=' "$TMP/new.env" || echo "ALLOWED_REDIRECTS=com.ogneliss.mail://oauth" >> "$TMP/new.env"
[ "$(enc_fp "$TMP/new.env")" = "$(enc_fp "$TMP/source.env")" ] || [ ! -s "$TMP/source.env" ] \
  || die "Ключ шифрования изменился бы — остановка (ошибка скрипта, сообщите)"

PORTS_LINE=""
if [ -n "${GW:-}" ]; then
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "(^|:)${GW//./\\.}:8787$|^\*:8787$|0\.0\.0\.0:8787$"; then
    warn "порт $GW:8787 уже занят — публикация на шлюзе пропущена (NPM: оставьте Forward Hostname $CONTAINER)"
  else
    PORTS_LINE="    ports: [\"$GW:8787:8787\"]"
  fi
fi
cat > "$TMP/compose.yml" <<EOF
# OAuth-прокси Ogneliss — создано reinstall-oauth-proxy.sh $STAMP
# version нужен старому docker-compose 1.x (на сервере стоит он); compose v2 его игнорирует.
version: "3.7"
services:
  oauth-proxy:
    build: .
    image: $IMAGE
    container_name: $CONTAINER
    env_file: [./.env]
    environment:
      - HOST=0.0.0.0
      - PORT=8787
      - NODE_ENV=production
    expose: ["8787"]
    # Порт — только на адресе шлюза сети NPM ($GW): по нему NPM пересылал /oauth
    # в варианте systemd, и прежняя настройка NPM продолжает работать. Снаружи
    # (из интернета) этот адрес недоступен.
$PORTS_LINE
    restart: unless-stopped
    # Проверка живости: Docker показывает unhealthy, если прокси завис.
    healthcheck:
      test: ["CMD", "node", "-e", "fetch('http://127.0.0.1:8787${BASE_PATH}/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 20s
    # Журнал с ротацией: не больше 5 файлов по 10 МБ.
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"
    read_only: true
    tmpfs: [/tmp]
    volumes: [oauth-proxy-data:/data]
    security_opt: [no-new-privileges:true]
    networks: [npm]
volumes:
  oauth-proxy-data:
networks:
  npm:
    name: $NET
    external: true
EOF
run cp "$TMP/new.env" "$APP_DIR/.env"
run cp "$TMP/compose.yml" "$APP_DIR/docker-compose.yml"
[ "$DRY" = 1 ] || { chmod 600 "$APP_DIR/.env"; chmod 644 "$APP_DIR/docker-compose.yml"; }
ok ".env (600) и docker-compose.yml записаны"
if [ "$DRY" = 1 ]; then
  info "был бы запущен: (cd ${APP_DIR#$ROOT} && ${DC[*]} -p oauth-proxy up -d --build)"
else
  if ! (cd "$APP_DIR" && "${DC[@]}" -p oauth-proxy up -d --build --force-recreate) >"$TMP/compose.log" 2>&1; then
    tail -n 40 "$TMP/compose.log" >&2
    die "docker compose не собрал/не запустил контейнер (журнал выше). Секреты: $BACKUP"
  fi
  # Том /data — владельцу node (uid 1000) внутри контейнера; перенос сессий.
  VOL="oauth-proxy_oauth-proxy-data"
  if [ -s "$TMP/store.json" ]; then
    docker run --rm -v "$VOL:/data" -v "$TMP:/src:ro" alpine:3 \
      sh -c 'cp /src/store.json /data/store.json && chmod 600 /data/store.json' >/dev/null 2>&1 \
      && ok "хранилище сессий перенесено в том $VOL" || warn "не удалось перенести store.json (копия: $BACKUP)"
  fi
  docker run --rm -v "$VOL:/data" alpine:3 chown -R 1000:1000 /data >/dev/null 2>&1 || warn "chown тома $VOL не выполнен"
  docker restart "$CONTAINER" >/dev/null
  ok "контейнер $CONTAINER собран и запущен"
  # Автозапуск после перезагрузки сервера: Docker поднимает контейнер сам
  # (restart: unless-stopped), если включена служба docker.
  systemctl enable docker.service containerd.service >/dev/null 2>&1 \
    && ok "автозапуск: docker.service включён" || warn "не удалось включить docker.service — проверьте: systemctl is-enabled docker"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "Проверка прокси"
HZ_PATH="${BASE_PATH}/healthz"
if [ "$DRY" = 1 ]; then
  info "проверка изнутри: http://$CONTAINER:8787$HZ_PATH"
else
  hz=""
  for _ in $(seq 1 30); do
    hz="$(docker exec "$CONTAINER" node -e \
      "fetch('http://127.0.0.1:8787$HZ_PATH').then(r=>r.text()).then(t=>console.log(t)).catch(()=>process.exit(1))" 2>/dev/null)" && break
    sleep 2
  done
  [ -n "$hz" ] || { docker logs --tail 30 "$CONTAINER" >&2; die "прокси не отвечает (журнал выше)"; }
  ok "прокси отвечает"
  printf '%s' "$hz" | grep -q '"google":{"clientId":true,"clientSecret":true' \
    && ok "Google: client_id и client_secret заданы" || warn "Google: client_id/secret НЕ заданы в .env"
fi

# ═════════════════════════════════════════════════════════════════════════════
step "Nginx Proxy Manager и проверка снаружи"
[ "$DRY" = 1 ] || status_report "$BASE_URL" "$HZ_PATH"

printf '\n%sГотово.%s\n' "$c_b" "$c_0"
cat <<EOF
  Резервная копия:  ${BACKUP#$ROOT}
  Каталог прокси:   ${APP_DIR#$ROOT}   (обновление: положить новый server.js и
                    выполнить: cd ${APP_DIR#$ROOT} && ${DC[*]} -p oauth-proxy up -d --build)
  Журнал прокси:    docker logs -f $CONTAINER   (ротация 10 МБ × 5)
  Проверка:         sudo bash $0 --status
  Сверка с приложением: «отпечаток ключа» в диагностике приложения должен
  совпасть с keys.api в $BASE_URL/healthz.
  Причина отказа провайдера видна в журнале, например:
    oauth-proxy: google refresh_token → HTTP 401 invalid_client
EOF
