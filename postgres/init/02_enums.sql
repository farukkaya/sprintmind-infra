-- =============================================================================
-- SprintMind | 02_enums.sql
-- PostgreSQL ENUM tip tanımlamaları
-- Bu dosya 01_extensions.sql'den SONRA çalışır (alfabetik sıra).
-- EF Core bu tipleri tanır; migration'larda HasColumnType("...") ile referans
-- verilir. Tipler bir kez oluşturulur — değişiklik için ALTER TYPE gerekir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- user_role
-- Kullanıcının sistemdeki rolü.
--   admin   → kullanıcı yönetimi, referans madde yönetimi, tüm raporlar
--   senior  → ön efor oturumu açabilir, planning oturumuna katılabilir
--   member  → yalnızca planning oturumuna katılabilir
-- -----------------------------------------------------------------------------
CREATE TYPE user_role AS ENUM (
    'admin',
    'senior',
    'member'
);

-- -----------------------------------------------------------------------------
-- session_type
-- Oturumun hangi amaçla açıldığını belirtir.
--   planning    → tüm ekibin katıldığı standart Fibonacci oylama oturumu
--   pre_effort  → yalnızca Senior + Admin'in katıldığı ön efor oturumu (V2)
-- -----------------------------------------------------------------------------
CREATE TYPE session_type AS ENUM (
    'planning',
    'pre_effort'
);

-- -----------------------------------------------------------------------------
-- session_status
-- Oturum yaşam döngüsü — tek yönlü ilerleme, geri dönüş yoktur.
--
--   waiting   → oturum oluşturuldu, katılımcılar bekleniyor
--   active    → oturum başladı, madde tartışılıyor
--   voting    → oy verme açıldı, kartlar seçiliyor
--   revealed  → oylar açıldı, tartışma / konsensüs aşaması
--   completed → puan atandı, bir sonraki maddeye geçildi veya oturum kapandı
-- -----------------------------------------------------------------------------
CREATE TYPE session_status AS ENUM (
    'waiting',
    'active',
    'voting',
    'revealed',
    'completed'
);

-- -----------------------------------------------------------------------------
-- fibonacci_sp
-- Geçerli Story Point değerleri — Fibonacci serisi + soru işareti.
--   '?'  → kullanıcı fikir beyan etmek istemiyor / bilgisi yok
--   '0'  → iş yok / trivial (opsiyonel kullanım)
-- -----------------------------------------------------------------------------
CREATE TYPE fibonacci_sp AS ENUM (
    '0',
    '1',
    '2',
    '3',
    '5',
    '8',
    '13',
    '21',
    '?'
);

-- -----------------------------------------------------------------------------
-- approval_type
-- Bir session_item'a puanın hangi yolla atandığını gösterir.
--   ai_approved          → ekip AI önerisini direkt onayladı
--   pre_effort_approved  → ekip ön efor konsensüs puanını onayladı (V2)
--   team_voted           → Fibonacci oylama yapıldı, ekip oylamayla karar verdi
-- -----------------------------------------------------------------------------
CREATE TYPE approval_type AS ENUM (
    'ai_approved',
    'pre_effort_approved',
    'team_voted'
);

-- -----------------------------------------------------------------------------
-- reference_item_source
-- Bir referans maddenin sisteme nasıl girdiğini belirtir.
--   manual    → admin tarafından elle eklendi (seed verisi dahil)
--   learned   → tamamlanan bir oturumdan otomatik öğrenildi
--   imported  → Jira / Azure DevOps entegrasyonuyla içe aktarıldı (Faza 4)
-- -----------------------------------------------------------------------------
CREATE TYPE reference_item_source AS ENUM (
    'manual',
    'learned',
    'imported'
);

-- -----------------------------------------------------------------------------
-- deviation_direction
-- Ön efor puanına göre ekip kararının yönü (V2).
--   up    → ekip puanı yükseltti  (pre_effort < team)
--   down  → ekip puanı düşürdü    (pre_effort > team)
--   none  → tam uyum              (pre_effort = team)
-- -----------------------------------------------------------------------------
CREATE TYPE deviation_direction AS ENUM (
    'up',
    'down',
    'none'
);