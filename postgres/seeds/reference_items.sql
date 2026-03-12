-- =============================================================================
-- SprintMind | seeds/reference_items.sql
-- Başlangıç eğitim verisi — 25 madde
-- Dil: Türkçe | Kategoriler: Backend/API, Frontend/UI
--
-- NOT: embedding kolonu kasıtlı olarak NULL bırakılmıştır.
--      Uygulama ilk çalıştığında her kayıt için Ollama'dan
--      (nomic-embed-text) embedding üretilip bu kolon doldurulur.
--      Bu işlem Infrastructure katmanındaki ReferenceItemSeeder
--      servisi tarafından startup'ta otomatik yapılır.
-- =============================================================================

INSERT INTO reference_items (id, title, description, final_sp, tags, source)
VALUES

-- =============================================================================
-- BACKEND / API  (13 madde)
-- =============================================================================

(
    gen_random_uuid(),
    'JWT kimlik doğrulama altyapısı kurulumu',
    'ASP.NET Core''da JWT access token ve refresh token mekanizması kurulacak. Token üretimi, doğrulama middleware''i ve refresh endpoint yazılacak. Redis''te refresh token saklanacak.',
    '8',
    ARRAY['backend', 'auth', 'security', 'redis'],
    'manual'
),

(
    gen_random_uuid(),
    'Kullanıcı kayıt ve giriş endpoint''leri',
    'POST /auth/register ve POST /auth/login endpoint''leri yazılacak. Input validasyonu, hata mesajları ve HTTP durum kodları standartlaştırılacak.',
    '3',
    ARRAY['backend', 'auth', 'api'],
    'manual'
),

(
    gen_random_uuid(),
    'Rol tabanlı yetkilendirme middleware''i',
    'Admin, Senior ve Member rolleri için ASP.NET Core policy tanımları yazılacak. Endpoint bazında [Authorize(Roles = "...")] attribute''ları uygulanacak.',
    '3',
    ARRAY['backend', 'auth', 'middleware'],
    'manual'
),

(
    gen_random_uuid(),
    'SignalR Hub kurulumu ve temel event''ler',
    'Gerçek zamanlı oylama için SignalR Hub oluşturulacak. UserJoined, UserLeft, CardSelected, VotesRevealed ve SessionUpdated event''leri yazılacak.',
    '8',
    ARRAY['backend', 'signalr', 'realtime'],
    'manual'
),

(
    gen_random_uuid(),
    'Oturum oluşturma ve join_code üretimi',
    'POST /sessions endpoint''i yazılacak. 8 haneli benzersiz join_code üretilecek, çakışma durumunda yeniden deneme mekanizması eklenecek.',
    '3',
    ARRAY['backend', 'api', 'sessions'],
    'manual'
),

(
    gen_random_uuid(),
    'Oylama endpoint''leri ve oy kaydetme',
    'POST /sessions/{id}/votes endpoint''i yazılacak. Aynı kullanıcı aynı madde için oy değiştirebilmeli (UPSERT). Reveal öncesi oy değerleri gizli tutulacak.',
    '5',
    ARRAY['backend', 'api', 'voting'],
    'manual'
),

(
    gen_random_uuid(),
    'EF Core DbContext ve entity konfigürasyonları',
    'AppDbContext oluşturulacak. Tüm entity''ler için Fluent API konfigürasyonları (ilişkiler, indexler, kolon tipleri) yazılacak. İlk migration üretilecek.',
    '5',
    ARRAY['backend', 'database', 'efcore'],
    'manual'
),

(
    gen_random_uuid(),
    'Redis bağlantısı ve oturum state yönetimi',
    'StackExchange.Redis entegrasyonu yapılacak. Aktif oturum durumu, bağlı kullanıcılar ve açılmamış oylar Redis''te saklanacak. TTL stratejisi belirlenecek.',
    '5',
    ARRAY['backend', 'redis', 'cache'],
    'manual'
),

(
    gen_random_uuid(),
    'Ollama HTTP istemcisi ve prompt servisi',
    'Ollama API''ye HTTP isteği atan wrapper servisi yazılacak. Prompt şablonu parametrik hale getirilecek. JSON response parse edilecek ve hata durumları yönetilecek.',
    '5',
    ARRAY['backend', 'ai', 'ollama'],
    'manual'
),

(
    gen_random_uuid(),
    'pgvector embedding üretimi ve benzerlik araması',
    'nomic-embed-text modeli ile metin embedding üretilecek. cosine similarity ile en benzer 5 referans madde bulunacak. IVFFlat index kullanımı optimize edilecek.',
    '8',
    ARRAY['backend', 'ai', 'pgvector', 'database'],
    'manual'
),

(
    gen_random_uuid(),
    'Global exception handler middleware',
    'Tüm controller''lardan fırlayan exception''ları yakalayan middleware yazılacak. ProblemDetails RFC 7807 formatında hata response''ları döndürülecek. Loglama eklenecek.',
    '3',
    ARRAY['backend', 'middleware', 'errorhandling'],
    'manual'
),

(
    gen_random_uuid(),
    'Pagination ve filtreleme için generic repository',
    'IRepository<T> arayüzü ve generic implementasyonu yazılacak. GetAll, GetById, Add, Update, Delete metodları eklenecek. Sayfalama ve sıralama desteklenecek.',
    '5',
    ARRAY['backend', 'database', 'architecture'],
    'manual'
),

