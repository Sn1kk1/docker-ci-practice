# Практика 4 Миграция Mattermost

Проект переносит учебный Mattermost 9.5.14 с MySQL 8.0 на PostgreSQL 15 и обновляет сервер до 12.0.1. В Docker Desktop на Apple Silicon образы Mattermost и pgloader работают в режиме linux/amd64, базы используют нативные образы.

| Файл | Назначение |
| --- | --- |
| `legacy/docker-compose.yml` | Mattermost 9.5.14 и MySQL |
| `docker-compose.prod.yml` | Mattermost 12.0.1 и PostgreSQL |
| `scripts/migrate.sh` | Бэкап, перенос, обновление и проверки |
| `scripts/copy-staging.sql` | Сверка количества строк и перенос из промежуточной схемы |
| `scripts/demo.py` | Создание и проверка четырёх сообщений и вложения через API |
| `.github/workflows/migration.yml` | Запуск на self-hosted runner для ветки `migration` |

## Первый запуск на чистом стенде

Нужны Docker с Compose, Bash, curl, OpenSSL и Python 3. Выполняйте команды из корня проекта. Создайте `.env` один раз. Сохраните его для повторных запусков, так как смена значения в файле сама по себе не меняет пароль в уже созданной базе.

```bash
(umask 077; for var in DB_MYSQL_ROOT_PASSWORD DB_MYSQL_USER_PASSWORD DB_POSTGRES_PASSWORD MM_ADMIN_PASSWORD; do
  printf '%s=%s\n' "$var" "$(openssl rand -hex 24)"
done > .env)
docker compose --env-file .env -f legacy/docker-compose.yml up -d --wait
set -a; source ./.env; set +a
python3 scripts/demo.py seed
```

В браузере откройте <http://localhost:8065>. Логин `student@example.test`, пароль администратора хранится в `MM_ADMIN_PASSWORD` в локальном `.env`. В команде «Практика 4» откройте приватный канал «Проверка миграции».

## Два прогона локально

```bash
bash scripts/migrate.sh
python3 scripts/demo.py verify
bash scripts/migrate.sh
python3 scripts/demo.py verify
docker compose -f docker-compose.prod.yml ps
```

На первом прогоне исходное приложение останавливается, создаётся сжатый MySQL-дамп, данные переносятся во временную схему `mattermost` через pgloader с `include drop`. Проверенные данные попадают в штатную схему `public`. Она обновляется промежуточными версиями Mattermost. После проверки создаётся отметка в PostgreSQL и флаг-файл. Последний шаг обоих прогонов поднимает целевой стек с `--remove-orphans` и проверяет HTTP API. На втором прогоне ищите строку `Migration already completed. Skipping MySQL backup, pgloader, and schema upgrade.`

Бэкап `mysql-*.sql.gz` и `.migration_completed` лежат в соседнем каталоге `mm-practice4-state` либо в `MIGRATION_STATE_DIR`. Три тома Docker хранят данные обеих СУБД и пользовательские файлы. Не удаляйте их через `down -v`, если демонстрационный стенд нужен дальше. Для свежего прогона используйте отдельный чистый Docker-контекст или задайте новые значения COMPOSE_PROJECT_NAME, MM_PORT и MIGRATION_STATE_DIR. Передайте выбранный адрес через --url в demo.py.

## Проверка в GitHub Actions

1. Используйте закрытый репозиторий. В **Settings → Actions → Runners** подключите self-hosted runner, добавьте метку `mattermost-practice4` и проверьте доступ к тому Docker-контексту, где развернут исходный стенд. На сервере CI потребуется Docker Compose с `up --wait` и Bash.
2. В **Settings → Secrets and variables → Actions** заведите `DB_MYSQL_ROOT_PASSWORD`, `DB_MYSQL_USER_PASSWORD` и `DB_POSTGRES_PASSWORD`. Значения берутся из `.env` того стенда, который будет мигрировать. `MM_ADMIN_PASSWORD` нужен только для локального входа и проверки демоданных.
3. Сохраните файлы в ветке `migration`. Push в эту ветку запускает первый прогон. Для ручного **Run workflow** файл workflow также должен быть доступен в ветке по умолчанию. Для повторного прогона можно сделать **Re-run all jobs** из первого запуска.
4. В логах сравните шаг **Migrate or deploy**. На первом прогоне будут бэкап, pgloader и проверка данных. На втором прогоне перенос пропускается, HTTP-проверка снова возвращает `status: OK`. Откройте приватный канал на машине раннера и скачайте вложение.

Для отдельного CI-стенда на той же машине сначала разверните исходное приложение с новыми COMPOSE_PROJECT_NAME и MM_PORT. Затем внесите эти значения в репозиторий в **Settings → Secrets and variables → Actions → Variables** как MM_COMPOSE_PROJECT и MM_PORT. Для CI состояние остаётся в `$RUNNER_WORKSPACE/${COMPOSE_PROJECT_NAME}-state`. Оба запуска направляйте на один и тот же стенд. В комплекте нет локальных секретов и резервных копий.

## Документация

- [Mattermost Миграция с MySQL на PostgreSQL](https://docs.mattermost.com/administration-guide/manage/admin/postgres-migration)
- [Mattermost Подготовка к обновлению сервера](https://docs.mattermost.com/administration-guide/upgrade/prepare-to-upgrade-mattermost)
- [GitHub Добавление self-hosted runner](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)
- [GitHub Использование секретов в Actions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)
