#!/usr/bin/env bash
# =============================================================================
# SprintMind | scripts/backup/backup_db.sh
#
# PostgreSQL yedeği alır, sıkıştırır ve eski yedekleri temizler.
#
# Kullanım:
#   ./scripts/backup/backup_db.sh                   → tek seferlik manuel
#   ./scripts/backup/backup_db.sh --dry-run          → ne yapacağını göster
#
# Otomatik çalıştırmak için crontab örneği (her gün 02:00):
#   0 2 * * * /opt/sprintmind/sprintmind-infra/scripts/backup/backup_db.sh \
#             >> /var/log/sprintmind-backup.log 2>&1
#
# Gereksinimler:
#   - Docker Compose ile sprintmind-postgres container'ı çalışıyor olmalı
#   - Bu script sprintmind-infra/ klasöründen çalıştırılmalı
#     ya da INFRA_DIR ortam değişkeni set edilmeli
# =============================================================================

set -euo pipefail

# ── Renkli çıktı ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'

log_info()  { echo -e "${CYAN}[$(date '+%H:%M:%S')] INFO  ${NC}$*"; }
log_ok()    { echo -e "${GREEN}[$(date '+%H:%M:%S')] OK    ${NC}$*"; }
log_warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN  ${NC}$*"; }
log_error() { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR ${NC}$*" >&2; }

# ── Konfigürasyon ─────────────────────────────────────────────────────────────
# sprintmind-infra repo kök dizini
INFRA_DIR="${INFRA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# .env dosyasından değişkenleri yükle
ENV_FILE="${INFRA_DIR}/.env"
if [[ -f "$ENV_FILE" ]]; then
  # export edilebilir satırları güvenli şekilde yükle
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
else
  log_error ".env dosyası bulunamadı: $ENV_FILE"
  log_error "cp .env.example .env && .env'yi düzenle"
  exit 1
fi

POSTGRES_USER="${POSTGRES_USER:-sprintmind_user}"
POSTGRES_DB="${POSTGRES_DB:-sprintmind}"
CONTAINER_NAME="sprintmind-postgres"

# Yedeklerin saklanacağı dizin
BACKUP_DIR="${BACKUP_DIR:-${INFRA_DIR}/backups}"

# Kaç günlük yedek saklanacak (eski olanlar silinir)
RETENTION_DAYS="${RETENTION_DAYS:-7}"

# Zaman damgası
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="${BACKUP_DIR}/sprintmind_${TIMESTAMP}.sql.gz"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# ── Kontroller ────────────────────────────────────────────────────────────────
echo ""
log_info "SprintMind Veritabanı Yedekleme"
log_info "Hedef : $BACKUP_FILE"
log_info "Saklama süresi : ${RETENTION_DAYS} gün"

# Docker var mı?
if ! command -v docker &>/dev/null; then
  log_error "docker komutu bulunamadı"
  exit 1
fi

# Container çalışıyor mu?
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  log_error "Container çalışmıyor: $CONTAINER_NAME"
  log_error "docker compose up -d postgres ile başlat"
  exit 1
fi

# ── Backup dizini ──────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "false" ]]; then
  mkdir -p "$BACKUP_DIR"
  # Backup dizinini yanlışlıkla Git'e eklememe
  GITIGNORE="${BACKUP_DIR}/.gitignore"
  if [[ ! -f "$GITIGNORE" ]]; then
    echo "*" > "$GITIGNORE"
    echo "!.gitignore" >> "$GITIGNORE"
    log_info "Backup dizinine .gitignore eklendi"
  fi
fi

# ── pg_dump ────────────────────────────────────────────────────────────────────
log_info "pg_dump başlatılıyor..."

if [[ "$DRY_RUN" == "true" ]]; then
  log_warn "[DRY-RUN] Şu komut çalıştırılacaktı:"
  echo "  docker exec $CONTAINER_NAME pg_dump -U $POSTGRES_USER -d $POSTGRES_DB | gzip > $BACKUP_FILE"
else
  if docker exec "$CONTAINER_NAME" \
      pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
      --no-owner --no-acl \
      --format=plain \
      | gzip > "$BACKUP_FILE"; then
    SIZE=$(du -sh "$BACKUP_FILE" 2>/dev/null | cut -f1)
    log_ok "Yedek oluşturuldu: $BACKUP_FILE ($SIZE)"
  else
    log_error "pg_dump başarısız oldu!"
    rm -f "$BACKUP_FILE"
    exit 1
  fi
fi

# ── Rotasyon ── eski yedekleri temizle ─────────────────────────────────────────
log_info "Eski yedekler temizleniyor (>${RETENTION_DAYS} gün)..."

OLD_FILES=$(find "$BACKUP_DIR" -maxdepth 1 -name "sprintmind_*.sql.gz" \
  -mtime +"$RETENTION_DAYS" 2>/dev/null || true)

if [[ -z "$OLD_FILES" ]]; then
  log_info "Silinecek eski yedek yok"
else
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "[DRY-RUN] Silinecek dosyalar:"
    echo "$OLD_FILES" | while read -r f; do echo "  $f"; done
  else
    echo "$OLD_FILES" | while read -r f; do
      rm -f "$f"
      log_ok "Silindi: $f"
    done
  fi
fi

# ── Özet ──────────────────────────────────────────────────────────────────────
echo ""
BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -name "sprintmind_*.sql.gz" 2>/dev/null | wc -l | tr -d ' ')
log_ok "Tamamlandı. Mevcut yedek sayısı: $BACKUP_COUNT"
echo ""

# ── Geri yükleme notu ─────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "false" ]]; then
  log_info "Geri yükleme için:"
  echo "  gunzip -c $BACKUP_FILE | docker exec -i $CONTAINER_NAME psql -U $POSTGRES_USER -d $POSTGRES_DB"
fi
