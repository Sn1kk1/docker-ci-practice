# Практика 2. Docker и Docker Compose

Fullstack-приложение: Go API + статичный frontend + PostgreSQL.

```
project/
├── backend/          # Go API + multi-stage Dockerfile
├── frontend/         # index.html, app.js, style.css (запекаются в образ)
├── init/01_seed.sql  # создание таблицы и тестовые данные
├── docker-compose.yml
├── .env.example      # шаблон -> скопировать в .env
├── .dockerignore
└── .gitignore        # содержит .env
```

## Запуск

```bash
cp .env.example .env               # и задать DB_PASSWORD
docker compose config -q           # проверка файла
docker compose up -d --build
docker compose ps                  # app и db -> healthy
docker compose logs app            # "connected to database", "listening on :8080"
curl -s http://localhost:8080/api/items
# [{"id":1,"name":"first item"},{"id":2,"name":"second item"},{"id":3,"name":"third item"}]
```

Открыть в браузере: http://localhost:8080

## Проверки по чек-листу

```bash
docker images app-backend                       # размер ~10 МБ (< 30 МБ)
docker inspect -f '{{.Config.User}}' app-backend:1.0.0   # nonroot:nonroot
docker compose exec app sh                      # ошибка: shell в образе нет
docker compose port db 5432                     # пусто: порт БД наружу не проброшен
```

## Остановка

```bash
docker compose down          # контейнеры удалены, том db_data остаётся
docker compose down -v --rmi local   # удалить и том, и собранный образ
```

## Что и почему

| Критерий | Где реализовано |
|---|---|
| Multi-stage | `backend/Dockerfile`: `builder` (golang:1.22-alpine) → distroless, `COPY --from=builder` |
| Кэш слоёв | `COPY go.mod go.sum` + `go mod download` до `COPY backend/` |
| Non-root, без shell | `distroless/static-debian12:nonroot` + `USER nonroot:nonroot` |
| Fullstack | `/` — статика, `/api/items` — JSON из PostgreSQL |
| Compose | 2 сервиса, сети `frontend_net` / `backend_net (internal)`, у `db` нет `ports`, секреты из `.env` |
| Готовность | `healthcheck` с `pg_isready` + `condition: service_healthy`; плюс ретраи `db.Ping()` в приложении |
| Здоровье app | `HEALTHCHECK` вызывает сам бинарник (`/app/app healthcheck` → `GET /healthz`), т.к. curl/sh нет |
| Чистота | `.env` в `.gitignore`, образ `app-backend:1.0.0` вместо `latest`, комментарии «почему» |

---

# Практика 3. GitHub Actions + self-hosted runner

Workflow [.github/workflows/deploy.yml](.github/workflows/deploy.yml) на каждый push в `main`
(или вручную) на **своей машине** собирает `.env` из GitHub Secrets, поднимает стек через
Docker Compose, прогоняет тесты [tests/smoke.sh](tests/smoke.sh) и сохраняет артефакты.

```
push в main ─▶ self-hosted runner (этот Mac)
                ├─ .env из secrets.DB_USER / DB_PASSWORD / DB_NAME
                ├─ docker compose up -d --build --wait   (проект ci-app, порт 8081)
                ├─ проверка: все сервисы running
                ├─ tests/smoke.sh: приложение + БД, данные БД == веб-интерфейс
                ├─ отчёт в Summary + артефакт deployment-<run_id>
                └─ rm .env
```

## Настройка (один раз)

1. **Репозиторий.** Создать репозиторий на GitHub и запушить в него содержимое этой папки
   (корень репозитория = папка с `docker-compose.yml`).
2. **Секреты.** Settings → Secrets and variables → Actions → *New repository secret*:
   `DB_USER`, `DB_PASSWORD`, `DB_NAME`.
   В пароле не используйте `$` — Compose воспринимает его как подстановку переменной.
   Необязательно: на вкладке *Variables* — `APP_PORT` (по умолчанию 8081).
3. **Runner.** Settings → Actions → Runners → *New self-hosted runner* → macOS, ARM64.
   Выполнить в терминале команды со страницы (скачивание, `./config.sh --url … --token …`),
   затем запустить:
   ```bash
   ./run.sh
   ```
   В Settings → Actions → Runners runner должен стать **Idle** (зелёный, Online).
   Docker Desktop должен быть запущен.
4. **Запуск.** Сделать push в `main` или Actions → *Deploy and Test* → *Run workflow*.

## Что проверяют тесты

| Тест | Как |
|---|---|
| Веб-интерфейс отдаётся | `GET /` → 200 без редиректов, в HTML есть заголовок страницы |
| Frontend берёт данные из API | в `app.js` есть запрос к `/api/items` |
| Приложение подключено к БД | `GET /healthz` → `ok` (внутри — `db.Ping()`) |
| Количество записей совпадает | `SELECT` через `psql` в контейнере `db` vs `GET /api/items` |
| Содержимое совпадает | построчный `diff` строк `id\|name` из БД и из API |
| Данные живые | `INSERT` новой записи в БД → она появляется в `/api/items` → `DELETE` |

Локально (при поднятом стеке): `./tests/smoke.sh`.

## Артефакты (`deployment-<run_id>`, хранятся 30 дней)

- `test-results/test-report.md` — отчёт (то же на вкладке Summary запуска)
- `test-results/` — выгрузки БД и API, `diff.txt`, HTML главной страницы
- `logs/deployment-logs.txt` — логи контейнеров; `docker-ps.txt`, `docker-images.txt`
- `logs/env.masked` — `.env` без значений (сам `.env` с паролем не выгружается)
- `docker-compose.yml`

## Почему так

- **Секреты через `env:`, а не `${{ secrets.X }}` внутри скрипта** — значение не может сломать
  shell-команду; GitHub маскирует его в логах.
- **`--wait` вместо `sleep 30`** — шаг ждёт, пока сервисы станут healthy, ровно столько, сколько нужно.
- **`COMPOSE_PROJECT_NAME=ci-app` и порт 8081** — CI-стек не трогает стек, запущенный руками на 8080.
- **`concurrency`** — на одном runner'е два деплоя не идут одновременно.
- **`if: always()`** у отчёта, логов и артефактов — при падении тестов логи особенно нужны.
- **`docker compose`, а не `docker-compose`** — в методичке v1-синтаксис; в Docker Desktop
  есть только Compose v2.
