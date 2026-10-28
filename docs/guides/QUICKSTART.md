# Ogneliss Mail — запуск по шагам: сервер и Android Studio

Папка проекта на компьютере: `C:\dev\ogneliss-mail` (если она в другом месте —
подставьте свой путь; в пути не должно быть пробелов и кириллицы).
Сервер: `217.114.43.126` (Debian 11, почта и Nginx Proxy Manager в Docker).

---

## Часть 1. Сервер: обновить OAuth-прокси

### 1.1. Скопировать папку прокси на сервер

На компьютере, в PowerShell (не в Android Studio — можно и там, разницы нет):

```powershell
scp -r C:\dev\ogneliss-mail\server\oauth-proxy root@217.114.43.126:/root/
```

Копируется вся папка `oauth-proxy`: скрипту нужны `server.js`, `package.json`,
`package-lock.json`, `Dockerfile` рядом с ним.

### 1.2. Войти на сервер

```powershell
ssh root@217.114.43.126
```

Дальше все команды — на сервере. Если вы вошли не под `root`, добавляйте
`sudo` перед `bash` и `nano`.

```bash
cd /root/oauth-proxy
sed -i 's/\r$//' *.sh          # на случай, если файлы прошли через Windows с CRLF
```

### 1.3. Поправить настройки прокси

```bash
nano /opt/mailserver/oauth-proxy/.env
```

1. **Удалите три строки** `PROXY_API_KEY=…`, `STATE_SECRET=…`, `ENC_SECRET=…` —
   их значения были в переписке; скрипт создаст новые.
2. Строка адресов возврата должна быть такой:
   ```
   ALLOWED_REDIRECTS=com.ogneliss.mail://oauth,com.ogneliss.mail:/oauth2redirect
   ```
3. Впишите клиентов провайдеров (значения — из консолей; без кавычек):
   ```
   GOOGLE_CLIENT_ID=…
   GOOGLE_CLIENT_SECRET=…
   YANDEX_CLIENT_ID=…
   YANDEX_CLIENT_SECRET=…
   MAILRU_CLIENT_ID=…
   MAILRU_CLIENT_SECRET=…
   ```
   Пустые пары можно оставить — эти провайдеры будут «не настроены».

Сохранить: `Ctrl+O`, `Enter`; выйти: `Ctrl+X`.

### 1.4. Обновить прокси

```bash
bash install-oauth-proxy.sh update --base-url https://www.ogneliss.ru/oauth
```

На вопрос «Продолжить?» — `Y`. Скрипт сохранит копию старых файлов в
`/opt/mailserver/oauth-proxy/backup-…`, создаст новые секреты, обновит код
прокси, пересоберёт и перезапустит контейнер `oauth-proxy`.

### 1.5. Nginx Proxy Manager: путь /oauth на www.ogneliss.ru

Один раз, в браузере: `http://217.114.43.126:81`

1. **Hosts → Proxy Hosts** → строка `www.ogneliss.ru` → ⋮ → **Edit**.
2. Вкладка **Custom locations** → **Add location**:
   - Define location: `/oauth`
   - Scheme: `http`
   - Forward Hostname / IP: `oauth-proxy`
   - Forward Port: `8787`
3. **Save**.

### 1.6. Проверить

```bash
bash install-oauth-proxy.sh check
```

Все строки должны быть с ✓, провайдеры, которые вы заполнили, — «настроен».
Если «снаружи не отвечает» — проверьте шаг 1.5.

Если после правки в Nginx Proxy Manager перестали открываться **все** сайты и
панель на порту 81 — значит, nginx не запускается из-за ошибки в одном из
хостов. Причина видна в журнале:

```bash
docker logs --tail 5 proxy-manager 2>&1
```

Типичная строка: `host not found in upstream "имя" in /data/nginx/proxy_host/N.conf`
— хост ссылается на остановленный контейнер. Запустите его
(`docker start имя`, и чтобы не повторялось:
`docker update --restart unless-stopped имя`) либо уберите этот путь в панели.

