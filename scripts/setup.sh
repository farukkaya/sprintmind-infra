#!/usr/bin/env bash
# =============================================================================
# SprintMind | scripts/setup.sh
#
# İLK KURULUM scripti.
# Docker servisleri çalıştıktan sonra yapılması gereken tek seferlik işlemler:
#   1. Ollama modelleri indir (mistral, nomic-embed-text)
#   2. Seed verisini PostgreSQL'e yükle
#
# Kullanım:
#   cd sprintmind-infra/
#   ./scripts/setup.sh
#   ./scripts/setup.sh --only-models    → sadece Ollama modelleri
#   ./scripts/setup.sh --only-seed      → sadece seed verisi
#   ./scripts/setup.sh --dry-run        → ne yapacağını göster
#
# ⚠️  Gereksinimler:
#   - docker compose up -d yapılmış ve containerlar çalışıyor olmalı
#   - Özellikle sprintmind-postgres healthy, sprintmind-ollama running olmalı
# =============================================================================

set -euo pipefail

# ── Renkli çıktı ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log_info()    { echo -e "${CYAN}[$(date '+%H:%M:%S')] INFO  ${NC}$*"; }
log_ok()      { echo -e "${GREEN}[$(date '+%H:%M:%S')] OK    ${NC}$*"; }
log_warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN  ${NC}$*"; }
log_error()   { echo -e "${RED}[$(date '+%H:%M:%S')] ERROR ${NC}$*" >&2; }
log_section() { echo -e "\n${BOLD}════════ $* ════════${NC}\n"; }

# ── Konfigürasyon ─────────────────────────────────────────────────────────────
INFRA_DIR="${INFRA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
ENV_FILE="${INFRA_DIR}/.env"
SEED_FILE="${INFRA_DIR}/postgres/seeds/reference_items.sql"

POSTGRES_CONTAINER="sprintmind-postgres"
OLLAMA_CONTAINER="sprintmind-ollama"

# Ollama modelleri — handoff'ta belirtilen modeller
OLLAMA_MODELS=(
  "mistral"            # ~4.1 GB  — Story Point analizi ve açıklama üretimi
  "nomic-embed-text"   # ~274 MB  — Metin embedding (pgvector için)
)

# Argümanları işle
ONLY_MODELS=false
ONLY_SEED=false
DRY_RUN=false

for arg in "$@"; do
  case $arg in
    --only-models) ONLY_MODELS=true ;;
    --only-seed)   ONLY_SEED=true ;;
    --dry-run)     DRY_RUN=true ;;
  esac
done

RUN_MODELS=true
RUN_SEED=true
[[ "$ONLY_MODELS" == "true" ]] && RUN_SEED=false
[[ "$ONLY_SEED"   == "true" ]] && RUN_MODELS=false

# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

container_running() {
  docker ps --format '{{.Names}}' | grep -q "^${1}$"
}

wait_healthy() {
  local container="$1"
  local max_wait="${2:-60}"
  local elapsed=0
  log_info "$container bekleniyor..."
  while [[ $elapsed -lt $max_wait ]]; do
    # Önce container'ın çalışıp çalışmadığını kontrol et
    IS_RUNNING=$(docker inspect --format='{{.State.Running}}' "$container" 2>/dev/null || echo "false")
    if [[ "$IS_RUNNING" != "true" ]]; then
      sleep 3
      elapsed=$((elapsed + 3))
      continue
    fi

    # Healthcheck tanımlı mı?
    HAS_HEALTH=$(docker inspect --format='{{if .State.Health}}yes{{else}}no{{end}}' "$container" 2>/dev/null || echo "no")
    if [[ "$HAS_HEALTH" == "no" ]]; then
      log_ok "$container → running (healthcheck tanımlı değil)"
      return 0
    fi

    # Healthcheck varsa durumunu kontrol et
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "starting")
    if [[ "$STATUS" == "healthy" ]]; then
      log_ok "$container → healthy"
      return 0
    fi

    sleep 3
    elapsed=$((elapsed + 3))
  done
  log_error "$container ${max_wait}s içinde hazır olmadı"
  return 1
}

# ── Başlık ────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}SprintMind İlk Kurulum${NC}"
echo "Tarih : $(date '+%Y-%m-%d %H:%M:%S')"
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN modu — gerçek işlem yapılmayacak"
echo ""

# ── .env yükle ────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]]; then
  set -a; source "$ENV_FILE"; set +a
  log_ok ".env yüklendi"
