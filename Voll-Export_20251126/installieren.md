# Speiseplan‑Meister – Installation

Diese Anleitung beschreibt die Inbetriebnahme des Projekts **Speiseplan‑Meister** aus einem ZIP‑Archiv auf einem **frischen** Server (Linux oder Windows).

## 1. Voraussetzungen

### 1.1 Hardware / Netzwerk

- **CPU/RAM:** ausreichend für Docker‑Builds (Backend Python + Frontend Node). Empfehlung: mindestens 2 CPU / 4–8 GB RAM.
- **Ports (eingehend):**
  - **HTTP:** 80
  - **HTTPS:** 443 (nur bei HTTPS‑Betrieb)
- **Ausgehend:** Zugriff auf Docker Registry (Pull von `postgres`, `redis`, `python`, `nginx`) und ggf. auf Git/Package‑Registries.

### 1.2 Software

- **Docker Engine**
- **Docker Compose** (Compose Plugin, d. h. `docker compose`)

> Hinweis: Das Projekt nutzt Docker Compose und startet u. a. Postgres, Redis, Backend, Frontend und einen Nginx‑Proxy.

---

## 2. Inhalt des Projektordners (Pflichtdateien / Pflichtordner)

Nach dem Entpacken des ZIP‑Archivs wird folgende Struktur erwartet (Auszug):

- `docker-compose.yml`
- `.env` (muss erstellt/geliefert werden)
- `ndjson_updater.env` (optional, siehe Abschnitt 6)
- `proxy/`
  - `nginx.conf`
  - `certs/` (nur bei HTTPS)
- `uploads/` (wird als persistentes Volume genutzt)
- `backups/` (Backups werden hier abgelegt)
- `imports/remi_export_inbox/current/` (NDJSON‑Importquelle)

### 2.1 Erforderliche Umgebungsdatei `.env`

`docker-compose.yml` referenziert eine `.env` Datei. Diese muss im Projekt‑Root liegen.

Minimal erforderlich:

- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`

Empfohlene Basis‑Konfiguration (Beispiel):

```env
POSTGRES_DB=fps_database
POSTGRES_USER=postgres
POSTGRES_PASSWORD=changeme

ENVIRONMENT=production
DEBUG=False

# Für lokalen Test unbedingt localhost drin lassen
ALLOWED_HOSTS=localhost,127.0.0.1,46.224.129.131,api.speiseplan-meister.de
CORS_ALLOW_ORIGINS=http://46.224.129.131:3000,https://app.speiseplan-meister.de,http://localhost:3000

TRUST_PROXY_HEADERS=true
PROXY_TRUSTED_HOSTS=*

ADMIN_USERNAME=admin
ADMIN_PASSWORD_BCRYPT=<set-admin-password-bcrypt>

FORCE_RESTORE=0

AUTH_USER_1_USERNAME=elisabeth.acker
AUTH_USER_1_PASSWORD_BCRYPT=<set-user-1-password-bcrypt>
AUTH_USER_2_USERNAME=katharina.hausmann
AUTH_USER_2_PASSWORD_BCRYPT=<set-user-2-password-bcrypt>

UPLOAD_WRITE_METADATA=true
RECONCILE_UPLOADS_ON_START=true
RECONCILE_FAIL_ON_ERROR=false

# Optional nur für lokale Scripts außerhalb Docker (gegen Port 5433)
DB_HOST=db
DB_PORT=5432
DB_NAME=fps_database
DB_USER=postgres
DB_PASSWORD=changeme

API_KEY=<set-a-strong-random-api-key>
HMAC_SECRET=<set-a-strong-random-hmac-secret>

# OpenAI (optional)
OPENAI_API_KEY=<optional>
```

Optional (für Backend‑Build User‑Mapping):

- `UID`
- `GID`

Hinweis zu `ALLOWED_HOSTS`:

- Wenn die Server‑IP/Domain nicht in `ALLOWED_HOSTS` enthalten ist, antwortet die API auf Login‑Requests mit `400 Invalid host header`.
- Deshalb in Produktivbetrieb immer die tatsächliche Domain und/oder öffentliche IP ergänzen.

---

## 3. Linux‑Installation (Ubuntu/Debian)

### 3.1 Docker installieren

Beispiel (Docker Convenience Script):

```bash
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
```

Optional: Docker ohne `sudo` nutzen

```bash
sudo usermod -aG docker $USER
# Danach neu einloggen (SSH Session neu öffnen)
```

### 3.2 Projekt bereitstellen

- ZIP in ein Zielverzeichnis kopieren, z. B. `/opt/speiseplan-meister/`
- ZIP entpacken
- Sicherstellen, dass `.env` vorhanden ist

### 3.3 Verzeichnisse vorbereiten

Folgende Ordner müssen existieren und beschreibbar sein:

- `./uploads`
- `./backups`

Zusatz: Upload‑Rechte (wichtig)

- Das Backend läuft als **nicht‑root User** im Container.
- `./uploads` wird nach `/app/uploads` gemountet.
- Wenn `./uploads` auf dem Host dem falschen User gehört, schlägt ein Dateiupload in der Web‑UI mit `Permission denied: /app/uploads/...` fehl.

Empfohlen: `UID`/`GID` in `.env` setzen und die Ordner auf dem Host entsprechend besitzen lassen.

Beispiel:

```bash
mkdir -p uploads backups

