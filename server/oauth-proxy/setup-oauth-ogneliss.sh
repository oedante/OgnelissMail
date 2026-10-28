#!/usr/bin/env bash
# =============================================================================
# Ogneliss — OAuth-прокси рядом с почтовым сервером (Docker + Nginx Proxy Manager).
#
# УСТАРЕЛО: оставлен для совместимости со старыми инструкциями. Раньше этот
# скрипт содержал внутри себя копию server.js — версию ДО аудита (без /exchange
# и PKCE). Запуск старой копии откатывал прокси, и новое приложение не могло
# войти через Google/Яндекс/Mail.ru/Yahoo.
#
# Теперь он просто вызывает install-oauth-proxy.sh в режиме docker.
# Копируйте на сервер всю папку server/oauth-proxy.
#
# Старые переменные поддерживаются: BASE_URL, DOMAIN, MAIL_DIR, NPM_NETWORK,
# SECRETS_FILE.
# =============================================================================
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/install-oauth-proxy.sh" ] || {
  echo "Нет $DIR/install-oauth-proxy.sh — скопируйте на сервер всю папку server/oauth-proxy." >&2
  exit 1
}
args=(install --mode docker)
if [ -n "${BASE_URL:-}" ]; then args+=(--base-url "$BASE_URL")
elif [ -n "${DOMAIN:-}" ]; then args+=(--base-url "https://$DOMAIN"); fi
[ -n "${SECRETS_FILE:-}" ] && args+=(--secrets "$SECRETS_FILE")
echo "setup-oauth-ogneliss.sh устарел — запускаю install-oauth-proxy.sh ${args[*]}" >&2
exec bash "$DIR/install-oauth-proxy.sh" "${args[@]}" "$@"