### 1.7. Взять ключ для сборки приложения

```bash
bash install-oauth-proxy.sh key
```

Скопируйте выведенный JSON (вместе с фигурными скобками) — он нужен в части 2,
шаг 2.3. Не пересылайте его в мессенджерах и почте.

### 1.8. Консоли провайдеров

В Google (тип клиента **«Веб-приложение»**), Яндексе и Mail.ru
redirect_uri: `https://www.ogneliss.ru/oauth/callback`.
Client secret Yahoo и Mail.ru перевыпустите.

Выход с сервера: `exit`.

---

## Часть 2. Android Studio

Один раз должны быть установлены: Android Studio с плагинами Flutter и Dart,
Flutter SDK, Visual Studio 2022 с «Разработкой классических приложений на C++»,
режим разработчика Windows, NuGet (подробно — `ANDROID_STUDIO.md`, раздел 1).

### 2.1. Открыть проект

File → Open → `C:\dev\ogneliss-mail`. Терминал: **View → Tool Windows →
Terminal** (или `Alt+F12`). Все команды ниже — в нём.

```powershell
cd C:\dev\ogneliss-mail
flutter doctor
```

Нужны зелёные строки Flutter, Windows Version, Visual Studio. Для Android ещё
Android toolchain (если ругается на лицензии: `flutter doctor --android-licenses`).

### 2.2. Подготовка проекта

Первый раз и после каждой замены файлов из нового архива:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -Platforms "android,windows"
```

5–10 минут: пакеты, код базы данных, иконки, папка `windows\`,
файл `config\dart_defines.json`.

### 2.3. Ключ прокси и адрес поддержки

Откройте в Android Studio `config\dart_defines.json` и вставьте JSON из шага
1.7, добавив адрес поддержки:

```json
{
  "OAUTH_PROXY_URL": "https://www.ogneliss.ru/oauth",
  "OAUTH_PROXY_KEY": "<ключ из шага 1.7>",
  "SUPPORT_EMAIL": "<адрес ИТ-поддержки>"
}
```

Файл в архив и в git не попадает; `setup.ps1` вписанное не затирает.

### 2.4. Проверка кода

```powershell
flutter analyze
flutter test
```

### 2.5. Запуск под Windows

```powershell
flutter run -d windows --dart-define-from-file=config/dart_defines.json
```

Или мышью: устройство **Windows (desktop)**, конфигурация
**Ogneliss Mail (debug)**, ▶. В терминале во время работы: `r` — применить
изменения кода, `R` — перезапуск, `q` — выход.

### 2.6. Запуск на эмуляторе Android (по желанию)

Эмулятор создаётся один раз: Device Manager → + → Pixel 8 → API 35.

```powershell
flutter emulators                                  # список, видно имя эмулятора
flutter emulators --launch Pixel_8_API_35          # имя из списка выше
flutter devices                                    # id запущенного, обычно emulator-5554
flutter run -d emulator-5554 --dart-define-from-file=config/dart_defines.json
```

### 2.7. Если что-то не так

Журнал приложения: Настройки → Журнал (или «Журнал для поддержки» под ошибкой
входа) → «Сохранить журнал» — и пришлите файл.

### 2.8. Для Google Play (когда понадобится)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\create_upload_key.ps1
flutter build appbundle --release --dart-define-from-file=config/dart_defines.json
```

Перед каждой загрузкой увеличьте число после `+` в `version:` в `pubspec.yaml`.
Подробно — `ANDROID_STUDIO.md`, разделы 7–9.

---

## Обновление проекта из нового архива

1. Распакуйте архив во временную папку — внутри будет `ogneliss-mail`.
2. Скопируйте её содержимое поверх `C:\dev\ogneliss-mail` с заменой.
   `config\dart_defines.json` и `android\key.properties` в архиве нет —
   ваши файлы останутся.
3. Шаг 2.2 (`setup.ps1`), затем запуск.
