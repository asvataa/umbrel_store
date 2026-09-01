# Asvata — Umbrel Community App Store

Собственный магазин приложений для [umbrelOS](https://umbrel.com). Позволяет ставить приложения,
которых нет в [официальном каталоге](https://github.com/getumbrel/umbrel-apps).

Сейчас в магазине одно приложение — **[Lampac NextGen](https://github.com/lampac-nextgen/lampac)**,
backend-сервер для медиаприложения [Lampa](https://github.com/yumata/lampa).

## Установка

1. Запушьте этот репозиторий на GitHub (публичный).
2. В umbrelOS откройте **App Store → ⋮ (три точки справа вверху) → Community App Stores**.
3. Вставьте URL репозитория, например `https://github.com/<ваш-аккаунт>/umbrel_store`, и нажмите **Add**.
4. Магазин «Asvata» появится в списке — установите оттуда **Lampac**.

## Структура

```
umbrel-app-store.yml        id и название магазина
asvata-lampac/
├── umbrel-app.yml          карточка приложения для UI umbrelOS
└── docker-compose.yml      сервисы: app_proxy, init, server
scripts/update-lampac.sh    обновление версии образа и digest
```

ID приложения обязан начинаться с ID магазина, поэтому папка называется `asvata-lampac`.

### Переименовать магазин

Смените `id`/`name` в `umbrel-app-store.yml`, переименуйте папку и поправьте `id` в
`umbrel-app.yml` и `APP_HOST` в `docker-compose.yml`. Одной командой (пример — `mystore`):

```bash
NEW=mystore; sed -i '' "s/asvata/$NEW/g" umbrel-app-store.yml asvata-lampac/*.yml && sed -i '' "s/\"Asvata\"/\"Mystore\"/" umbrel-app-store.yml && git mv asvata-lampac "$NEW-lampac"
```

## Как устроено приложение Lampac

Образ: `ghcr.io/lampac-nextgen/lampac` (linux/amd64 + linux/arm64), пин по digest.
Рабочий каталог в контейнере — `/lampac`, порт — `9118`.

Три сервиса в `docker-compose.yml`:

| Сервис | Роль |
| --- | --- |
| `app_proxy` | Обратный прокси umbrelOS. `PROXY_AUTH_ADD: "false"` — без этого TV-клиенты не смогут ходить в API |
| `init` | Одноразовый контейнер: создаёт каталоги, кладёт стартовый `init.conf` из образа, генерирует случайный root-пароль |
| `server` | Сам Lampac. Стартует после успешного завершения `init` |

`init` нужен потому, что `init.conf` и `passwd` лежат в корне `/lampac` рядом с бинарниками —
их можно монтировать только пофайлово, а значит файлы должны существовать на хосте до старта.

### Данные

Всё лежит в `~/umbrel/app-data/asvata-lampac/data/`:

| Хост | Контейнер | Назначение |
| --- | --- | --- |
| `data/config/init.conf` | `/lampac/init.conf` | Конфигурация (hot-reload, поверх `base.conf` из образа) |
| `data/config/passwd` | `/lampac/passwd` | Root-пароль (WebLog и служебные функции) |
| `data/cache` | `/lampac/cache` | Кеш |
| `data/database` | `/lampac/database` | SQLite: Sync, TimeCode, SISI |
| `data/plugins` | `/lampac/plugins/override` | Переопределение клиентских плагинов |
| `data/mods` | `/lampac/mods` | Пользовательские модули |

Файлы создаются один раз и при обновлении приложения не перезаписываются.

### Root-пароль

Генерируется случайно при первой установке:

```bash
cat ~/umbrel/app-data/asvata-lampac/data/config/passwd
```

Сменить — записать новое значение в тот же файл (одной строкой, без перевода строки) и перезапустить приложение:

```bash
printf '%s' 'новый_пароль' > ~/umbrel/app-data/asvata-lampac/data/config/passwd
```

### Настройка

Правьте `data/config/init.conf` — Lampac перечитывает его на лету, перезапуск не нужен.
Стартовый файл копируется из `example.init.conf` образа; в нём по умолчанию отключены
`DLNA`, `JacRed`, `Sync`, `TimeCode`, `TorrServer`, `Tracks`, `Transcoding`, `WebLog` —
уберите ненужные строки из `BaseModule.SkipModules`, чтобы их включить.

Не меняйте `listen.port` — `app_proxy` ходит на `9118`.

Полное описание параметров: [README Lampac](https://github.com/lampac-nextgen/lampac#конфигурация).

### Порты

Наружу проброшен только `9118` (через `app_proxy`). Если понадобятся отдельные порты
TorrServer или DLNA/UPnP — добавьте их в секцию `ports` сервиса `server`.

## Безопасность

Прокси-аутентификация umbrelOS отключена, иначе Lampa на Android TV / Tizen / webOS не сможет
обращаться к API. В локальной сети приложение доступно без пароля umbrelOS — ограничивайте
доступ через `accsdb` и `WAF` в `init.conf` и не пробрасывайте порт в интернет без необходимости.

## Обновление версии Lampac

```bash
./scripts/update-lampac.sh          # до последнего релиза
./scripts/update-lampac.sh 1.53.0   # до конкретной версии
```

Скрипт подставит новый тег и digest в `docker-compose.yml` и версию в `umbrel-app.yml`.
После этого закоммитьте и запушьте — umbrelOS предложит обновление.

## Лицензии

Содержимое этого репозитория — конфигурация магазина. Lampac NextGen распространяется
по [MIT](https://github.com/lampac-nextgen/lampac/blob/main/LICENSE).
