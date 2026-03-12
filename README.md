# sprintmind-infra

SprintMind projesinin altyapı katmanı. Docker Compose ile tüm servisleri tek komutla ayağa kaldırır.

---

## İçindekiler

- [Genel Bakış](#genel-bakış)
- [Gereksinimler](#gereksinimler)
- [Hızlı Başlangıç](#hızlı-başlangıç)
- [Servisler](#servisler)
- [Klasör Yapısı](#klasör-yapısı)
- [Ortam Değişkenleri](#ortam-değişkenleri)
- [Veritabanı](#veritabanı)
- [Ollama — AI Modelleri](#ollama--ai-modelleri)
- [Nginx](#nginx)
- [Sık Kullanılan Komutlar](#sık-kullanılan-komutlar)
- [Production Notları](#production-notları)

---

## Genel Bakış

```
Kullanıcı (browser)
    ↓
  Nginx :80
    ├── /api/*    → ASP.NET Core API :5000
    ├── /hubs/*   → SignalR Hub :5000 (WebSocket)
    └── /*        → React statik dosyalar
```

Tüm servisler `sprintmind-net` adlı Docker internal ağı üzerinden birbirine bağlanır. Dışarıya yalnızca Nginx'in 80 portu açıktır.

---

## Gereksinimler

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) 4.x+
- Docker Compose v2+ (`docker compose` — tire ile)
- 8 GB RAM (Ollama modeli için minimum)
- 20 GB disk alanı (Docker image'ları + model dosyaları)

---

## Hızlı Başlangıç

```bash
# 1. Repoyu klonla
git clone https://github.com/farukkaya/sprintmind-infra.git
cd sprintmind-infra

# 2. Ortam değişkenlerini oluştur
cp .env.example .env
# .env dosyasını aç ve şifreleri doldur

# 3. Geçici placeholder oluştur (frontend build gelene kadar)
mkdir -p frontend-dist
echo "<h1>SprintMind</h1>" > frontend-dist/index.html

# 4. Servisleri başlat
docker compose up -d

# 5. Ollama modellerini indir (ilk kurulumda bir kere yapılır)
docker exec sprintmind-ollama ollama pull mistral
docker exec sprintmind-ollama ollama pull nomic-embed-text

# 6. Kontrol et
docker compose ps
```

Tarayıcıdan `http://localhost` adresini aç — placeholder sayfası görünüyorsa her şey çalışıyor.

---

## Servisler

| Servis | Image | Port | Açıklama |
|---|---|---|---|
| nginx | `nginx:alpine` | `80` | Ters proxy + statik dosya sunucusu |
| postgres | `pgvector/pgvector:pg16` | `5432` | Ana veritabanı + pgvector eklentisi |
| redis | `redis:7-alpine` | `6379` | Oturum state + JWT refresh token cache |
| ollama | `ollama/ollama` | `11434` | Lokal AI model servisi (Mistral 7B) |
| api | *(yorum satırı)* | `5000` | ASP.NET Core API — hazır olunca açılacak |

> **Not:** `5432`, `6379`, `11434` portları geliştirme kolaylığı için açıktır. Production ortamında bu portlar kapatılmalıdır.

---

## Klasör Yapısı

```
sprintmind-infra/
├── docker-compose.yml          # Servis tanımları
├── docker-compose.prod.yml     # Production overrides (hazırlanacak)
├── .env                        # Ortam değişkenleri — Git'e gitmiyor
├── .env.example                # .env şablonu — Git'e gidiyor
│
├── nginx/
│   ├── nginx.conf              # Nginx ana konfigürasyonu
│   └── conf.d/
│       └── sprintmind.conf     # Site konfigürasyonu (proxy kuralları)
│
├── postgres/
│   ├── init/                   # İlk açılışta otomatik çalışan SQL'ler
│   │   ├── 01_extensions.sql   # pgvector, pgcrypto, pg_trgm
│   │   ├── 02_enums.sql        # PostgreSQL ENUM tipleri
│   │   └── 03_tables.sql       # Tüm tablolar ve indexler
│   └── seeds/
│       └── reference_items.sql # AI eğitim verisi (25 referans madde)
│
├── scripts/
│   ├── backup/
│   │   └── backup_db.sh        # Otomatik yedekleme scripti
│   └── deploy/
│       └── deploy.sh           # Production güncelleme scripti
│
└── frontend-dist/              # React build çıktısı buraya kopyalanır
    └── index.html              # Geçici placeholder
```

---

## Ortam Değişkenleri

`.env.example` dosyasını kopyalayarak `.env` oluştur:

```bash
cp .env.example .env
```

| Değişken | Açıklama | Örnek |
|---|---|---|
| `POSTGRES_USER` | Veritabanı kullanıcı adı | `sprintmind_user` |
| `POSTGRES_PASSWORD` | Veritabanı şifresi | `güçlü_bir_şifre` |
| `JWT_SECRET` | JWT imzalama anahtarı (min 32 karakter) | `rastgele_uzun_string` |

> ⚠️ `.env` dosyasını asla Git'e commit etme. `.gitignore`'a ekli olduğunu kontrol et.

---

## Veritabanı

### Init SQL Dosyaları

`postgres/init/` klasöründeki dosyalar container **ilk oluşturulduğunda** alfabetik sırayla otomatik çalışır:

```
01_extensions.sql  →  pgvector, pgcrypto, pg_trgm eklentileri
02_enums.sql       →  user_role, session_type, fibonacci_sp vb. ENUM'lar
03_tables.sql      →  10 tablo + indexler (V1 + V2)
```

> ⚠️ Bu dosyalar yalnızca **ilk açılışta** çalışır. Değişiklik yapılırsa volume silinip container yeniden oluşturulmalıdır.

### Seed Verisi

Referans maddeleri manuel olarak yükle:

```bash
docker exec -i sprintmind-postgres psql -U sprintmind_user -d sprintmind \
  < ./postgres/seeds/reference_items.sql
```

### Veritabanına Bağlanma

```bash
# psql ile
docker exec -it sprintmind-postgres psql -U sprintmind_user -d sprintmind

# Tabloları listele
\dt

# Eklentileri kontrol et
\dx
```

DBeaver veya DataGrip ile bağlanmak için:
- Host: `localhost`
- Port: `5432`
- Database: `sprintmind`
- User/Password: `.env` dosyasındaki değerler

### Volume Yönetimi

```bash
# Veritabanını sıfırla (TÜM VERİLER SİLİNİR)
docker compose down -v
docker compose up -d
```

---

## Ollama — AI Modelleri

### Model Kurulumu

İlk kurulumda modelleri indir (internet bağlantısı gerekir, bir kere yapılır):

```bash
# Dil modeli (~4 GB)
docker exec sprintmind-ollama ollama pull mistral

# Embedding modeli (~270 MB)
docker exec sprintmind-ollama ollama pull nomic-embed-text
```

İndirilen modeller `ollama_models` Docker volume'unda kalıcı olarak saklanır. Container yeniden başlatılsa bile tekrar indirilmez.

### Model Testi

```bash
# Mistral ile test
docker exec -it sprintmind-ollama ollama run mistral "Merhaba, nasılsın?"

# Yüklü modelleri listele
docker exec sprintmind-ollama ollama list
```

### GPU Desteği

Sunucuda NVIDIA GPU varsa `docker-compose.yml`'deki `ollama` servisinde yorum satırlarını aç:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1
          capabilities: [gpu]
```

GPU olmadan yanıt süresi 30–60 saniye, GPU ile 3–8 saniyedir.

---

## Nginx

### Trafik Kuralları

| Path | Hedef | Açıklama |
|---|---|---|
| `/api/*` | `api:5000` | REST API — *(api servisi hazır olunca aktif)* |
| `/hubs/*` | `api:5000` | SignalR WebSocket — *(api servisi hazır olunca aktif)* |
| `/*` | statik dosyalar | React uygulaması |
| `/health` | Nginx | Sağlık kontrolü endpoint'i |

### API Proxy'yi Aktifleştirme

`sprintmind-api` reposu hazır olduğunda `nginx/conf.d/sprintmind.conf` dosyasındaki yorum satırlarını aç ve Nginx'i yeniden yükle:

```bash
docker exec sprintmind-nginx nginx -s reload
```

### Frontend Build Güncelleme

`sprintmind-frontend` reposunda build alındıktan sonra:

```bash
# frontend reposunda
npm run build

# Çıktıyı infra reposuna kopyala
cp -r dist/* ../sprintmind-infra/frontend-dist/
```

Nginx yeniden başlatmaya gerek yok — dosyalar mount edildiği için anlık güncellenir.

### SSL Aktifleştirme

1. Sertifika dosyalarını kopyala:
   ```
   nginx/ssl/sprintmind.crt
   nginx/ssl/sprintmind.key
   ```

2. `docker-compose.yml`'de nginx volume'una ekle:
   ```yaml
   - ./nginx/ssl:/etc/nginx/ssl:ro
   ```

3. `nginx/conf.d/sprintmind.conf`'taki HTTPS bloğunun yorum satırlarını aç.

---

## Sık Kullanılan Komutlar

```bash
# Tüm servisleri başlat
docker compose up -d

# Tüm servisleri durdur
docker compose down

# Servis durumlarını gör
docker compose ps

# Belirli bir servisin loglarını takip et
docker compose logs -f postgres
docker compose logs -f nginx

# Tek servisi yeniden başlat
docker compose restart nginx

# Nginx konfigürasyonunu test et
docker exec sprintmind-nginx nginx -t

# Nginx'i yeniden yükle (sıfırlama olmadan)
docker exec sprintmind-nginx nginx -s reload

# PostgreSQL'e bağlan
docker exec -it sprintmind-postgres psql -U sprintmind_user -d sprintmind

# Redis'e bağlan
docker exec -it sprintmind-redis redis-cli
```

---

## Production Notları

- `5432`, `6379`, `11434` portlarını kapat — sadece `80` (ve SSL için `443`) açık olmalı
- `.env` dosyasındaki şifreleri güçlü ve rastgele değerlerle değiştir
- `backup_db.sh` scriptini cron job olarak zamanla
- SSL sertifikasını aktifleştir (`nginx/conf.d/sprintmind.conf` içindeki talimatları takip et)
- `restart: unless-stopped` tüm servislerde tanımlı — sunucu yeniden başlatılsa servisler otomatik ayağa kalkar

---

## İlgili Repolar

| Repo | Açıklama |
|---|---|
| [sprintmind-api](https://github.com/farukkaya/sprintmind-api) | ASP.NET Core 8 backend |
| [sprintmind-frontend](https://github.com/farukkaya/sprintmind-frontend) | React 18 + TypeScript frontend |