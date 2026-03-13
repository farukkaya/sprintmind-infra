#!/usr/bin/env bash
# =============================================================================
# SprintMind | scripts/deploy/deploy.sh
#
# Production deployment scripti.
# Git pull → Docker image build → Migration → Container yenile → Sağlık kontrolü
#
# Kullanım:
#   ./scripts/deploy/deploy.sh              → tam deploy
#   ./scripts/deploy/deploy.sh --skip-pull  → Git pull yapma (manuel kod güncellemesi)
#   ./scripts/deploy/deploy.sh --dry-run    → ne yapacağını göster
#
# Gereksinimler:
#   - sprintmind-infra ve sprintmind-api yan yana klonlanmış olmalı
#   - Docker + Docker Compose kurulu olmalı
#   - .env dosyası doldurulmuş olmalı
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
INFRA_DIR="${INFRA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
API_DIR="${API_DIR:-$(cd "${INFRA_DIR}/../sprintmind-api" 2>/dev/null && pwd || echo '')}"
FRONTEND_DIR="${FRONTEND_DIR:-$(cd "${INFRA_DIR}/../sprintmind-frontend" 2>/dev/null && pwd || echo '')}"

ENV_FILE="${INFRA_DIR}/.env"
COMPOSE_FILE="${INFRA_DIR}/docker-compose.prod.yml"
BACKUP_SCRIPT="${INFRA_DIR}/scripts/backup/backup_db.sh"

# Deployment seçenekleri
SKIP_PULL=false
DRY_RUN=false
SKIP_BACKUP=false

for arg in "$@"; do
  case $arg in
    --skip-pull)   SKIP_PULL=true ;;
    --dry-run)     DRY_RUN=true ;;
    --skip-backup) SKIP_BACKUP=true ;;
  esac
done

# ── Yardımcı fonksiyonlar ─────────────────────────────────────────────────────
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    log_error "'$1' komutu bulunamadı. Kurulum gerekli."
    exit 1
  fi
}

wait_healthy() {
  local container="$1"
  local max_wait="${2:-60}"
  local elapsed=0
  log_info "$container sağlıklı olana kadar bekleniyor..."
  while [[ $elapsed -lt $max_wait ]]; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
    if [[ "$STATUS" == "healthy" ]]; then
      log_ok "$container → healthy"
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  log_error "$container ${max_wait}s içinde healthy olmadı (son durum: $STATUS)"
  return 1
}

# ── Başlık ────────────────────────────────────────────────────────────────────
echo -e "\n${BOLD}SprintMind Deployment Script${NC}"
echo "Tarih     : $(date '+%Y-%m-%d %H:%M:%S')"
echo "Infra dir : $INFRA_DIR"
[[ -n "$API_DIR" ]]      && echo "API dir   : $API_DIR"
[[ -n "$FRONTEND_DIR" ]] && echo "Frontend  : $FRONTEND_DIR"
[[ "$DRY_RUN" == "true" ]]   && log_warn "DRY-RUN modu aktif — gerçek işlem yapılmayacak"
echo ""

# ── Ön kontroller ─────────────────────────────────────────────────────────────
log_section "Ön Kontroller"
check_cmd docker
check_cmd git

if [[ ! -f "$ENV_FILE" ]]; then
  log_error ".env dosyası bulunamadı: $ENV_FILE"
  log_error "cp .env.example .env && .env'yi düzenle"
  exit 1
fi
log_ok ".env mevcut"

# .env yükle
set -a; source "$ENV_FILE"; set +a

if [[ ! -f "$COMPOSE_FILE" ]]; then
  log_error "docker-compose.prod.yml bulunamadı: $COMPOSE_FILE"
  exit 1
fi
log_ok "docker-compose.prod.yml mevcut"

# ── 1. Deployment öncesi yedek ────────────────────────────────────────────────
log_section "1 / 5 — Veritabanı Yedeği"

if [[ "$SKIP_BACKUP" == "true" ]]; then
  log_warn "Yedek atlandı (--skip-backup)"
elif [[ -f "$BACKUP_SCRIPT" ]]; then
  run "bash $BACKUP_SCRIPT"
else
  log_warn "backup_db.sh bulunamadı — yedek alınmıyor"
fi

# ── 2. Kod güncelleme ─────────────────────────────────────────────────────────
log_section "2 / 5 — Kod Güncelleme"

if [[ "$SKIP_PULL" == "true" ]]; then
  log_warn "Git pull atlandı (--skip-pull)"
else
  log_info "sprintmind-infra güncelleniyor..."
  run "git -C $INFRA_DIR pull --ff-only origin master"

  if [[ -n "$API_DIR" && -d "$API_DIR" ]]; then
    log_info "sprintmind-api güncelleniyor..."
    run "git -C $API_DIR pull --ff-only origin master"
  else
    log_warn "sprintmind-api dizini bulunamadı — API güncellenmedi"
  fi

  if [[ -n "$FRONTEND_DIR" && -d "$FRONTEND_DIR" ]]; then
    log_info "sprintmind-frontend güncelleniyor..."
    run "git -C $FRONTEND_DIR pull --ff-only origin master"
  else
    log_warn "sprintmind-frontend dizini bulunamadı — frontend güncellenmedi"
  fi
fi

# ── 3. Frontend build ────────────────────────────────────────────────────────
log_section "3 / 5 — Frontend Build"

if [[ -n "$FRONTEND_DIR" && -d "$FRONTEND_DIR" ]]; then
  log_info "npm install + vite build..."
  run "cd $FRONTEND_DIR && npm ci --prefer-offline"
  run "cd $FRONTEND_DIR && npm run build"
  log_info "Build çıktısı frontend-dist/ dizinine kopyalanıyor..."
  run "rm -rf ${INFRA_DIR}/frontend-dist/*"
  run "cp -r ${FRONTEND_DIR}/dist/. ${INFRA_DIR}/frontend-dist/"
  log_ok "Frontend build tamamlandı"
else
  log_warn "Frontend dizini yok — build atlandı"
fi

# ── 4. Docker image build + servis yenile ────────────────────────────────────
log_section "4 / 5 — Docker Build & Deploy"

log_info "API image build ediliyor..."
run "docker compose -f $COMPOSE_FILE build --no-cache api"

log_info "Servisler yeniden başlatılıyor (zero-downtime: postgres ve redis dokunulmaz)..."
run "docker compose -f $COMPOSE_FILE up -d --no-deps nginx api"

# ── 5. Sağlık kontrolü ────────────────────────────────────────────────────────
log_section "5 / 5 — Sağlık Kontrolü"

if [[ "$DRY_RUN" == "false" ]]; then
  wait_healthy "sprintmind-postgres" 30
  wait_healthy "sprintmind-redis" 30

  # API'nin ayağa kalkması için kısa süre bekle
  sleep 5

  log_info "Nginx sağlık uç noktası kontrol ediliyor..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/health || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    log_ok "Nginx → HTTP 200"
  else
    log_warn "Nginx /health → HTTP $HTTP_CODE (nginx yeniden başlatılıyor olabilir)"
  fi

  log_info "Çalışan containerlar:"
  docker ps --filter "name=sprintmind" \
    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
fi

# ── Özet ──────────────────────────────────────────────────────────────────────
echo ""
log_ok "Deployment tamamlandı — $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
echo "  Logları izlemek için:"
echo "    docker compose -f $COMPOSE_FILE logs -f api"
echo "  Geri almak için:"
echo "    docker compose -f $COMPOSE_FILE restart api"
echo ""
