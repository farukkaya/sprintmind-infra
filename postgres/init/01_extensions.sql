-- =============================================================================
-- SprintMind | 01_extensions.sql
-- PostgreSQL eklentileri — Docker init sırasında süper kullanıcı olarak çalışır
-- Bu dosya EF Core tarafından yönetilmez; docker-entrypoint-initdb.d/ altında
-- alfabetik olarak ilk çalışan dosyadır.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- pgvector: AI embedding vektörlerini saklamak ve cosine similarity araması
-- yapmak için gerekli. reference_items.embedding kolonu bu eklentiyi kullanır.
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS vector;

-- -----------------------------------------------------------------------------
-- pgcrypto: gen_random_uuid() fonksiyonu — tüm tablolarda UUID primary key
-- üretimi için kullanılır. PostgreSQL 13+ sürümlerinde built-in gelir ancak
-- açıkça enable etmek iyi pratiktir.
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------------------------------------------------------
-- pg_trgm: Trigram tabanlı metin araması. İleride madde başlığına göre
-- arama (LIKE '%...%') yapılacaksa GIN index ile birlikte kullanılır.
-- Faza 1'de aktif kullanılmaz; ileride ihtiyaç duyulduğunda hazır olsun.
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;