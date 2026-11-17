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

Четыре сервиса в `docker-compose.yml`:

| Сервис | Роль |
| --- | --- |
| `app_proxy` | Обратный прокси umbrelOS. `PROXY_AUTH_ADD: "false"` — без этого TV-клиенты не смогут ходить в API |
| `init` | Одноразовый контейнер: создаёт каталоги, кладёт стартовый `init.conf` из образа, генерирует случайный root-пароль |
| `server` | Сам Lampac. Стартует после успешного завершения `init` |
| `cache-cleaner` | Раз в час чистит дисковый кэш TorrServer: по возрасту и при нехватке места (см. ниже) |

`init` нужен потому, что `init.conf` и `passwd` лежат в корне `/lampac` рядом с бинарниками —
их можно монтировать только пофайлово, а значит файлы должны существовать на хосте до старта.

### Данные

Всё лежит в `~/umbrel/app-data/asvata-lampac/data/`:

| Хост | Контейнер | Назначение |
| --- | --- | --- |
| `data/config/init.conf` | `/lampac/init.conf` → симлинк | Конфигурация (hot-reload, поверх `base.conf` из образа) |
| `data/config/passwd` | `/lampac/passwd` → симлинк | Root-пароль (WebLog и служебные функции) |
| `data/cache` | `/lampac/cache` | Кеш |
| `data/database` | `/lampac/database` | SQLite: Sync, TimeCode, SISI |
| `data/torrserver` | `/lampac/data/ts` | Бинарник TorrServer, его настройки, список «Мои торренты» и дисковый кэш (`cache/`) |
| `data/plugins` | `/lampac/plugins/override` | Переопределение клиентских плагинов |
| `data/mods` | `/lampac/mods` | Пользовательские модули |

Файлы создаются один раз и при обновлении приложения не перезаписываются.

`init.conf` и `passwd` подключены симлинками на примонтированный каталог `/data`, а не
bind-mount'ом отдельных файлов. Bind-mount файла привязан к inode, и любое атомарное
сохранение на хосте (`sed -i`, vim, VS Code — все они пишут временный файл и переименовывают
его поверх) подменяет inode: контейнер после этого читает старую версию, пока его не
пересоздадут. Через симлинк путь разрешается при каждом чтении, поэтому правки видны сразу
и любым редактором.

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
Исключение: список `BaseModule.SkipModules` применяется только при загрузке модулей,
после его правки приложение надо перезапустить.

Стартовый файл генерирует сервис `init` (см. `docker-compose.yml`), а не копирует из
`example.init.conf` образа — тот выключает `JacRed`, `TorrServer`, `Sync` и `TimeCode`,
из-за чего не работает поиск торрентов. Что включено в стартовом конфиге:

- `JacRed.typesearch: "jackett"` — Lampac сам парсит трекеры (Rutor, TorrentBy, Bitru,
  Selezen, Anilibria, Anifilm, BigFanGroup, NNMClub работают без аккаунтов; Kinozal,
  Rutracker, Toloka, Lostfilm, Animelayer требуют логин в `JacRed.Jackett.<трекер>.login`)
- `JacRed.disableJackett: false` — обязательно вместе с `typesearch: "jackett"`, иначе
  не работает получение магнет-ссылок (см. ниже)
- `TorrServer`, `Sync`, `TimeCode` — включены
- `DLNA` — выключен: в bridge-сети umbrelOS SSDP/multicast всё равно не работает
- `chromium.executablePath: /usr/bin/chromium` — Playwright для источников с JS-защитой

Два подвоха при правке:

- **Массивы в `init.conf` заменяют значения из `base.conf`, а не дополняют их.** Поэтому
  `SkipModules` перечислен целиком: удаление модуля из списка включает его, но и добавлять
  новый нужно в этот же список.
- **`JacRed` без `typesearch` возвращает текст `typesearch == null` вместо JSON**, и клиент
  показывает «Парсер не отвечает». Валидные значения: `jackett` (парсить самому),
  `webapi` (проксировать на внешний JacRed через `JacRed.webApiHost`), `red` (своя база).
- **`JacRed.disableJackett` по умолчанию `true`.** Модуль рассчитан на `typesearch: "webapi"`,
  где ссылки приходят от внешнего JacRed. Флаг не влияет на поиск, но выключает маршруты
  `/<трекер>/parsemagnet` — они отдают текстом `disable`. Трекеры, которые возвращают magnet
  напрямую (Rutor, TorrentBy), играют; те, что отдают `Link` на `parsemagnet` (NNMClub,
  BigFanGroup, Anifilm, Kinozal, Rutracker, Toloka, Bitru, Megapeer, Selezen, Lostfilm,
  Animelayer), падают с «Не удалось получить HASH».

