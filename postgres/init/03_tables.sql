-- =============================================================================
-- SprintMind | 03_tables.sql
-- Tüm tablo tanımlamaları — V1 + V2
-- Çalışma sırası: 01_extensions.sql → 02_enums.sql → 03_tables.sql
-- =============================================================================

-- =============================================================================
-- V1 TABLOLARI
-- =============================================================================

-- -----------------------------------------------------------------------------
-- users
-- ASP.NET Identity'nin AspNetUsers tablosunu genişletir.
-- Identity migration çalıştıktan SONRA bu tablo oluşturulur.
-- NOT: Bu tablo EF Core migration ile de oluşturulabilir; burada referans
--      amaçlı saf SQL olarak verilmiştir.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    full_name       VARCHAR(150)    NOT NULL,
    role            user_role       NOT NULL DEFAULT 'member',
    is_active       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    last_login_at   TIMESTAMPTZ     NULL,

    CONSTRAINT pk_users PRIMARY KEY (id)
);

COMMENT ON TABLE  users                IS 'Uygulama kullanıcıları — ASP.NET Identity AspNetUsers ile 1:1 ilişkili';
COMMENT ON COLUMN users.id             IS 'Primary key — AspNetUsers.Id ile aynı değer kullanılır';
COMMENT ON COLUMN users.full_name      IS 'Kullanıcının tam adı';
COMMENT ON COLUMN users.role           IS 'admin | senior | member';
COMMENT ON COLUMN users.is_active      IS 'false = soft delete, giriş yapamaz';
COMMENT ON COLUMN users.last_login_at  IS 'Son başarılı giriş zamanı (UTC)';


-- -----------------------------------------------------------------------------
-- sessions
-- Her oylama toplantısı bir satırdır.
-- session_type = planning  → standart ekip refinement
-- session_type = pre_effort → yalnızca Senior/Admin (V2)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS sessions (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    title           VARCHAR(255)    NOT NULL,
    session_type    session_type    NOT NULL DEFAULT 'planning',
    status          session_status  NOT NULL DEFAULT 'waiting',
    join_code       VARCHAR(8)      NOT NULL,
    created_by      UUID            NOT NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    started_at      TIMESTAMPTZ     NULL,
    completed_at    TIMESTAMPTZ     NULL,

    CONSTRAINT pk_sessions          PRIMARY KEY (id),
    CONSTRAINT fk_sessions_user     FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT,
    CONSTRAINT uq_sessions_joincode UNIQUE (join_code)
);

COMMENT ON TABLE  sessions               IS 'Oylama oturumu — her toplantı bir kayıt';
COMMENT ON COLUMN sessions.join_code     IS '8 haneli büyük harf kod — ekip bu kodla oturuma katılır';
COMMENT ON COLUMN sessions.session_type  IS 'planning: tüm ekip | pre_effort: sadece Senior+Admin (V2)';
COMMENT ON COLUMN sessions.status        IS 'waiting→active→voting→revealed→completed (tek yön)';
COMMENT ON COLUMN sessions.started_at    IS 'İlk madde analize girdiğinde set edilir';
COMMENT ON COLUMN sessions.completed_at  IS 'Oturum kapatıldığında set edilir';

CREATE INDEX IF NOT EXISTS idx_sessions_status
    ON sessions(status);

CREATE INDEX IF NOT EXISTS idx_sessions_created_by
    ON sessions(created_by);


-- -----------------------------------------------------------------------------
-- session_participants
-- sessions ↔ users many-to-many köprü tablosu.
-- SignalR bağlantı durumu da burada tutulur.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS session_participants (
    id              UUID            NOT NULL DEFAULT gen_random_uuid(),
    session_id      UUID            NOT NULL,
    user_id         UUID            NOT NULL,
    connection_id   VARCHAR(128)    NULL,
    is_online       BOOLEAN         NOT NULL DEFAULT FALSE,
    joined_at       TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_session_participants          PRIMARY KEY (id),
    CONSTRAINT fk_sp_session                    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    CONSTRAINT fk_sp_user                       FOREIGN KEY (user_id)    REFERENCES users(id)    ON DELETE CASCADE,
    CONSTRAINT uq_session_participants          UNIQUE (session_id, user_id)
);

COMMENT ON TABLE  session_participants               IS 'Oturum-kullanıcı köprü tablosu';
COMMENT ON COLUMN session_participants.connection_id IS 'SignalR Hub bağlantı ID — bağlantı kopunca güncellenir';
COMMENT ON COLUMN session_participants.is_online     IS 'Anlık bağlantı durumu — Redis fallback olarak bu kullanılır';

