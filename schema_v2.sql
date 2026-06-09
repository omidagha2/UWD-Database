-- =============================================================
-- Game Project Schema v2 (Comprehensive + Programmable Objects)
-- Supports: Auth/Guest, Email Verification, Daily Challenges,
--           Friends, Multiplayer Rooms, Matchmaking Queue,
--           Subscriptions + Access Control, Word Reports, Sync
-- Includes: FUNCTIONS, TRIGGERS, STORED PROCEDURES (w/ CURSOR), VIEWS
-- Target  : PostgreSQL 13+
-- =============================================================

BEGIN;

-- ---------- Clean slate (safe re-run for local dev) ----------
DROP VIEW     IF EXISTS vw_user_active_plans CASCADE;
DROP TABLE    IF EXISTS sync_state, multiplayer_matches, room_participants,
                        multiplayer_rooms, matchmaking_queue, friendships,
                        user_subscriptions, plan_variation_access, subscription_plans,
                        daily_challenge_submissions, daily_challenges,
                        email_verification_tokens, word_reports, words,
                        game_variations, games, users CASCADE;

-- =====================  CORE  ================================

-- 1) USERS
CREATE TABLE users (
    user_id           SERIAL PRIMARY KEY,
    username          VARCHAR(50)  UNIQUE NOT NULL,
    email             VARCHAR(100) UNIQUE,
    password_hash     VARCHAR(255),
    is_guest          BOOLEAN DEFAULT FALSE,
    is_admin          BOOLEAN DEFAULT FALSE,
    is_verified       BOOLEAN DEFAULT FALSE,
    coins             INTEGER DEFAULT 0,
    total_score       INTEGER DEFAULT 0,
    is_report_blocked BOOLEAN DEFAULT FALSE,
    created_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    last_login_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    upgraded_at       TIMESTAMPTZ,                         -- NEW: guest -> registered
    CONSTRAINT chk_registered_has_credentials
        CHECK ((is_guest = TRUE) OR (email IS NOT NULL AND password_hash IS NOT NULL))
);

-- 2) GAMES
CREATE TABLE games (
    game_id             SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    description         TEXT,
    has_daily_challenge BOOLEAN DEFAULT FALSE,
    has_multiplayer     BOOLEAN DEFAULT FALSE,
    status              VARCHAR(20) DEFAULT 'active',
    created_at          TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3) GAME VARIATIONS
CREATE TABLE game_variations (
    variation_id SERIAL PRIMARY KEY,
    game_id      INTEGER REFERENCES games(game_id) ON DELETE CASCADE,
    name         VARCHAR(100) NOT NULL,
    params_json  JSONB DEFAULT '{}',
    player_count INTEGER DEFAULT 1
);

-- 4) WORDS  (length auto-filled by trigger)
CREATE TABLE words (
    word_id          SERIAL PRIMARY KEY,
    text             VARCHAR(100) NOT NULL,
    language         VARCHAR(10) DEFAULT 'en',
    difficulty_level INTEGER DEFAULT 1,
    length           INTEGER,                       -- auto via trigger
    is_soft_deleted  BOOLEAN DEFAULT FALSE,
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5) WORD REPORTS  (+ updated_at via trigger)
CREATE TABLE word_reports (
    report_id        SERIAL PRIMARY KEY,
    word_id          INTEGER REFERENCES words(word_id) ON DELETE CASCADE,
    reporter_user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    reason           TEXT,
    status           VARCHAR(20) DEFAULT 'pending',  -- pending, reviewed, dismissed
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP   -- NEW
);

-- 6) EMAIL VERIFICATION TOKENS  (NEW)
CREATE TABLE email_verification_tokens (
    token_id   SERIAL PRIMARY KEY,
    user_id    INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    token      VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 7) DAILY CHALLENGES