else
  log_error ".env bulunamadı — önce: cp .env.example .env"
  exit 1
fi

POSTGRES_USER="${POSTGRES_USER:-sprintmind_user}"
POSTGRES_DB="${POSTGRES_DB:-sprintmind}"

# ── Containerlar çalışıyor mu? ────────────────────────────────────────────────
log_section "Container Kontrolü"

if ! command -v docker &>/dev/null; then
  log_error "docker bulunamadı"
  exit 1
fi

if [[ "$RUN_SEED" == "true" ]]; then
  if ! container_running "$POSTGRES_CONTAINER"; then
    log_error "$POSTGRES_CONTAINER çalışmıyor."
    log_error "Önce: docker compose up -d"
    exit 1
  fi
  wait_healthy "$POSTGRES_CONTAINER" 60
fi

if [[ "$RUN_MODELS" == "true" ]]; then
  if ! container_running "$OLLAMA_CONTAINER"; then
    log_error "$OLLAMA_CONTAINER çalışmıyor."
    log_error "Önce: docker compose up -d"
    exit 1
  fi
  wait_healthy "$OLLAMA_CONTAINER" 30
fi

# ── 1. Ollama modelleri ────────────────────────────────────────────────────────
if [[ "$RUN_MODELS" == "true" ]]; then
  log_section "1 / 2 — Ollama Modelleri"
  log_warn "Bu adım internet bağlantısı ve disk alanı gerektirir:"
  log_warn "  mistral          → ~4.1 GB"
  log_warn "  nomic-embed-text → ~274 MB"
  echo ""

  for MODEL in "${OLLAMA_MODELS[@]}"; do
    # Model zaten indirilmiş mi kontrol et
    ALREADY_PULLED=$(docker exec "$OLLAMA_CONTAINER" \
      ollama list 2>/dev/null | grep -c "^${MODEL}" || true)

    if [[ "$ALREADY_PULLED" -gt 0 ]]; then
      log_ok "$MODEL zaten indirilmiş — atlanıyor"
    else
      log_info "$MODEL indiriliyor..."
      run "docker exec $OLLAMA_CONTAINER ollama pull $MODEL"
      log_ok "$MODEL indirildi"
    fi
  done

  # Model listesini göster
  if [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    log_info "Mevcut Ollama modelleri:"
    docker exec "$OLLAMA_CONTAINER" ollama list 2>/dev/null || true
  fi
fi

# ── 2. Seed verisi ────────────────────────────────────────────────────────────
if [[ "$RUN_SEED" == "true" ]]; then
  log_section "2 / 2 — Seed Verisi (reference_items)"

  if [[ ! -f "$SEED_FILE" ]]; then
    log_error "Seed dosyası bulunamadı: $SEED_FILE"
    exit 1
  fi

  # Zaten seed yapılmış mı kontrol et
  EXISTING=$(docker exec "$POSTGRES_CONTAINER" \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
    "SELECT COUNT(*) FROM reference_items;" 2>/dev/null || echo "0")
  EXISTING=$(echo "$EXISTING" | tr -d ' \n')

  if [[ "$EXISTING" -gt 0 ]]; then
    log_warn "reference_items tablosunda $EXISTING kayıt var — seed zaten yapılmış"
    read -r -p "Yine de yüklemek istiyor musun? [e/H]: " CONFIRM
    if [[ "$CONFIRM" != "e" && "$CONFIRM" != "E" ]]; then
      log_info "Seed atlandı"
    else
      run "docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB < $SEED_FILE"
      log_ok "Seed verisi yüklendi"
    fi
  else
    log_info "Seed verisi yükleniyor: $SEED_FILE"
    run "docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB < $SEED_FILE"
    log_ok "Seed verisi yüklendi"

    # Kaç kayıt yüklendi?
    if [[ "$DRY_RUN" == "false" ]]; then
      COUNT=$(docker exec "$POSTGRES_CONTAINER" \
        psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
        "SELECT COUNT(*) FROM reference_items;" 2>/dev/null | tr -d ' ')
      log_info "reference_items: $COUNT kayıt"
    fi
  fi
fi

# ── Özet ──────────────────────────────────────────────────────────────────────
echo ""
log_ok "Kurulum tamamlandı — $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "  Sonraki adım:"
echo "    sprintmind-api reposunu kur (ASP.NET Core solution)"
echo ""