CREATE INDEX IF NOT EXISTS idx_sp_session_id
    ON session_participants(session_id);

CREATE INDEX IF NOT EXISTS idx_sp_user_id
    ON session_participants(user_id);


-- -----------------------------------------------------------------------------
-- session_items
-- Bir oturumdaki her backlog maddesi.
-- AI analiz çıktısı ve atanan puan bu tabloda saklanır.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS session_items (
    id                  UUID            NOT NULL DEFAULT gen_random_uuid(),
    session_id          UUID            NOT NULL,
    title               TEXT            NOT NULL,
    description         TEXT            NULL,
    order_index         INTEGER         NOT NULL DEFAULT 0,
    status              VARCHAR(20)     NOT NULL DEFAULT 'pending',
    -- AI alanları (Faza 2'de dolar)
    ai_suggested_sp     fibonacci_sp    NULL,
    ai_summary          TEXT            NULL,
    analyzed_at         TIMESTAMPTZ     NULL,
    -- Ön efor alanı (V2'de dolar)
    pre_effort_sp       fibonacci_sp    NULL,
    -- Nihai karar
    assigned_sp         fibonacci_sp    NULL,
    approval_type       approval_type   NULL,
    assigned_at         TIMESTAMPTZ     NULL,

    CONSTRAINT pk_session_items         PRIMARY KEY (id),
    CONSTRAINT fk_si_session            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
    CONSTRAINT chk_si_status            CHECK (status IN ('pending', 'analyzing', 'voting', 'completed'))
);

COMMENT ON TABLE  session_items                IS 'Oturumdaki her backlog maddesi';
COMMENT ON COLUMN session_items.order_index    IS 'Maddelerin oturum içindeki sırası';
COMMENT ON COLUMN session_items.status         IS 'pending→analyzing→voting→completed';
COMMENT ON COLUMN session_items.ai_suggested_sp IS 'AI önerisi — Faza 2 öncesi NULL';
COMMENT ON COLUMN session_items.pre_effort_sp  IS 'V2: ön efor konsensüs puanı';
COMMENT ON COLUMN session_items.assigned_sp    IS 'Ekibin nihai kararı — NULL ise henüz atanmamış';
COMMENT ON COLUMN session_items.approval_type  IS 'Puanın hangi yolla atandığı';

CREATE INDEX IF NOT EXISTS idx_si_session_id
    ON session_items(session_id, order_index);


-- -----------------------------------------------------------------------------
-- votes
-- Kullanıcıların her madde için verdiği oylar.
-- (session_item_id, user_id) UNIQUE — bir kullanıcı bir madde için tek oy.
-- Reveal öncesi yeniden oy verilebilir (UPSERT).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS votes (
    id                  UUID            NOT NULL DEFAULT gen_random_uuid(),
    session_item_id     UUID            NOT NULL,
    user_id             UUID            NOT NULL,
    value               fibonacci_sp    NOT NULL,
    is_revealed         BOOLEAN         NOT NULL DEFAULT FALSE,
    voted_at            TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_votes             PRIMARY KEY (id),
    CONSTRAINT fk_votes_item        FOREIGN KEY (session_item_id) REFERENCES session_items(id) ON DELETE CASCADE,
    CONSTRAINT fk_votes_user        FOREIGN KEY (user_id)         REFERENCES users(id)         ON DELETE CASCADE,
    CONSTRAINT uq_votes_item_user   UNIQUE (session_item_id, user_id)
);

COMMENT ON TABLE  votes              IS 'Kullanıcı oyları — reveal öncesi UPSERT ile değiştirilebilir';
COMMENT ON COLUMN votes.is_revealed  IS 'FALSE iken değer SignalR üzerinden gizlenir, sadece "oy verildi" sinyali gider';
COMMENT ON COLUMN votes.voted_at     IS 'Oy verildiği veya güncellendiği son zaman';

CREATE INDEX IF NOT EXISTS idx_votes_item_id
    ON votes(session_item_id);


-- -----------------------------------------------------------------------------
-- reference_items
-- AI'ın SP önerisi üretirken kullandığı eğitim verisi.
-- embedding kolonu pgvector ile tutulur.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reference_items (
    id              UUID                    NOT NULL DEFAULT gen_random_uuid(),
    title           TEXT                    NOT NULL,
    description     TEXT                    NULL,
    final_sp        fibonacci_sp            NOT NULL,
    tags            TEXT[]                  NULL,
    embedding       vector(768)             NULL,
    source          reference_item_source   NOT NULL DEFAULT 'manual',
    created_at      TIMESTAMPTZ             NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ             NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_reference_items PRIMARY KEY (id)
);

COMMENT ON TABLE  reference_items            IS 'AI eğitim verisi — geçmiş oylama sonuçları';
COMMENT ON COLUMN reference_items.embedding  IS 'nomic-embed-text çıktısı, 768 boyutlu vektör';
COMMENT ON COLUMN reference_items.tags       IS 'Serbest etiketler: {backend, frontend, db, devops, ...}';
COMMENT ON COLUMN reference_items.source     IS 'manual: elle eklendi | learned: oturumdan öğrenildi | imported: entegrasyon';
COMMENT ON COLUMN reference_items.updated_at IS 'Embedding yenilendiğinde güncellenir';

-- GIN index: tags dizisi araması için
CREATE INDEX IF NOT EXISTS idx_reference_items_tags
    ON reference_items USING GIN(tags);

-- IVFFlat index: cosine similarity araması için
-- NOT: Bu index embedding alanı dolduktan sonra anlamlı hale gelir.
--      Başlangıçta az veri varken performans farkı ihmal edilebilir.
--      lists parametresi = sqrt(beklenen satır sayısı) olarak ayarlanır.
CREATE INDEX IF NOT EXISTS idx_reference_items_embedding
    ON reference_items USING ivfflat (embedding vector_cosine_ops)
    WITH (lists = 50);

-- Trigram index: başlık araması için (pg_trgm eklentisi gerekli)
CREATE INDEX IF NOT EXISTS idx_reference_items_title_trgm
    ON reference_items USING GIN(title gin_trgm_ops);


-- =============================================================================
-- V2 TABLOLARI
-- =============================================================================

-- -----------------------------------------------------------------------------
-- pre_effort_sessions
-- Ön efor toplantıları. Yalnızca Senior + Admin katılabilir.
-- linked_session_id ile ekip refinement oturumuna bağlanabilir (opsiyonel).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pre_effort_sessions (
    id                  UUID            NOT NULL DEFAULT gen_random_uuid(),
    title               VARCHAR(255)    NOT NULL,
    status              session_status  NOT NULL DEFAULT 'waiting',
    join_code           VARCHAR(8)      NOT NULL,
    created_by          UUID            NOT NULL,
    linked_session_id   UUID            NULL,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ     NULL,

    CONSTRAINT pk_pre_effort_sessions           PRIMARY KEY (id),
    CONSTRAINT fk_pes_created_by                FOREIGN KEY (created_by)        REFERENCES users(id)    ON DELETE RESTRICT,
    CONSTRAINT fk_pes_linked_session            FOREIGN KEY (linked_session_id) REFERENCES sessions(id) ON DELETE SET NULL,
    CONSTRAINT uq_pre_effort_sessions_joincode  UNIQUE (join_code)
);

COMMENT ON TABLE  pre_effort_sessions                    IS 'V2: Ön efor oturumları — sadece Senior+Admin katılır';
COMMENT ON COLUMN pre_effort_sessions.linked_session_id  IS 'Bağlı ekip refinement oturumu — NULL olabilir';
COMMENT ON COLUMN pre_effort_sessions.join_code          IS 'Sadece Senior/Admin rolüne gösterilen katılım kodu';

CREATE INDEX IF NOT EXISTS idx_pes_created_by
    ON pre_effort_sessions(created_by);


-- -----------------------------------------------------------------------------
-- pre_effort_votes
-- Ön efor oturumunda verilen oylar.
-- consensus_sp: tartışma sonrası grubun uzlaştığı puan.
-- Bu değer session_items.pre_effort_sp alanını doldurur.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pre_effort_votes (
    id                      UUID            NOT NULL DEFAULT gen_random_uuid(),
    pre_effort_session_id   UUID            NOT NULL,
    session_item_id         UUID            NOT NULL,
    user_id                 UUID            NOT NULL,
    value                   fibonacci_sp    NOT NULL,
    consensus_sp            fibonacci_sp    NULL,
    voted_at                TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_pre_effort_votes          PRIMARY KEY (id),
    CONSTRAINT fk_pev_session               FOREIGN KEY (pre_effort_session_id) REFERENCES pre_effort_sessions(id) ON DELETE CASCADE,
    CONSTRAINT fk_pev_item                  FOREIGN KEY (session_item_id)       REFERENCES session_items(id)       ON DELETE CASCADE,
    CONSTRAINT fk_pev_user                  FOREIGN KEY (user_id)               REFERENCES users(id)               ON DELETE CASCADE,
    CONSTRAINT uq_pre_effort_votes          UNIQUE (pre_effort_session_id, session_item_id, user_id)
);

COMMENT ON TABLE  pre_effort_votes               IS 'V2: Ön efor oturumu oyları';
COMMENT ON COLUMN pre_effort_votes.consensus_sp  IS 'Tartışma sonrası konsensüs — bu değer session_items.pre_effort_sp''yi günceller';

CREATE INDEX IF NOT EXISTS idx_pev_session_item
    ON pre_effort_votes(pre_effort_session_id, session_item_id);


-- -----------------------------------------------------------------------------
-- ai_analyses
-- Her madde için AI analiz çıktısının tam kaydı.
-- Audit trail + model performans izleme amaçlı saklanır.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ai_analyses (
    id                  UUID            NOT NULL DEFAULT gen_random_uuid(),
    session_item_id     UUID            NOT NULL,
    model_name          VARCHAR(100)    NOT NULL,
    suggested_sp        fibonacci_sp    NOT NULL,
    summary             TEXT            NOT NULL,
    reasoning           TEXT            NULL,
    similar_items       JSONB           NULL,
    prompt_tokens       INTEGER         NULL,
    completion_tokens   INTEGER         NULL,
    duration_ms         INTEGER         NULL,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_ai_analyses       PRIMARY KEY (id),
    CONSTRAINT fk_aa_item           FOREIGN KEY (session_item_id) REFERENCES session_items(id) ON DELETE CASCADE
);

COMMENT ON TABLE  ai_analyses                IS 'V2: AI analiz çıktıları — her analiz isteği bir kayıt';
COMMENT ON COLUMN ai_analyses.model_name     IS 'Kullanılan Ollama model adı (ör. mistral:7b)';
COMMENT ON COLUMN ai_analyses.similar_items  IS 'JSON: [{id, title, sp, similarity}, ...] — bulunan benzer referanslar';
COMMENT ON COLUMN ai_analyses.duration_ms    IS 'Ollama yanıt süresi — model performans izleme için';

CREATE INDEX IF NOT EXISTS idx_aa_session_item_id
    ON ai_analyses(session_item_id);


-- -----------------------------------------------------------------------------
-- deviation_logs
-- Ön efor puanı ile ekip kararı arasındaki sapma kaydı.
-- deviation_score = 0.0 → tam uyum, 1.0 → maksimum sapma
-- ai_feedback_sent = false olan kayıtlar AI öğrenme kuyruğuna alınır.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS deviation_logs (
    id                      UUID                    NOT NULL DEFAULT gen_random_uuid(),
    session_item_id         UUID                    NOT NULL,
    pre_effort_sp           fibonacci_sp            NOT NULL,
    team_sp                 fibonacci_sp            NOT NULL,
    ai_suggested_sp         fibonacci_sp            NULL,
    deviation_score         FLOAT                   NOT NULL,
    direction               deviation_direction     NOT NULL DEFAULT 'none',
    ai_feedback_sent        BOOLEAN                 NOT NULL DEFAULT FALSE,
    ai_feedback_sent_at     TIMESTAMPTZ             NULL,
    created_at              TIMESTAMPTZ             NOT NULL DEFAULT NOW(),

    CONSTRAINT pk_deviation_logs        PRIMARY KEY (id),
    CONSTRAINT fk_dl_item               FOREIGN KEY (session_item_id) REFERENCES session_items(id) ON DELETE CASCADE,
    CONSTRAINT uq_deviation_logs_item   UNIQUE (session_item_id),
    CONSTRAINT chk_deviation_score      CHECK (deviation_score >= 0.0 AND deviation_score <= 1.0)
);

COMMENT ON TABLE  deviation_logs                     IS 'V2: Ön efor ile ekip kararı sapma kayıtları';
COMMENT ON COLUMN deviation_logs.deviation_score     IS '0.0 = tam uyum, 1.0 = maksimum sapma — Fibonacci index farkı normalize edilir';
COMMENT ON COLUMN deviation_logs.direction           IS 'up: ekip puanı yükseltti | down: düşürdü | none: aynı';
COMMENT ON COLUMN deviation_logs.ai_feedback_sent    IS 'TRUE olunca bu sapma AI öğrenme verisine eklendi';

-- Partial index: AI'a henüz gönderilmemiş sapmaları hızlı bulmak için
CREATE INDEX IF NOT EXISTS idx_dl_feedback_pending
    ON deviation_logs(ai_feedback_sent)
    WHERE ai_feedback_sent = FALSE;