(
    gen_random_uuid(),
    'Sapma skoru hesaplama servisi',
    'Ön efor puanı ile ekip kararı arasındaki sapmayı hesaplayan servis yazılacak. Fibonacci indeks normalizasyonu uygulanacak. Sonuç deviation_logs tablosuna kaydedilecek.',
    '3',
    ARRAY['backend', 'business-logic', 'v2'],
    'manual'
),

-- =============================================================================
-- FRONTEND / UI  (12 madde)
-- =============================================================================

(
    gen_random_uuid(),
    'Vite + React + TypeScript proje kurulumu',
    'Vite ile React 18 + TypeScript projesi oluşturulacak. Tailwind CSS, ESLint, Prettier konfigürasyonları yapılacak. Klasör yapısı (pages/components/hooks/services) oluşturulacak.',
    '2',
    ARRAY['frontend', 'setup', 'tooling'],
    'manual'
),

(
    gen_random_uuid(),
    'Login sayfası ve JWT token yönetimi',
    'Email + şifre ile giriş formu yapılacak. JWT access token Zustand store''a kaydedilecek. Token expiry kontrolü ve otomatik refresh mekanizması eklenecek.',
    '5',
    ARRAY['frontend', 'auth', 'state'],
    'manual'
),

(
    gen_random_uuid(),
    'Korumalı route yapısı (PrivateRoute)',
    'React Router ile PrivateRoute bileşeni yazılacak. Token yoksa /login''e yönlendirme yapılacak. Rol bazlı sayfa erişim kontrolü eklenecek.',
    '3',
    ARRAY['frontend', 'auth', 'routing'],
    'manual'
),

(
    gen_random_uuid(),
    'Lobby sayfası — oturum listesi ve oluşturma',
    'Aktif oturumlar listelenecek. Yeni oturum oluşturma modalı yapılacak. join_code ile mevcut oturuma katılım formu eklenecek. Loading ve empty state''ler tasarlanacak.',
    '5',
    ARRAY['frontend', 'ui', 'sessions'],
    'manual'
),

(
    gen_random_uuid(),
    'SignalR bağlantı hook''u (useSignalR)',
    'SignalR HubConnection''ı yöneten custom hook yazılacak. Bağlantı kurma, yeniden bağlanma ve temizleme (cleanup) işlemleri yönetilecek. Event listener''lar hook içinde tanımlanacak.',
    '5',
    ARRAY['frontend', 'signalr', 'hooks', 'realtime'],
    'manual'
),

(
    gen_random_uuid(),
    'Oturum ekranı sol panel — madde girişi',
    'Madde başlığı ve açıklama metin alanları yapılacak. Referans madde önerileri gösterilecek. "AI ile Analiz Et" butonu eklenecek. Mevcut madde listesi sidebar''da gösterilecek.',
    '5',
    ARRAY['frontend', 'ui', 'session'],
    'manual'
),

(
    gen_random_uuid(),
    'Fibonacci kart bileşeni ve oylama paneli',
    'Her Fibonacci değeri (1,2,3,5,8,13,21,?) için kart bileşeni yapılacak. Seçili kart vurgulanacak. Oylar açılana kadar diğer kullanıcıların seçimleri gizlenecek.',
    '5',
    ARRAY['frontend', 'ui', 'voting', 'components'],
    'manual'
),

(
    gen_random_uuid(),
    'AI analiz sonucu gösterim bileşeni',
    'AI''ın ürettiği teknik özet, SP önerisi ve gerekçe gösterilecek. Benzer referans maddeler listelencek. Loading skeleton ve hata durumu tasarlanacak.',
    '3',
    ARRAY['frontend', 'ui', 'ai', 'components'],
    'manual'
),

(
    gen_random_uuid(),
    'Katılımcı listesi ve oy durumu göstergesi',
    'Oturumdaki kullanıcılar anlık listelenecek. Oy veren / vermeyenler farklı ikonla gösterilecek. Online/offline durumu SignalR event''leriyle güncellenecek.',
    '3',
    ARRAY['frontend', 'ui', 'realtime', 'components'],
    'manual'
),

(
    gen_random_uuid(),
    'Ön efor puanı badge bileşeni (V2)',
    'Ekip refinement ekranında ön efor konsensüs puanı altın renk badge ile gösterilecek. "Ön Eforu Onayla" butonu eklenecek. Puan yoksa badge gizlenecek.',
    '2',
    ARRAY['frontend', 'ui', 'v2', 'components'],
    'manual'
),

(
    gen_random_uuid(),
    'Sapma analizi rapor sayfası',
    '/report sayfası yapılacak. Sprint bazında ön efor ve ekip kararları tablo halinde gösterilecek. Fark ve durum (konsensüs/yükseltildi/düşürüldü) renk kodlu badge ile gösterilecek.',
    '5',
    ARRAY['frontend', 'ui', 'reports', 'v2'],
    'manual'
),

(
    gen_random_uuid(),
    'Axios interceptor ve hata yönetimi',
    'Tüm API isteklerine Authorization header ekleyen interceptor yazılacak. 401 response''unda token refresh denenecek, başarısız olursa logout yapılacak. Toast bildirimleri eklenecek.',
    '3',
    ARRAY['frontend', 'api', 'errorhandling'],
    'manual'
);