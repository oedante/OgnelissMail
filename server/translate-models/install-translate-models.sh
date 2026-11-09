#!/usr/bin/env bash
# Модели перевода Ogneliss Mail для Windows (2.2.0): Firefox Translations
# (Mozilla, MPL-2.0) на сервере Ogneliss — приложение скачивает языки отсюда,
# а не у Google или Mozilla (решение владельца 09.11.2026).
#
#   sudo bash install-translate-models.sh install  — скачать модели и запустить раздачу
#   sudo bash install-translate-models.sh models   — только обновить модели
#   sudo bash install-translate-models.sh check    — проверить
#
# Модели — из набора Firefox Translations 0.3.3 (registry.json проекта
# Bergamot); каждый файл сверяется с sha256 из списка, index.json — только
# проверенные пары. Раздаёт контейнер nginx в сети Nginx Proxy Manager (как
# weather-proxy), адрес снаружи — https://ogneliss.ru/mail/translate/v1/.
# Подробно — README.md рядом.
set -euo pipefail

DIR="${DIR:-/opt/mailserver/translate-models}"
CONTAINER="translate-models"
PORT=8790
NPM_NETWORK="${NPM_NETWORK:-}"
SOURCE="${SOURCE:-https://storage.googleapis.com/bergamot-models-sandbox/0.3.3}"
# Пары через пробел (enru ruen …); пусто — все из registry.json (~670 МБ).
PAIRS="${PAIRS:-}"
NGINX_IMAGE="nginx:1.27-alpine"
SRC="$(cd "$(dirname "$0")" && pwd)"

ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

detect_network() {
  [ -n "$NPM_NETWORK" ] && return 0
  local n
  for c in weather-proxy push-relay proxy-manager oauth-proxy; do
    n="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$c" 2>/dev/null | awk '{print $1}')"
    [ -n "$n" ] && { NPM_NETWORK="$n"; return 0; }
  done
  NPM_NETWORK="mailserver_default"
}

models() {
  command -v python3 >/dev/null || die "нужен python3 (apt install python3)"
  command -v curl >/dev/null || die "нужен curl"
  local out="$DIR/www/v1" tmp
  mkdir -p "$out"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/registry.json" "$SOURCE/registry.json" || die "не скачан $SOURCE/registry.json"
  # Список файлов: пара, имя, размер, sha256 (имена — без путей).
  python3 -I - "$tmp/registry.json" "$PAIRS" > "$tmp/files.tsv" <<'PY' || die "registry.json не разобран"
import json, re, sys
reg = json.load(open(sys.argv[1], encoding='utf-8'))
want = set(sys.argv[2].split())
for pair, parts in sorted(reg.items()):
    if not re.fullmatch(r'[a-z]{4}', pair) or (want and pair not in want):
        continue
    for role, f in sorted(parts.items()):
        if not isinstance(f, dict) or 'name' not in f:
            continue
        name, size, sha = f['name'], f.get('size'), f.get('expectedSha256Hash', '')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', name) or '..' in name:
            continue
        if not isinstance(size, int) or not re.fullmatch(r'[0-9a-f]{64}', sha):
            continue
        print(f'{pair}\t{name}\t{size}\t{sha}')
PY
  local n=0 bad=0 pair name size sha f
  while IFS=$'\t' read -r pair name size sha; do
    f="$out/$pair/$name"
    mkdir -p "$out/$pair"
    if [ -f "$f" ] && [ "$(stat -c %s "$f")" = "$size" ] && [ "$(sha256sum "$f" | awk '{print $1}')" = "$sha" ]; then
      n=$((n + 1)); continue
    fi
    if curl -fsSL --retry 3 -o "$f.part" "$SOURCE/$pair/$name" \
      && [ "$(stat -c %s "$f.part")" = "$size" ] \
      && [ "$(sha256sum "$f.part" | awk '{print $1}')" = "$sha" ]; then
      mv -f "$f.part" "$f"; n=$((n + 1))
    else
      rm -f "$f.part"; bad=$((bad + 1)); warn "не скачан или не совпал: $pair/$name"
    fi
  done < "$tmp/files.tsv"
  # index.json — только пары, все файлы которых на месте и проверены.
  python3 -I - "$tmp/registry.json" "$out" "$PAIRS" > "$tmp/index.json" <<'PY' || die "index.json не собран"
import hashlib, json, os, sys
reg = json.load(open(sys.argv[1], encoding='utf-8'))
out, want = sys.argv[2], set(sys.argv[3].split())
idx = {}
for pair, parts in sorted(reg.items()):
    if want and pair not in want:
        continue
    files = {r: f for r, f in parts.items() if isinstance(f, dict) and 'name' in f}
    good = True
    for f in files.values():
        p = os.path.join(out, pair, f['name'])
        if not os.path.isfile(p) or os.path.getsize(p) != f.get('size'):
            good = False
            break
    if good and files:
        idx[pair] = {r: {k: f[k] for k in ('name', 'size', 'expectedSha256Hash', 'modelType') if k in f}
                     for r, f in files.items()}
json.dump(idx, sys.stdout, ensure_ascii=False, indent=1, sort_keys=True)
PY
  install -m 0644 "$tmp/index.json" "$out/index.json"
  install -m 0644 "$SRC/LICENSE-MPL-2.0.txt" "$out/LICENSE-MPL-2.0.txt"
  cat > "$out/README.txt" <<TXT
Translation models for Ogneliss Mail (Windows): Firefox Translations models
by Mozilla, unmodified, licensed under the Mozilla Public License 2.0
(LICENSE-MPL-2.0.txt). Source: https://github.com/mozilla/firefox-translations-models
Mirrored from $SOURCE
TXT
  rm -rf "$tmp"
  chmod -R a+rX "$DIR/www"
  ok "моделей: файлов $n, пар в index.json: $(python3 -I -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$out/index.json")"
  [ "$bad" = 0 ] || warn "файлов с ошибкой: $bad (повторите: sudo bash $0 models)"
}

