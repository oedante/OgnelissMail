# OAuth-прокси Ogneliss Mail — контейнер для работы за Nginx Proxy Manager.
# Собирается установщиком install-oauth-proxy.sh (вариант docker).
FROM node:24-alpine
ENV NODE_ENV=production PORT=8787 HOST=0.0.0.0
WORKDIR /app
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force
# --chown: файлы читаются пользователем node при любых правах на хосте.
COPY --chown=node:node server.js ./
USER node
EXPOSE 8787
CMD ["node", "server.js"]
