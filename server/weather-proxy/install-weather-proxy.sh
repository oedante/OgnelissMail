#!/usr/bin/env bash
# Установка прокси погоды Ogneliss Mail рядом с push-relay (Docker, сеть
# Nginx Proxy Manager). Запуск от root:
#   sudo bash install-weather-proxy.sh install   — установить или обновить
#   sudo bash install-weather-proxy.sh cities    — обновить список городов
#                                                  (PLACE_COUNTRIES="RU KZ" — все
#                                                  населённые пункты этих стран)
#   sudo bash install-weather-proxy.sh check     — проверить
# Подробно — README.md рядом.
set -euo pipefail

DIR="${DIR:-/opt/mailserver/weather-proxy}"
CONTAINER="weather-proxy"
PORT=8789
NPM_NETWORK="${NPM_NETWORK:-}"
GEONAMES="https://download.geonames.org/export/dump"
SRC="$(cd "$(dirname "$0")" && pwd)"

ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

detect_network() {
  [ -n "$NPM_NETWORK" ] && return 0
  local n
  for c in push-relay proxy-manager oauth-proxy; do
    n="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$c" 2>/dev/null | awk '{print $1}')"
    [ -n "$n" ] && { NPM_NETWORK="$n"; return 0; }
  done
  NPM_NETWORK="mailserver_default"
}

# Страны, по которым нужны ВСЕ населённые пункты и аэропорты (а не только
# города от 1000 жителей): вахтовые посёлки, сёла. 18.11.2026: «Сабетта»
# (Ямал) не находилась. Через пробел: PLACE_COUNTRIES="RU KZ BY".
PLACE_COUNTRIES="${PLACE_COUNTRIES:-RU}"

cities() {
  mkdir -p "$DIR/data"
  local tmp; tmp="$(mktemp -d)"
  # GeoNames, CC BY 4.0: города от 1000 жителей, названия областей и стран.
  curl -fsSL -o "$tmp/cities1000.zip" "$GEONAMES/cities1000.zip" || die "не скачан cities1000.zip"
  curl -fsSL -o "$tmp/admin1CodesASCII.txt" "$GEONAMES/admin1CodesASCII.txt" || die "не скачан admin1CodesASCII.txt"
  curl -fsSL -o "$tmp/countryInfo.txt" "$GEONAMES/countryInfo.txt" || die "не скачан countryInfo.txt"
  (cd "$tmp" && unzip -o -q cities1000.zip cities1000.txt) || die "не распакован cities1000.zip (нужен unzip)"
  # Все населённые пункты (класс P, кроме исторических, заброшенных,
  # разрушенных и частей других) и аэропорты страны — из её выгрузки.
  local cc
  for cc in $PLACE_COUNTRIES; do
    curl -fsSL -o "$tmp/$cc.zip" "$GEONAMES/$cc.zip" || die "не скачан $cc.zip"
    unzip -p "$tmp/$cc.zip" "$cc.txt" \
      | awk -F'\t' '($7 == "P" && $8 !~ /^(PPLH|PPLQ|PPLW|PPLX|PPLCH)$/) || $8 == "AIRP"' \
      > "$tmp/places-$cc.txt" || die "не разобран $cc.zip"
    rm -f "$tmp/$cc.zip"
  done
  rm -f "$DIR/data/cities15000.txt" "$DIR/data"/places-*.txt
  install -m 0644 "$tmp/cities1000.txt" "$tmp/admin1CodesASCII.txt" "$tmp/countryInfo.txt" "$DIR/data/"
  for cc in $PLACE_COUNTRIES; do install -m 0644 "$tmp/places-$cc.txt" "$DIR/data/"; done
  rm -rf "$tmp"
  ok "города GeoNames от 1000 жителей: $(wc -l < "$DIR/data/cities1000.txt") строк"
  for cc in $PLACE_COUNTRIES; do ok "населённые пункты и аэропорты $cc: $(wc -l < "$DIR/data/places-$cc.txt") строк"; done
}

install_all() {
  command -v docker >/dev/null || die "нет docker"
  mkdir -p "$DIR"
  install -m 0644 "$SRC/server.js" "$SRC/bimi.js" "$SRC/package.json" "$SRC/Dockerfile" "$DIR/"
  [ -s "$DIR/data/cities1000.txt" ] || cities
  detect_network
  docker network inspect "$NPM_NETWORK" >/dev/null 2>&1 \
    || die "сеть Docker «$NPM_NETWORK» не найдена: NPM_NETWORK=ИМЯ bash $0 install (docker network ls)"
  ok "сеть Nginx Proxy Manager: $NPM_NETWORK"
  cat > "$DIR/docker-compose.weather.yml" <<YML
services:
  weather-proxy:
    build: .
    image: ogneliss/weather-proxy:latest
    container_name: $CONTAINER
    environment:
      - HOST=0.0.0.0
      - PORT=$PORT
      - BASE_PATH=/weather
      - DATA_DIR=/data
      # Мест — сотни тысяч (2.6.4). Куча — 160 МБ (24.11.2026: со списком
      # часовых поясов 128 МБ не хватило, служба падала при запуске; столбцы
      # мест теперь вне кучи, нужно ~100 МБ — остальное запас). Процесс —
      # до ~250 МБ из 320.
      - NODE_OPTIONS=--max-old-space-size=160
    expose:
      - "$PORT"
    volumes:
      - ./data:/data:ro
    restart: always
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    mem_limit: 320m
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://127.0.0.1:$PORT/weather/healthz"]
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
  (cd "$DIR" && docker compose -f docker-compose.weather.yml up -d --build) || die "контейнер не запущен"
  ok "контейнер $CONTAINER запущен"
  echo
  echo "  Дальше: раздел «location ^~ /weather/» в Advanced хоста ogneliss.ru (README.md, шаг 2), затем:"
  echo "    sudo bash $0 check"
}

check() {
  docker exec "$CONTAINER" wget -qO- "http://127.0.0.1:$PORT/weather/healthz" >/dev/null 2>&1 \
    && ok "служба отвечает в контейнере" || die "служба не отвечает: docker logs $CONTAINER"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' 'https://www.ogneliss.ru/weather/search?q=Moscow' || true)"
  case "$code" in
    200) ok "снаружи: поиск города работает" ;;
    *) warn "снаружи ответ $code — проверьте раздел /weather/ в Nginx Proxy Manager (README.md, шаг 2)" ;;
  esac
  if curl -s 'https://www.ogneliss.ru/weather/search?q=Sabetta' | grep -q 'Sabetta'; then
    ok "снаружи: находятся и посёлки (Sabetta)"
  else
    warn "Sabetta не находится — обновите список мест: sudo bash $0 cities"
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' 'https://www.ogneliss.ru/weather/forecast?lat=55.75&lon=37.62' || true)"
  [ "$code" = 200 ] && ok "снаружи: прогноз MET Norway получен" || warn "прогноз: ответ $code (docker logs $CONTAINER)"
}

case "${1:-}" in
  install) install_all ;;
  cities) cities; docker restart "$CONTAINER" >/dev/null 2>&1 && ok "служба перезапущена" || true ;;
  check) check ;;
  *) echo "Использование: sudo bash $0 install|cities|check"; exit 1 ;;
esac
