#!/usr/bin/env bash
# Тесты поднятого стека: приложение отвечает, БД подключена,
# и данные в веб-интерфейсе (/api/items, который рисует frontend) совпадают с БД.
# Запуск из корня проекта после `docker compose up`:  ./tests/smoke.sh
set -euo pipefail

# Настройки берём из того же .env, по которому поднят стек
set -a; source .env; set +a
BASE_URL="http://localhost:${APP_PORT:-8080}"
OUT=test-results
mkdir -p "$OUT"

pass=0; fail=0
ok()  { echo "PASS  $1"; echo "| $1 | PASS |" >> "$OUT/results.md"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; echo "| $1 | FAIL |" >> "$OUT/results.md"; fail=$((fail + 1)); }

# psql внутри контейнера db: -A без выравнивания, -t без заголовков
psql_db() {
  docker compose exec -T db psql -U "$DB_USER" -d "$DB_NAME" -At -v ON_ERROR_STOP=1 -c "$1"
}

printf '| Тест | Результат |\n| --- | --- |\n' > "$OUT/results.md"

# --- 1. Приложение и подключение к БД ---------------------------------------

# Главная страница отдаётся сразу с 200, без редиректов (ловит баг с циклом 301)
code=$(curl -s -o "$OUT/index.html" -w '%{http_code}' "$BASE_URL/")
if [ "$code" = "200" ] && grep -q 'Items из PostgreSQL' "$OUT/index.html"; then
  ok "GET / отдаёт веб-интерфейс (HTTP $code)"
else
  bad "GET / отдаёт веб-интерфейс (HTTP $code)"
fi

# Frontend действительно берёт данные из /api/items — значит API и есть то, что видит пользователь
if curl -sf "$BASE_URL/app.js" | grep -q "/api/items"; then
  ok "Веб-интерфейс загружает данные из /api/items"
else
  bad "Веб-интерфейс загружает данные из /api/items"
fi

# /healthz пингует БД из приложения: 200 = приложение живо И видит базу
if [ "$(curl -s "$BASE_URL/healthz")" = "ok" ]; then
  ok "GET /healthz: приложение подключено к БД"
else
  bad "GET /healthz: приложение подключено к БД"
fi

# --- 2. Сравнение данных БД и веб-интерфейса --------------------------------

# Одинаковый формат с двух сторон: строка "id|name" на запись, по возрастанию id
psql_db "SELECT id || '|' || name FROM items ORDER BY id" > "$OUT/db_items.txt"
curl -sf "$BASE_URL/api/items" > "$OUT/api_items.json"
jq -r '.[] | "\(.id)|\(.name)"' "$OUT/api_items.json" > "$OUT/web_items.txt"

db_count=$(wc -l < "$OUT/db_items.txt" | tr -d ' ')
web_count=$(wc -l < "$OUT/web_items.txt" | tr -d ' ')
echo "Записей в БД: $db_count, в веб-интерфейсе: $web_count"

if [ "$db_count" -gt 0 ] && [ "$db_count" = "$web_count" ]; then
  ok "Количество записей совпадает ($db_count)"
else
  bad "Количество записей совпадает (БД $db_count, веб $web_count)"
fi

if diff -u "$OUT/db_items.txt" "$OUT/web_items.txt" > "$OUT/diff.txt"; then
  ok "Содержимое записей совпадает построчно"
else
  bad "Содержимое записей совпадает построчно (см. diff.txt)"
fi

# Живая проверка: новая запись в БД сразу видна в веб-интерфейсе (данные не "зашиты")
marker="ci-check-${GITHUB_RUN_ID:-local}-$$"
new_id=$(psql_db "INSERT INTO items (name) VALUES ('$marker') RETURNING id" | head -1)
if curl -sf "$BASE_URL/api/items" | jq -e --arg m "$marker" 'any(.[]; .name == $m)' > /dev/null; then
  ok "Новая запись из БД появилась в веб-интерфейсе (id $new_id)"
else
  bad "Новая запись из БД появилась в веб-интерфейсе (id $new_id)"
fi
psql_db "DELETE FROM items WHERE id = $new_id" > /dev/null

# --- Итог -------------------------------------------------------------------
{
  echo
  echo "Записей в БД: $db_count, в веб-интерфейсе: $web_count"
  echo
  echo "Итого: $pass passed, $fail failed"
} >> "$OUT/results.md"

echo "Итого: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