install_all() {
  command -v docker >/dev/null || die "нет docker"
  mkdir -p "$DIR"
  models
  cat > "$DIR/nginx.conf" <<'NGINX'
server {
    listen 8790;
    server_tokens off;
    access_log off;
    # Адрес снаружи — /mail/translate/… (раздел в Nginx Proxy Manager).
    location /mail/translate/ {
        alias /srv/;
        autoindex off;
        limit_except GET { deny all; }
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "public, max-age=604800" always;
        types { application/json json; text/plain txt; }
        default_type application/octet-stream;
    }
    location = /mail/translate/v1/index.json {
        alias /srv/v1/index.json;
        add_header X-Content-Type-Options nosniff always;
        add_header Cache-Control "no-cache" always;
        default_type application/json;
    }
    location = /healthz { return 200 "ok\n"; }
    location / { return 404; }
}
NGINX
  detect_network
  docker network inspect "$NPM_NETWORK" >/dev/null 2>&1 \
    || die "сеть Docker «$NPM_NETWORK» не найдена: NPM_NETWORK=ИМЯ bash $0 install (docker network ls)"
  ok "сеть Nginx Proxy Manager: $NPM_NETWORK"
  cat > "$DIR/docker-compose.translate.yml" <<YML
services:
  translate-models:
    image: $NGINX_IMAGE
    container_name: $CONTAINER
    expose:
      - "$PORT"
    volumes:
      - ./www:/srv:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    restart: always
    read_only: true
    tmpfs:
      - /var/cache/nginx
      - /var/run
      - /tmp
    security_opt:
      - no-new-privileges:true
    mem_limit: 128m
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:$PORT/healthz"]
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
networks:
  npm:
    external: true
    name: $NPM_NETWORK
YML
  (cd "$DIR" && docker compose -f docker-compose.translate.yml up -d) || die "контейнер не запущен"
  ok "контейнер $CONTAINER запущен"
  echo
  echo "  Дальше: раздел «location ^~ /mail/translate/» в Advanced хоста ogneliss.ru (README.md, шаг 2), затем:"
  echo "    sudo bash $0 check"
}

check() {
  docker exec "$CONTAINER" wget -qO- "http://127.0.0.1:$PORT/mail/translate/v1/index.json" >/dev/null 2>&1 \
    && ok "раздача отвечает в контейнере" || die "раздача не отвечает: docker logs $CONTAINER"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' 'https://ogneliss.ru/mail/translate/v1/index.json' || true)"
  case "$code" in
    200) ok "снаружи: index.json доступен" ;;
    *) warn "снаружи ответ $code — проверьте раздел /mail/translate/ в Nginx Proxy Manager (README.md, шаг 2)" ;;
  esac
  code="$(curl -s -o /dev/null -r 0-99 -w '%{http_code}' 'https://ogneliss.ru/mail/translate/v1/enru/vocab.enru.spm' || true)"
  case "$code" in
    200|206) ok "снаружи: файл модели скачивается" ;;
    *) warn "файл модели: ответ $code" ;;
  esac
}

case "${1:-}" in
  install) install_all ;;
  models) models ;;
  check) check ;;
  *) echo "Использование: sudo bash $0 install|models|check"; exit 1 ;;
esac
