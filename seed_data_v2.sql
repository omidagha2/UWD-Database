-- =============================================================
-- Seed Data v2  — Fictional but test-ready dataset
-- Target schema : schema_v2.sql
-- Notes:
--   * Run AFTER schema_v2.sql on a fresh DB (SERIAL ids start at 1).
--   * users.total_score is intentionally seeded as 0; the AFTER INSERT
--     trigger on daily_challenge_submissions will accumulate it.
--   * words.length is omitted on purpose (auto-filled by trigger).
--   * friendships are pre-normalized (user_id_1 < user_id_2) to match
--     fn_normalize_friendship and avoid UNIQUE collisions.
-- =============================================================

BEGIN;

-- =====================  1) USERS  ===========================
-- password_hash values are placeholder bcrypt-format strings (fake).
INSERT INTO users
    (username, email, password_hash, is_guest, is_admin, is_verified,
     coins, total_score, is_report_blocked, upgraded_at)
VALUES
    -- 1: super admin
    ('admin',      'admin@game.local',   '$2b$12$AdminHashPlaceholder000000000000000000000000000000', FALSE, TRUE,  TRUE,  9999, 0, FALSE, NULL),
    -- 2: normal verified user, active player
    ('alice',      'alice@game.local',   '$2b$12$AliceHashPlaceholder000000000000000000000000000000', FALSE, FALSE, TRUE,  500,  0, FALSE, NULL),
    -- 3: normal verified user
    ('bob',        'bob@game.local',     '$2b$12$BobHashPlaceholder00000000000000000000000000000000', FALSE, FALSE, TRUE,  320,  0, FALSE, NULL),
    -- 4: registered but NOT verified (test email-verification flow)
    ('charlie',    'charlie@game.local', '$2b$12$CharlieHashPlaceholder0000000000000000000000000000', FALSE, FALSE, FALSE, 50,   0, FALSE, NULL),
    -- 5: verified, premium subscriber
    ('diana',      'diana@game.local',   '$2b$12$DianaHashPlaceholder00000000000000000000000000000', FALSE, FALSE, TRUE,  1200, 0, FALSE, NULL),
    -- 6: user who got report-blocked (abuse testing)
    ('eve',        'eve@game.local',     '$2b$12$EveHashPlaceholder00000000000000000000000000000000', FALSE, FALSE, TRUE,  10,   0, TRUE,  NULL),
    -- 7: guest account (no email / no password)
    ('guest_7f3a', NULL,                 NULL,                                                          TRUE,  FALSE, FALSE, 0,    0, FALSE, NULL),
    -- 8: another guest
    ('guest_b21c', NULL,                 NULL,                                                          TRUE,  FALSE, FALSE, 0,    0, FALSE, NULL),
    -- 9: guest that later upgraded to registered (upgraded_at set)
    ('frank',      'frank@game.local',   '$2b$12$FrankHashPlaceholder00000000000000000000000000000', FALSE, FALSE, TRUE,  150,  0, FALSE, CURRENT_TIMESTAMP - INTERVAL '5 days'),
    -- 10: secondary moderator-style verified user
    ('grace',      'grace@game.local',   '$2b$12$GraceHashPlaceholder00000000000000000000000000000', FALSE, FALSE, TRUE,  800,  0, FALSE, NULL);


-- =====================  2) GAMES  ===========================
INSERT INTO games
    (name, description, has_daily_challenge, has_multiplayer, status)
VALUES
    ('Wordle Clone',  'Guess the hidden word in limited tries.',        TRUE,  FALSE, 'active'),  -- 1
    ('Anagram Rush',  'Rearrange letters to form valid words.',         TRUE,  TRUE,  'active'),  -- 2
    ('Word Battle',   'Real-time multiplayer word duel.',               FALSE, TRUE,  'active'),  -- 3
    ('Crossword Mini','Daily small crossword.',                         TRUE,  FALSE, 'inactive');-- 4 (test inactive state)

-- =====================  3) GAME VARIATIONS  =================
INSERT INTO game_variations
    (game_id, name, params_json, player_count)
VALUES
    (1, 'Classic 5-letter',  '{"length": 5, "tries": 6}',                 1),  -- 1
    (1, 'Hard 6-letter',     '{"length": 6, "tries": 6, "hard": true}',   1),  -- 2 (premium-gated later)
    (2, 'Anagram Solo',      '{"min_len": 4, "time": 60}',                1),  -- 3
    (2, 'Anagram Versus',    '{"min_len": 4, "time": 90}',                2),  -- 4
    (3, 'Duel 1v1',          '{"rounds": 5}',                             2),  -- 5
    (3, 'Royale 4P',         '{"rounds": 3, "max_players": 4}',           4),  -- 6 (premium-gated later)
    (4, 'Mini 5x5',          '{"grid": 5}',                               1);  -- 7