Не меняйте `listen.port` — `app_proxy` ходит на `9118`.

Взрослый контент (модуль SISI) отключается добавлением `"SISI"` в `BaseModule.SkipModules`.

Полное описание параметров: [README Lampac](https://github.com/lampac-nextgen/lampac#конфигурация).

### Диагностика

Проверить, какие модули поднялись, можно по маршрутам — без SSH:

```bash
for p in /lampainit.js /online.js /ts.js /sisi.js /api/v1.0/conf; do \
  printf '%-20s %s\n' "$p" "$(curl -s -o /dev/null -w '%{http_code}' "http://umbrel.local:9118$p")"; done
```

`200` — модуль загружен, `404` — выключен в `SkipModules`. Соответствие:
`/api/v1.0/conf` → JacRed, `/ts.js` → TorrServer, `/online.js` → Online,
`/sisi.js` → SISI, `/timecode.js` → TimeCode, `/tracks.js` → Tracks.

Проверить сам парсер торрентов:

```bash
curl -s "http://umbrel.local:9118/api/v2.0/indexers/all/results?apikey=1&query=matrix" | head -c 300
```

| Ответ | Причина |
| --- | --- |
| `404` | JacRed в `SkipModules` |
| `typesearch == null` | не задан `JacRed.typesearch` |
| `apikey` | `JacRed.apikey` задан и не совпадает с ключом в настройках Lampa |
| JSON с `Results` | работает |

Если поиск находит раздачи, но при воспроизведении часть из них выдаёт «Не удалось получить
HASH» — проверьте `parsemagnet`. Возьмите поле `Link` из любого результата и запросите его:

```bash
curl -s "http://umbrel.local:9118/nnmclub/parsemagnet?id=1577522&apikey=1" | head -c 100
```

| Ответ | Причина |
| --- | --- |
| `disable` | `JacRed.disableJackett: true` (или трекер выключен в `JacRed.Jackett`) |
| `error` | трекер недоступен или требует логин |
| бинарный torrent / `magnet:?xt=` | работает |

Состояние встроенного TorrServer:

```bash
curl -s http://umbrel.local:9118/ts/echo                                          # версия
curl -s -X POST -d '{"action":"list"}' http://umbrel.local:9118/ts/torrents       # список
```

Если `parsemagnet` снаружи отдаёт торрент, а «HASH» всё равно не появляется — проверьте,
резолвится ли имя внутри контейнера. По ссылке ходит TorrServer, а он живёт подпроцессом
внутри контейнера Lampac:

```bash
sudo docker exec asvata-lampac_server_1 getent hosts umbrel.local
```

Пусто — имя недоступно. `umbrel.local` существует только в mDNS, а в образе нет ни avahi,
ни nss-mdns. Compose лечит это записью `extra_hosts: umbrel.local:127.0.0.1` — имя
заворачивается на сам контейнер, где Lampac и слушает 9118. Если устройство переименовано,
поправьте `extra_hosts` под своё имя либо задайте в `init.conf` явный адрес, от которого
Lampac будет строить все ссылки:

```json
"listen": { "ip": "0.0.0.0", "port": 9118, "scheme": "http", "host": "192.168.1.36:9118" }
```

Второй вариант заодно помогает телевизорам: Tizen и webOS обычно тоже не умеют `.local`.
Цена — IP зашит в конфиг, так что закрепите адрес в DHCP.

### Починить уже установленный экземпляр

Сервис `init` не перезаписывает существующий `init.conf`, поэтому на установке, сделанной
до этого исправления, конфиг надо заменить вручную (по SSH на umbrelOS):

```bash
cat > ~/umbrel/app-data/asvata-lampac/data/config/init.conf <<'CONF'
{
  "listen": { "ip": "0.0.0.0", "port": 9118, "scheme": "http" },
  "BaseModule": {
    "SkipModules": [
      "CacheMedia", "Catalog", "DLNA", "ForkPlayerXML", "MsxNative", "Potok",
      "TelegramAuth", "TelegramAuthBot", "Tracks", "Transcoding", "WebLog"
    ]
  },
  "chromium": { "enable": true, "executablePath": "/usr/bin/chromium" },
  "JacRed": { "typesearch": "jackett", "disableJackett": false },
  "online": { "name": "Lampac", "spiderName": "Lampac" }
}
CONF
sudo umbreld client apps.restart.mutate --appId asvata-lampac
```

Если `umbreld` не отвечает — перезапустите приложение из UI umbrelOS (меню приложения → Restart).

### Дисковый кэш TorrServer

По умолчанию TorrServer держит кэш в памяти, и при просмотре 4K буфера хватает на секунды:
стоит пирам притормозить — видео встаёт. С дисковым кэшем буфер вперёд измеряется гигабайтами,
всё просмотренное остаётся на диске, и при повторном открытии берётся оттуда.

Включается настройками самого TorrServer, они хранятся в его `config.db` на томе
`data/torrserver` и переживают рестарт и обновление:

```bash
C=asvata-lampac_server_1
P=$(sudo docker exec $C sed -E 's/.*"ts":"([^"]+)".*/\1/' /lampac/data/ts/accs.db)
sudo docker exec $C mkdir -p /lampac/data/ts/cache
sudo docker exec $C curl -s -u ts:$P -X POST -d '{"action":"get"}' http://127.0.0.1:9085/settings > ~/ts-settings-before-disk.json
python3 -c '
import json; s=json.load(open("/home/umbrel/ts-settings-before-disk.json"))
s.update(UseDisk=True, TorrentsSavePath="/lampac/data/ts/cache", CacheSize=64*1024**3,
         ReaderReadAHead=5, RemoveCacheOnDrop=False)
print(json.dumps({"action":"set","sets":s}))' | sudo docker exec -i $C curl -s -u ts:$P -X POST --data-binary @- http://127.0.0.1:9085/settings
```

`CacheSize` — лимит **на одну раздачу**, 64 ГБ покрывают почти любой фильм. Откатить можно,
отправив обратно сохранённый `~/ts-settings-before-disk.json` тем же `set`. Удаление раздачи
из «Моих торрентов» стирает и её кэш.

**`ReaderReadAHead` с дисковым кэшем обязательно уменьшать.** Окно загрузки вперёд — это
`CacheSize × ReaderReadAHead%`, и всё, что в него попадает, движок качает в обычном
торрент-порядке (сначала редкие куски), а приоритеты у позиции плеера держит лишь на
`ConnectionsLimit` кусков вперёд и вообще не ставит в первых 8–16 МБ файла
([`cache.go`](https://github.com/YouROK/TorrServer/blob/master/server/torr/storage/torrstor/cache.go)).
Замеры на 4K-раздаче, кэш 64 ГБ:

| `ReaderReadAHead` | Окно вперёд | Старт, первые 40 МБ | Дальше |
| --- | --- | --- | --- |
| 95% (умолчание) | ~61 ГБ | 20 МБ за 120 с — плеер голодает | — |
| **5%** (минимум) | ~3.2 ГБ | 40 МБ за 28 с, включая получение метаданных | 7 МБ/с |

3.2 ГБ вперёд — это около 17 минут 4K WEB-DL (25 Мбит/с) или 5 минут UHD-ремукса.
Остальные 95% кэша держат уже просмотренное, так что перемотка назад и пересмотр идут с диска.

Сам TorrServer по времени кэш не чистит, поэтому это делает сервис `cache-cleaner`:

- удаляет раздачи, в которые ничего не докачивалось `KEEP_DAYS` дней (по умолчанию 7);
  возраст считается от последней записи — просмотр уже скачанного его не продлевает;
- если на диске свободно меньше `MIN_FREE_GB` (по умолчанию 50), удаляет самые старые
  раздачи, пока место не освободится — кэш лежит на системном диске umbrelOS.

Оба порога задаются в `environment` сервиса. Таймер на хосте вместо сервиса не годится:
корень umbrelOS — overlay Rugix, `/etc` сбрасывается при обновлении ОС, а `crontab` там нет.

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

Если меняется только упаковка, а не Lampac, добавьте к версии ревизию: `1.83.1-1`, `1.83.1-2`.
umbrelOS сравнивает `version` как строку, обновлением считается любое отличие
([`routes.ts`](https://github.com/getumbrel/umbrel/blob/master/packages/umbreld/source/modules/apps/routes.ts)),
а обновление в отличие от переустановки сохраняет `app-data`.

## Лицензии

Содержимое этого репозитория — конфигурация магазина. Lampac NextGen распространяется
по [AGPL-3.0](https://github.com/lampac-nextgen/lampac/blob/main/LICENSE).
