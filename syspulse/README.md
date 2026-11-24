# Практика 5 Сборка Debian пакета и публикация в Nexus

Учебный Nexus OSS 3.76.1 слушает только loopback. На Mac используется профиль Colima `practice5` с запуском Linux amd64 через Rosetta.

Ветка `release` запускает `.github/workflows/publish-deb.yml` на self-hosted раннере с меткой `syspulse-practice5`.

| Файл | Назначение |
|---|---|
| `main.go` | Код syspulse, чтение /proc, версия пакета |
| `debian/control.in` | Шаблон метаданных |
| `scripts/build.sh`, `scripts/package.sh` | Сборка для Linux amd64 и упаковка через dpkg-deb |
| `scripts/publish.sh` | HTTP POST в Nexus Components API |
| `scripts/verify.sh` | Установка в новом Ubuntu 22.04 из подписанного источника |
| `nexus/docker-compose.yml` | Контейнер Nexus и постоянный том |
| `scripts/configure-nexus.py` | Первичная настройка нового Nexus, роли и ключа |

Из каталога `syspulse` запусти `docker compose -f nexus/docker-compose.yml up -d`. Когда ответит `http://localhost:8081/service/rest/v1/status`, выполни `python3 scripts/configure-nexus.py`. Для этого нужны Python 3 и GnuPG. Скрипт предназначен для нового экземпляра Nexus. Пароли и приватный ключ хранятся в `nexus/private`, который исключён из Git. В Git хранится только публичный ключ `nexus/syspulse.asc`.

```bash
./scripts/build.sh
./scripts/package.sh
NEXUS_HOST=http://127.0.0.1:8081 NEXUS_USER=syspulse-deployer \
  NEXUS_PASSWORD="$(cat nexus/private/deployer.password)" \
  ./scripts/publish.sh dist/syspulse_1.2.0_amd64.deb
./scripts/verify.sh
```

В GitHub добавь `NEXUS_HOST`, `NEXUS_USER`, `NEXUS_PASSWORD` как Actions secrets. Если Docker использует отдельный контекст, задай его имя в Actions variable `SYSPULSE_DOCKER_CONTEXT`. Nexus и раннер должны быть доступны на одной машине. Убедись, что Docker запускает контейнеры `linux/amd64`.

В Actions открой запуск Build and publish syspulse. Пакет находится в **Artifacts → syspulse-deb**. В UI Nexus открой **Browse → syspulse**, чтобы показать опубликованную версию. Повторный запуск публикует пакет с той же версией благодаря политике Allow и каждый раз устанавливает его в новом контейнере.

Справка [Nexus APT](https://help.sonatype.com/en/apt-repositories.html) и [Components API](https://help.sonatype.com/en/components-api.html).
