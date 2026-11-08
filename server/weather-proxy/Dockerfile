# Погода «Моего дня» Ogneliss Mail — контейнер за Nginx Proxy Manager.
# Собирается установщиком install-weather-proxy.sh. Зависимостей нет.
FROM node:24-alpine
ENV NODE_ENV=production PORT=8789 HOST=0.0.0.0 DATA_DIR=/data BASE_PATH=/weather
WORKDIR /app
COPY --chown=node:node package.json server.js ./
USER node
EXPOSE 8789
CMD ["node", "server.js"]