CREATE TABLE daily_challenges (
    daily_challenge_id SERIAL PRIMARY KEY,
    game_id            INTEGER REFERENCES games(game_id) ON DELETE CASCADE,
    variation_id       INTEGER REFERENCES game_variations(variation_id) ON DELETE CASCADE,
    challenge_date     DATE NOT NULL,
    data_json          JSONB DEFAULT '{}',
    status             VARCHAR(20) DEFAULT 'active',
    UNIQUE(game_id, challenge_date)
);

-- 8) DAILY CHALLENGE SUBMISSIONS  (feeds users.total_score via trigger)
CREATE TABLE daily_challenge_submissions (
    submission_id      SERIAL PRIMARY KEY,
    user_id            INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    daily_challenge_id INTEGER REFERENCES daily_challenges(daily_challenge_id) ON DELETE CASCADE,
    score              INTEGER DEFAULT 0,
    completed_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, daily_challenge_id)
);

-- 9) SUBSCRIPTION PLANS
CREATE TABLE subscription_plans (
    plan_id       SERIAL PRIMARY KEY,
    name          VARCHAR(50) NOT NULL,
    price_coins   INTEGER DEFAULT 0,
    duration_days INTEGER DEFAULT 30,
    features_json JSONB DEFAULT '{}'
);

-- 10) PLAN <-> VARIATION ACCESS  (NEW)
CREATE TABLE plan_variation_access (
    plan_id      INTEGER REFERENCES subscription_plans(plan_id) ON DELETE CASCADE,
    variation_id INTEGER REFERENCES game_variations(variation_id) ON DELETE CASCADE,
    PRIMARY KEY (plan_id, variation_id)
);

-- 11) USER SUBSCRIPTIONS  (+ status NEW)
CREATE TABLE user_subscriptions (
    subscription_id SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    plan_id         INTEGER REFERENCES subscription_plans(plan_id) ON DELETE CASCADE,
    starts_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ends_at         TIMESTAMPTZ NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE,
    status          VARCHAR(20) DEFAULT 'active'  -- active, cancelling, cancelled, expired
);

-- 12) FRIENDSHIPS  (+ action_user_id to keep request direction)
CREATE TABLE friendships (
    friendship_id  SERIAL PRIMARY KEY,
    user_id_1      INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    user_id_2      INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    action_user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,  -- NEW: who sent/acted
    status         VARCHAR(20) DEFAULT 'pending',  -- pending, accepted, blocked
    created_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id_1, user_id_2),
    CHECK (user_id_1 <> user_id_2)
);

-- 13) MULTIPLAYER ROOMS
CREATE TABLE multiplayer_rooms (
    room_id            SERIAL PRIMARY KEY,
    room_code          VARCHAR(10) UNIQUE NOT NULL,
    game_id            INTEGER REFERENCES games(game_id) ON DELETE CASCADE,
    variation_id       INTEGER REFERENCES game_variations(variation_id) ON DELETE CASCADE,
    created_by_user_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    admin_user_id      INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    is_private         BOOLEAN DEFAULT FALSE,
    status             VARCHAR(20) DEFAULT 'lobby',  -- lobby, playing, finished
    created_at         TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    started_at         TIMESTAMPTZ,
    ended_at           TIMESTAMPTZ
);

-- 14) ROOM PARTICIPANTS
CREATE TABLE room_participants (
    room_id   INTEGER REFERENCES multiplayer_rooms(room_id) ON DELETE CASCADE,
    user_id   INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    left_at   TIMESTAMPTZ,
    PRIMARY KEY (room_id, user_id)
);

-- 15) MATCHMAKING QUEUE  (NEW)
CREATE TABLE matchmaking_queue (
    queue_id     SERIAL PRIMARY KEY,
    user_id      INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    game_id      INTEGER REFERENCES games(game_id) ON DELETE CASCADE,
    variation_id INTEGER REFERENCES game_variations(variation_id) ON DELETE CASCADE,
    joined_at    TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    status       VARCHAR(20) DEFAULT 'waiting',  -- waiting, matched, cancelled
    UNIQUE (user_id, game_id, variation_id)
);

