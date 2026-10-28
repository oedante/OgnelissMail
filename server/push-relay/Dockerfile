# «Будильник» Ogneliss Mail для iPhone — контейнер за Nginx Proxy Manager.
# Собирается установщиком install-push-relay.sh. Зависимостей нет.
FROM node:24-alpine
ENV NODE_ENV=production PORT=8788 HOST=0.0.0.0 DATA_FILE=/data/tokens.json
WORKDIR /app
COPY --chown=node:node package.json server.js ./
USER node
EXPOSE 8788
CMD ["node", "server.js"]
