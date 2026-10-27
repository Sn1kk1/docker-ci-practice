// backend/main.go — Go API + раздача статичного frontend.
package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
)

type Item struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
}

func main() {
	// В distroless нет shell/curl, поэтому HEALTHCHECK вызывает сам бинарник:
	// `app healthcheck` делает GET /healthz и возвращает код выхода 0/1.
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		os.Exit(healthcheck())
	}

	// Параметры подключения берутся из окружения (их задаёт Compose из .env)
	dsn := "host=" + env("DB_HOST", "db") +
		" port=" + env("DB_PORT", "5432") +
		" user=" + env("DB_USER", "app") +
		" password=" + env("DB_PASSWORD", "secret") +
		" dbname=" + env("DB_NAME", "appdb") +
		" sslmode=disable"

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// sql.Open не подключается к БД. Второй рубеж после healthcheck в Compose:
	// ждём БД с ретраями, чтобы приложение не падало, если запущено раньше неё.
	waitForDB(db, 30, 2*time.Second)

	staticDir := env("STATIC_DIR", "/app/static")
	fs := http.FileServer(http.Dir(staticDir))

	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if err := db.PingContext(r.Context()); err != nil {
			http.Error(w, "db unavailable", http.StatusServiceUnavailable)
			return
		}
		w.Write([]byte("ok"))
	})

	http.HandleFunc("/api/items", func(w http.ResponseWriter, r *http.Request) {
		rows, err := db.Query(`SELECT id, name FROM items ORDER BY id`)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		items := []Item{}
		for rows.Next() {
			var it Item
			if err := rows.Scan(&it.ID, &it.Name); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			items = append(items, it)
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(items)
	})

	// FileServer сам отдаёт index.html на "/". Подменять путь на "/index.html"
	// нельзя: FileServer редиректит такие запросы на "./" -> бесконечный редирект.
	http.Handle("/", fs)

	addr := ":" + env("HTTP_PORT", "8080")
	log.Printf("listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

func waitForDB(db *sql.DB, attempts int, delay time.Duration) {
	for i := 1; i <= attempts; i++ {
		err := db.Ping()
		if err == nil {
			log.Printf("connected to database")
			return
		}
		log.Printf("database not ready (attempt %d/%d): %v", i, attempts, err)
		time.Sleep(delay)
	}
	log.Fatal("database is unavailable, giving up")
}

func healthcheck() int {
	client := http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + env("HTTP_PORT", "8080") + "/healthz")
	if err != nil {
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 1
	}
	return 0
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