-- 16) MULTIPLAYER MATCHES
CREATE TABLE multiplayer_matches (
    match_id         SERIAL PRIMARY KEY,
    room_id          INTEGER REFERENCES multiplayer_rooms(room_id) ON DELETE CASCADE,
    winner_user_id   INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    result_data_json JSONB DEFAULT '{}',
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ended_at         TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 17) SYNC STATE
CREATE TABLE sync_state (
    user_id        INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    dataset_name   VARCHAR(50) NOT NULL,
    last_synced_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    data_snapshot  JSONB DEFAULT '{}',
    PRIMARY KEY (user_id, dataset_name)
);


-- =====================  INDEXES  ============================
CREATE INDEX idx_words_length        ON words(length);
CREATE INDEX idx_words_difficulty    ON words(difficulty_level);
CREATE INDEX idx_words_text_lower    ON words(LOWER(text));
CREATE INDEX idx_words_active        ON words(is_soft_deleted) WHERE is_soft_deleted = FALSE;

CREATE INDEX idx_friendships_user1   ON friendships(user_id_1);
CREATE INDEX idx_friendships_user2   ON friendships(user_id_2);
CREATE INDEX idx_friendships_status  ON friendships(status);

CREATE INDEX idx_evt_user            ON email_verification_tokens(user_id);
CREATE INDEX idx_evt_token           ON email_verification_tokens(token);

CREATE INDEX idx_queue_lookup        ON matchmaking_queue(game_id, variation_id, status);
CREATE INDEX idx_subs_user_active    ON user_subscriptions(user_id, status);
CREATE INDEX idx_rooms_public        ON multiplayer_rooms(status) WHERE is_private = FALSE;
CREATE INDEX idx_reports_status      ON word_reports(status);
CREATE INDEX idx_submissions_user    ON daily_challenge_submissions(user_id);


-- =====================  FUNCTIONS  ==========================