-- =====================  4) WORDS  ===========================
-- length column omitted -> trigger fn_set_word_length fills it.
INSERT INTO words (text, language, difficulty_level, is_soft_deleted)
VALUES
    ('apple',   'en', 1, FALSE),  -- 1
    ('brain',   'en', 1, FALSE),  -- 2
    ('crane',   'en', 2, FALSE),  -- 3
    ('puzzle',  'en', 2, FALSE),  -- 4
    ('rhythm',  'en', 3, FALSE),  -- 5
    ('jazz',    'en', 3, FALSE),  -- 6
    ('galaxy',  'en', 2, FALSE),  -- 7
    ('zephyr',  'en', 3, FALSE),  -- 8
    ('badword', 'en', 1, TRUE),   -- 9  (soft-deleted, test filtering)
    ('کتاب',    'fa', 1, FALSE),  -- 10 (Persian, multibyte length test)
    ('برنامه',  'fa', 2, FALSE),  -- 11
    ('سلام',    'fa', 1, FALSE);  -- 12


-- =====================  5) WORD REPORTS  ====================
INSERT INTO word_reports (word_id, reporter_user_id, reason, status)
VALUES
    (9,  2, 'Offensive content.',          'pending'),   -- 1
    (6,  3, 'Not a common word.',          'reviewed'),  -- 2
    (8,  5, 'Too hard / typo suspected.',  'pending'),   -- 3
    (9,  6, 'Duplicate report (blocked).', 'dismissed'); -- 4

-- =====================  6) EMAIL VERIFICATION TOKENS  =======
INSERT INTO email_verification_tokens (user_id, token, expires_at, used_at)
VALUES
    -- charlie (4): active, unused token
    (4, 'verify-charlie-abc123token0001', CURRENT_TIMESTAMP + INTERVAL '24 hours', NULL),
    -- alice (2): already used token
    (2, 'verify-alice-used-token-0002',   CURRENT_TIMESTAMP - INTERVAL '10 days',  CURRENT_TIMESTAMP - INTERVAL '10 days'),
    -- charlie (4): expired token (test cleanup / re-send)
    (4, 'verify-charlie-expired-0003',    CURRENT_TIMESTAMP - INTERVAL '2 days',   NULL);

-- =====================  7) DAILY CHALLENGES  ================
INSERT INTO daily_challenges
    (game_id, variation_id, challenge_date, data_json, status)
VALUES
    (1, 1, CURRENT_DATE,                  '{"answer": "crane"}',  'active'),   -- 1 today
    (1, 1, CURRENT_DATE - INTERVAL '1 day','{"answer": "apple"}', 'active'),   -- 2 yesterday
    (2, 3, CURRENT_DATE,                  '{"letters": "traise"}','active'),   -- 3 today (anagram)
    (4, 7, CURRENT_DATE,                  '{"grid": "..."}',      'active');   -- 4 (inactive game, edge test)

-- =====================  8) DAILY CHALLENGE SUBMISSIONS  =====
-- These INSERTs FIRE the score trigger -> users.total_score updates.
INSERT INTO daily_challenge_submissions
    (user_id, daily_challenge_id, score)
VALUES
    (2, 1, 100),  -- alice  -> +100
    (3, 1, 80),   -- bob    -> +80
    (5, 1, 120),  -- diana  -> +120
    (2, 2, 90),   -- alice  -> +90  (alice total = 190)
    (3, 3, 70),   -- bob    -> +70  (bob total = 150)
    (9, 1, 60);   -- frank  -> +60


-- =====================  9) SUBSCRIPTION PLANS  ==============
INSERT INTO subscription_plans (name, price_coins, duration_days, features_json)
VALUES
    ('Free',    0,    36500, '{"ads": true,  "premium_variations": false}'),  -- 1
    ('Premium', 500,  30,    '{"ads": false, "premium_variations": true}'),   -- 2
    ('Pro',     1200, 90,    '{"ads": false, "premium_variations": true, "priority_match": true}'); -- 3

-- =====================  10) PLAN <-> VARIATION ACCESS  ======
-- Gate variation 2 (Hard 6-letter) and 6 (Royale 4P) behind paid plans.
-- Ungated variations remain free for everyone (per fn_user_has_variation_access).
INSERT INTO plan_variation_access (plan_id, variation_id)
VALUES
    (2, 2),  -- Premium -> Hard 6-letter
    (2, 6),  -- Premium -> Royale 4P
    (3, 2),  -- Pro     -> Hard 6-letter
    (3, 6);  -- Pro     -> Royale 4P

-- =====================  11) USER SUBSCRIPTIONS  =============
INSERT INTO user_subscriptions
    (user_id, plan_id, starts_at, ends_at, is_active, status)
VALUES
    -- diana (5): active Premium
    (5, 2, CURRENT_TIMESTAMP - INTERVAL '5 days',  CURRENT_TIMESTAMP + INTERVAL '25 days', TRUE,  'active'),
    -- grace (10): active Pro
    (10,3, CURRENT_TIMESTAMP - INTERVAL '10 days', CURRENT_TIMESTAMP + INTERVAL '80 days', TRUE,  'active'),
    -- bob (3): EXPIRED Premium (test sp_expire_subscriptions cursor)
    (3, 2, CURRENT_TIMESTAMP - INTERVAL '40 days', CURRENT_TIMESTAMP - INTERVAL '10 days', TRUE,  'active'),
    -- alice (2): cancelling (still valid until ends_at)
    (2, 2, CURRENT_TIMESTAMP - INTERVAL '15 days', CURRENT_TIMESTAMP + INTERVAL '15 days', TRUE,  'cancelling');


