# syntax=docker/dockerfile:1
# Контекст сборки — корень проекта (см. docker-compose.yml), чтобы в образ
# можно было положить и бинарник backend, и статичный frontend.

# ---------- Этап 1: сборка ----------
# Тег с точной версией Go — сборка воспроизводима, а не "что сегодня в latest".
FROM golang:1.22-alpine AS builder
WORKDIR /build

# Сначала ТОЛЬКО файлы зависимостей: пока go.mod/go.sum не меняются,
# слой с `go mod download` берётся из кэша и модули не перекачиваются.
COPY backend/go.mod backend/go.sum ./
RUN go mod download

# Теперь исходники. Меняется код -> пересобираются только слои ниже этой строки.
COPY backend/ ./

# CGO_ENABLED=0 — статический бинарник: в distroless/static нет glibc.
# -ldflags="-s -w" вырезает отладочные символы -> бинарник и образ меньше.
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/app .

# ---------- Этап 2: исполнение ----------
# distroless/static: нет shell, apk/apt, компилятора. Даже взломав процесс,
# атакующему нечего запустить. Тег :nonroot — процесс работает под UID 65532.
FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /app

# Из builder берём только готовый бинарник — компилятор Go (~300 МБ) остаётся там.
COPY --from=builder /out/app /app/app
# Frontend запекаем в образ: образ самодостаточен и одинаково работает везде.
COPY frontend/ /app/static/

# Явно фиксируем non-root (дублирует базовый образ — но намерение видно в Dockerfile).
USER nonroot:nonroot

ENV HTTP_PORT=8080 \
    STATIC_DIR=/app/static

# EXPOSE — только документация; реальный проброс порта делает Compose (ports).
EXPOSE 8080

# Shell и curl нет, поэтому проверку делает сам бинарник (exec-форма, без sh).
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/app/app", "healthcheck"]

# ENTRYPOINT — "что запускать", CMD (пусто) — аргументы, которые легко переопределить.
ENTRYPOINT ["/app/app"]