-- (F1) Generic: keep updated_at fresh on UPDATE
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- (F2) Auto-compute word length from text
CREATE OR REPLACE FUNCTION fn_set_word_length()
RETURNS TRIGGER AS $$
BEGIN
    NEW.length := char_length(NEW.text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- (F3) Normalize friendship pair so (A,B) == (B,A) — prevents reverse duplicates.
--      Direction is preserved separately via action_user_id.
CREATE OR REPLACE FUNCTION fn_normalize_friendship()
RETURNS TRIGGER AS $$
DECLARE
    tmp INTEGER;
BEGIN
    IF NEW.user_id_1 > NEW.user_id_2 THEN
        tmp := NEW.user_id_1;
        NEW.user_id_1 := NEW.user_id_2;
        NEW.user_id_2 := tmp;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- (F4) Add submission score to the user's running total
CREATE OR REPLACE FUNCTION fn_add_submission_score()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE users
       SET total_score = total_score + COALESCE(NEW.score, 0)
     WHERE user_id = NEW.user_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- (F5) Generate a guaranteed-unique 6-char room code (callable from app or DEFAULT)
CREATE OR REPLACE FUNCTION fn_generate_room_code()
RETURNS VARCHAR AS $$
DECLARE
    chars  TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    code   VARCHAR(6);
    i      INTEGER;
    n      INTEGER;
BEGIN
    LOOP
        code := '';
        FOR i IN 1..6 LOOP
            code := code || substr(chars, floor(random() * length(chars))::int + 1, 1);
        END LOOP;
        SELECT COUNT(*) INTO n FROM multiplayer_rooms WHERE room_code = code;
        EXIT WHEN n = 0;
    END LOOP;
    RETURN code;
END;
$$ LANGUAGE plpgsql;

-- (F6) Access check: does a user have an active plan granting this variation?
--      If a variation is not gated by any plan, it is free for everyone.
CREATE OR REPLACE FUNCTION fn_user_has_variation_access(p_user_id INTEGER, p_variation_id INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    has_access BOOLEAN := FALSE;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM plan_variation_access WHERE variation_id = p_variation_id) THEN
        RETURN TRUE;
    END IF;

    SELECT EXISTS (
        SELECT 1
          FROM user_subscriptions us
          JOIN plan_variation_access pva ON pva.plan_id = us.plan_id
         WHERE us.user_id   = p_user_id
           AND us.status    = 'active'
           AND us.ends_at   > CURRENT_TIMESTAMP
           AND pva.variation_id = p_variation_id
    ) INTO has_access;

    RETURN has_access;
END;
$$ LANGUAGE plpgsql;


-- =====================  TRIGGERS  ===========================

-- updated_at maintenance
CREATE TRIGGER trg_friendships_updated
    BEFORE UPDATE ON friendships
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_word_reports_updated
    BEFORE UPDATE ON word_reports
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- word length on insert/update
CREATE TRIGGER trg_words_length
    BEFORE INSERT OR UPDATE OF text ON words
    FOR EACH ROW EXECUTE FUNCTION fn_set_word_length();

-- normalize friendship pair before write
CREATE TRIGGER trg_friendships_normalize
    BEFORE INSERT OR UPDATE ON friendships
    FOR EACH ROW EXECUTE FUNCTION fn_normalize_friendship();

-- propagate daily submission score to user total
CREATE TRIGGER trg_submission_score
    AFTER INSERT ON daily_challenge_submissions
    FOR EACH ROW EXECUTE FUNCTION fn_add_submission_score();


-- =====================  STORED PROCEDURES  ==================

-- (P1) Expire subscriptions past their end date — uses an explicit CURSOR.
CREATE OR REPLACE PROCEDURE sp_expire_subscriptions()
LANGUAGE plpgsql AS $$
DECLARE
    sub_cursor CURSOR FOR
        SELECT subscription_id
          FROM user_subscriptions
         WHERE status = 'active'
           AND ends_at < CURRENT_TIMESTAMP;
    rec           RECORD;
    expired_count INTEGER := 0;
BEGIN
    OPEN sub_cursor;
    LOOP
        FETCH sub_cursor INTO rec;
        EXIT WHEN NOT FOUND;

        UPDATE user_subscriptions
           SET status = 'expired', is_active = FALSE
         WHERE subscription_id = rec.subscription_id;

        expired_count := expired_count + 1;
    END LOOP;
    CLOSE sub_cursor;

    RAISE NOTICE 'sp_expire_subscriptions: % subscription(s) expired', expired_count;
END;
$$;

-- (P2) Admin cleanup: delete stale pending friend requests — uses a CURSOR.
CREATE OR REPLACE PROCEDURE sp_cleanup_old_friend_requests(days_old INTEGER DEFAULT 30)
LANGUAGE plpgsql AS $$
DECLARE
    req_cursor CURSOR FOR
        SELECT friendship_id
          FROM friendships
         WHERE status = 'pending'
           AND created_at < (CURRENT_TIMESTAMP - make_interval(days => days_old));
    rec           RECORD;
    deleted_count INTEGER := 0;
BEGIN
    OPEN req_cursor;
    LOOP
        FETCH req_cursor INTO rec;
        EXIT WHEN NOT FOUND;

        DELETE FROM friendships WHERE friendship_id = rec.friendship_id;
        deleted_count := deleted_count + 1;
    END LOOP;
    CLOSE req_cursor;

    RAISE NOTICE 'sp_cleanup_old_friend_requests: % request(s) removed', deleted_count;
END;
$$;

-- =====================  VIEWS  ==============================

-- Convenience view of currently active, non-expired user plans
CREATE OR REPLACE VIEW vw_user_active_plans AS
SELECT us.user_id,
       us.subscription_id,
       us.plan_id,
       sp.name AS plan_name,
       us.starts_at,
       us.ends_at
  FROM user_subscriptions us
  JOIN subscription_plans sp ON sp.plan_id = us.plan_id
 WHERE us.status  = 'active'
   AND us.ends_at > CURRENT_TIMESTAMP;

COMMIT;