-- =====================  12) FRIENDSHIPS  ====================
-- Pre-normalized: user_id_1 < user_id_2. action_user_id = initiator.
INSERT INTO friendships (user_id_1, user_id_2, action_user_id, status)
VALUES
    (2, 3,  2, 'accepted'),  -- alice <-> bob (accepted)
    (2, 5,  5, 'accepted'),  -- alice <-> diana (accepted)
    (3, 5,  3, 'pending'),   -- bob -> diana (pending request)
    (2, 4,  4, 'pending'),   -- charlie -> alice (pending)
    (5, 6,  5, 'blocked'),   -- diana blocked eve
    (3, 10, 10,'accepted');  -- grace <-> bob

-- =====================  13) MULTIPLAYER ROOMS  ==============
INSERT INTO multiplayer_rooms
    (room_code, game_id, variation_id, created_by_user_id, admin_user_id,
     is_private, status, started_at, ended_at)
VALUES
    -- 1: public lobby, waiting for players
    ('ROOM01', 3, 5, 2,  2,  FALSE, 'lobby',    NULL, NULL),
    -- 2: private game in progress
    ('ROOM02', 3, 5, 5,  5,  TRUE,  'playing',  CURRENT_TIMESTAMP - INTERVAL '5 minutes', NULL),
    -- 3: finished match
    ('ROOM03', 2, 4, 3,  3,  FALSE, 'finished', CURRENT_TIMESTAMP - INTERVAL '1 hour', CURRENT_TIMESTAMP - INTERVAL '40 minutes'),
    -- 4: premium Royale lobby (variation 6, gated)
    ('ROOM04', 3, 6, 10, 10, FALSE, 'lobby',    NULL, NULL);

-- =====================  14) ROOM PARTICIPANTS  ==============
INSERT INTO room_participants (room_id, user_id, joined_at, left_at)
VALUES
    (1, 2, CURRENT_TIMESTAMP - INTERVAL '2 minutes', NULL),     -- alice in lobby
    (1, 3, CURRENT_TIMESTAMP - INTERVAL '1 minute',  NULL),     -- bob joined
    (2, 5, CURRENT_TIMESTAMP - INTERVAL '6 minutes', NULL),     -- diana playing
    (2, 2, CURRENT_TIMESTAMP - INTERVAL '6 minutes', NULL),     -- alice playing
    (3, 3, CURRENT_TIMESTAMP - INTERVAL '1 hour',    CURRENT_TIMESTAMP - INTERVAL '40 minutes'), -- bob (finished)
    (3, 5, CURRENT_TIMESTAMP - INTERVAL '1 hour',    CURRENT_TIMESTAMP - INTERVAL '45 minutes'), -- diana left early
    (4, 10,CURRENT_TIMESTAMP - INTERVAL '3 minutes', NULL);     -- grace in royale lobby

-- =====================  15) MATCHMAKING QUEUE  =============
INSERT INTO matchmaking_queue
    (user_id, game_id, variation_id, status)
VALUES
    (4, 3, 5, 'waiting'),    -- charlie waiting for a duel
    (6, 3, 5, 'waiting'),    -- eve waiting (could match charlie)
    (2, 2, 4, 'matched'),    -- alice already matched
    (9, 3, 5, 'cancelled');  -- frank cancelled search

-- =====================  16) MULTIPLAYER MATCHES  ===========
INSERT INTO multiplayer_matches
    (room_id, winner_user_id, result_data_json, ended_at)
VALUES
    (3, 3, '{"scores": {"3": 5, "5": 3}, "rounds": 5}', CURRENT_TIMESTAMP - INTERVAL '40 minutes');


-- =====================  17) SYNC STATE  =====================
INSERT INTO sync_state (user_id, dataset_name, last_synced_at, data_snapshot)
VALUES
    (2, 'progress',  CURRENT_TIMESTAMP - INTERVAL '1 hour',  '{"level": 12, "streak": 4}'),
    (2, 'settings',  CURRENT_TIMESTAMP - INTERVAL '2 days',  '{"theme": "dark", "lang": "en"}'),
    (5, 'progress',  CURRENT_TIMESTAMP - INTERVAL '30 min',  '{"level": 25, "streak": 10}'),
    (9, 'settings',  CURRENT_TIMESTAMP - INTERVAL '5 days',  '{"theme": "light", "lang": "fa"}');

COMMIT;

-- =============================================================
-- Optional sanity checks (run manually, not part of the seed):
--   SELECT username, total_score FROM users ORDER BY user_id;   -- trigger result
--   SELECT text, length FROM words;                             -- auto length
--   CALL sp_expire_subscriptions();                             -- expires bob's plan
--   SELECT * FROM vw_user_active_plans;                         -- active plans view
--   SELECT fn_user_has_variation_access(5, 2);                  -- diana -> TRUE
--   SELECT fn_user_has_variation_access(3, 2);                  -- bob   -> FALSE (after expire)
-- =============================================================