# Beispielwerte, müssen zu UID/GID in der .env passen
export UID_ON_HOST=1001
export GID_ON_HOST=1001

chown -R "${UID_ON_HOST}:${GID_ON_HOST}" uploads backups
chmod -R u+rwX uploads backups
```

### 3.4 Start

Im Projekt‑Root:

```bash
docker compose up -d --build
docker compose ps
```

### 3.5 Funktionsprüfung

- Status prüfen:

```bash
docker compose ps
```

- Migration‑Container (läuft einmalig) prüfen:

```bash
docker compose logs --tail=200 db_migrate
```

---

## 4. Windows‑Installation

### 4.1 Empfohlene Variante: Docker Desktop + WSL2

Empfohlen wird der Betrieb über **WSL2**, da das Projekt Linux‑Container nutzt.

- Docker Desktop installieren
- WSL2 aktivieren und eine Linux‑Distribution (z. B. Ubuntu) einrichten
- Im WSL‑Terminal in den Projektordner wechseln (z. B. `/mnt/c/speiseplan-meister`)

### 4.2 Projekt bereitstellen

- ZIP nach Windows kopieren und entpacken (z. B. `C:\speiseplan-meister`)
- `.env` im Projekt‑Root anlegen
- Start aus WSL heraus:

```bash
docker compose up -d --build
docker compose ps
```

---

## 5. HTTPS vs. HTTP (ohne HTTPS)

Im Docker‑Compose wird ein Reverse Proxy (`proxy`) genutzt.

### 5.1 HTTPS‑Betrieb (Standard‑Zielkonfiguration)

Voraussetzungen:

- `proxy/certs/fullchain.pem`
- `proxy/certs/privkey.pem`

Diese Dateien werden vom Nginx‑Proxy unter folgenden Pfaden erwartet:

- `/etc/nginx/certs/fullchain.pem`
- `/etc/nginx/certs/privkey.pem`

Start wie üblich:

```bash
docker compose up -d --build
```

Hinweis:

- Die Konfiguration in `proxy/nginx.conf` leitet HTTP (Port 80) auf HTTPS (Port 443) um.

### 5.2 HTTP‑Betrieb (ohne HTTPS)

Für einen reinen HTTP‑Betrieb gibt es zwei Möglichkeiten:

#### Möglichkeit A: Proxy‑Konfiguration auf HTTP umstellen

- Datei `proxy/nginx.conf` so anpassen, dass:
  - **kein Redirect** von 80 auf 443 erfolgt
  - **kein** `listen 443 ssl;` Block verwendet wird
  - stattdessen ein `server { listen 80; ... }` vorhanden ist, der direkt auf:
    - `http://backend:8000` für `/api/`
    - `http://frontend:80` für `/`
    proxied

Danach Proxy neu bauen und starten:

```bash
docker compose up -d --build
```

#### Möglichkeit B: Zertifikatsdateien bereitstellen

- Wenn weiterhin die bestehende Konfiguration genutzt werden soll, müssen Zertifikatsdateien bereitgestellt werden.
- In diesem Fall bleibt die Konfiguration unverändert.

---

## 6. NDJSON‑Updater (optional)

Der Service `ndjson_updater` aktualisiert die Gerichte aus NDJSON‑Exports.

### 6.1 Importquelle

- Host‑Pfad: `./imports/remi_export_inbox/current`
- Container‑Pfad: `/imports/remi_export_inbox/current`

In diesem Ordner werden u. a. erwartet:

- `manifest.json` (steuert, ob `all` oder `update` geladen wird)
- NDJSON‑Dateien (z. B. `articles.ndjson` oder `articles_update.ndjson`)

### 6.2 Env‑Datei

- `ndjson_updater.env` kann aus `ndjson_updater.env.example` erstellt werden.
- Falls im Update‑Prozess benötigt, muss `OPENAI_API_KEY` gesetzt werden.

---

## 7. Backups

Es laufen zwei Backup‑Services:

- `db_backup` (täglich)
  - Ziel: `./backups/daily`
  - Aufbewahrung: **14** Versionen
- `db_backup_weekly_gerichte2` (wöchentlich)
  - Ziel: `./backups/weekly`
  - Aufbewahrung: **8** Versionen

---

## 8. Typische Startreihenfolge (zur Einordnung)

- `db` startet und wird „healthy“
- `db_migrate` läuft einmalig (Migrationen)
- danach starten `backend` und `ndjson_updater`
- `frontend` und `proxy` stellen die Weboberfläche und `/api/` bereit

---

## 9. Betrieb / Diagnose

- Containerstatus:

```bash
docker compose ps
```

- Logs einzelner Container:

```bash
docker compose logs --tail=200 backend
```

Häufige Fehlerbilder:

- `400 Invalid host header` beim Login/bei API‑Calls:
  - Ursache: `ALLOWED_HOSTS` enthält die Server‑IP/Domain nicht.
  - Lösung: `ALLOWED_HOSTS` in `.env` ergänzen und Container neu starten:

```bash
docker compose up -d --build
```

- `500` bei Datei‑Upload, Backend‑Log enthält `Permission denied: '/app/uploads/...`:
  - Ursache: Host‑Ordner `./uploads` ist für den Container‑User nicht beschreibbar.
  - Lösung: Besitz/Rechte von `./uploads` korrigieren (siehe Abschnitt 3.3) und Backend neu starten:

```bash
docker compose restart backend
```

- Stoppen:

```bash
docker compose down
```
