-- =============================================================
-- GOLVAZHE Game Schema v2
-- PostgreSQL 13+
--
-- Domains:
--   Auth, words, reports, daily challenges, subscriptions,
--   friend graph, multiplayer rooms, matchmaking, and sync state.
--
-- Programmable objects:
--   Functions, triggers, maintenance procedures, and read-model views.
-- =============================================================

BEGIN;

-- Rebuild schema for local/dev environments.
DROP VIEW     IF EXISTS vw_user_active_plans CASCADE;
DROP VIEW     IF EXISTS vw_user_full_profile, vw_daily_challenge_leaderboard,
                        vw_active_rooms, vw_global_leaderboard, vw_active_users CASCADE;
DROP TABLE    IF EXISTS sync_state, multiplayer_matches, room_participants,
                        multiplayer_rooms, matchmaking_queue, friendships,
                        user_subscriptions, plan_variation_access, subscription_plans,
                        daily_challenge_submissions, daily_challenges,
                        email_verification_tokens, word_reports, words,
                        game_variations, games, users CASCADE;

-- =============================================================
-- TABLES
-- =============================================================

-- User accounts, including guests and upgraded registered users.
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
    is_soft_deleted   BOOLEAN DEFAULT FALSE,
    created_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at        TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    last_login_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    upgraded_at       TIMESTAMPTZ,
    CONSTRAINT chk_registered_has_credentials
        CHECK ((is_guest = TRUE) OR (email IS NOT NULL AND password_hash IS NOT NULL))
);

-- Game catalog entries.
CREATE TABLE games (
    game_id             SERIAL PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    description         TEXT,
    has_daily_challenge BOOLEAN DEFAULT FALSE,
    has_multiplayer     BOOLEAN DEFAULT FALSE,
    status              VARCHAR(20) DEFAULT 'active',
    created_at          TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_games_status
        CHECK (status IN ('active', 'inactive'))
);

-- Playable modes/configurations under a game.
CREATE TABLE game_variations (
    variation_id SERIAL PRIMARY KEY,
    game_id      INTEGER REFERENCES games(game_id) ON DELETE CASCADE,
    name         VARCHAR(100) NOT NULL,
    params_json  JSONB DEFAULT '{}',
    player_count INTEGER DEFAULT 1,
    CONSTRAINT chk_game_variations_player_count
        CHECK (player_count >= 1)
);

-- Dictionary words. length is maintained by trg_words_length.
CREATE TABLE words (
    word_id          SERIAL PRIMARY KEY,
    text             VARCHAR(100) NOT NULL,
    language         VARCHAR(10) DEFAULT 'en',
    difficulty_level INTEGER DEFAULT 1,
    length           INTEGER,
    is_soft_deleted  BOOLEAN DEFAULT FALSE,
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_words_difficulty
        CHECK (difficulty_level >= 1)
);

-- User moderation reports for dictionary words.
CREATE TABLE word_reports (
    report_id        SERIAL PRIMARY KEY,
    word_id          INTEGER REFERENCES words(word_id) ON DELETE CASCADE,
    reporter_user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    reason           TEXT,
    status           VARCHAR(20) DEFAULT 'pending',
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_word_reports_status
        CHECK (status IN ('pending', 'reviewed', 'dismissed'))
);

-- Server-side email verification tokens.
CREATE TABLE email_verification_tokens (
    token_id   SERIAL PRIMARY KEY,
    user_id    INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    token      VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Daily challenge definitions.
CREATE TABLE daily_challenges (
    daily_challenge_id SERIAL PRIMARY KEY,
    game_id            INTEGER REFERENCES games(game_id) ON DELETE CASCADE,
    variation_id       INTEGER REFERENCES game_variations(variation_id) ON DELETE CASCADE,
    challenge_date     DATE NOT NULL,
    data_json          JSONB DEFAULT '{}',
    status             VARCHAR(20) DEFAULT 'active',
    CONSTRAINT chk_daily_challenges_status
        CHECK (status IN ('active', 'inactive')),
    UNIQUE(game_id, challenge_date)
);

-- Per-user challenge results. Score changes update users.total_score.
CREATE TABLE daily_challenge_submissions (
    submission_id      SERIAL PRIMARY KEY,
    user_id            INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    daily_challenge_id INTEGER REFERENCES daily_challenges(daily_challenge_id) ON DELETE CASCADE,
    score              INTEGER DEFAULT 0,
    completed_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_daily_submission_score
        CHECK (score >= 0),
    UNIQUE(user_id, daily_challenge_id)
);

-- Purchasable plans and feature metadata.
CREATE TABLE subscription_plans (
    plan_id       SERIAL PRIMARY KEY,
    name          VARCHAR(50) NOT NULL,
    price_coins   INTEGER DEFAULT 0,
    duration_days INTEGER DEFAULT 30,
    features_json JSONB DEFAULT '{}',
    CONSTRAINT chk_subscription_plans_price
        CHECK (price_coins >= 0),
    CONSTRAINT chk_subscription_plans_duration
        CHECK (duration_days >= 1)
);

-- Plan-to-variation grants for premium access control.
CREATE TABLE plan_variation_access (
    plan_id      INTEGER REFERENCES subscription_plans(plan_id) ON DELETE CASCADE,
    variation_id INTEGER REFERENCES game_variations(variation_id) ON DELETE CASCADE,
    PRIMARY KEY (plan_id, variation_id)
);

-- User plan purchases and lifecycle state.
CREATE TABLE user_subscriptions (
    subscription_id SERIAL PRIMARY KEY,
    user_id         INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    plan_id         INTEGER REFERENCES subscription_plans(plan_id) ON DELETE CASCADE,
    starts_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ends_at         TIMESTAMPTZ NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE,
    status          VARCHAR(20) DEFAULT 'active',
    updated_at      TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_user_subscriptions_status
        CHECK (status IN ('active', 'cancelling', 'cancelled', 'expired')),
    CONSTRAINT chk_user_subscriptions_dates
        CHECK (ends_at > starts_at)
);

-- Normalized friendship pairs. action_user_id preserves request direction.
CREATE TABLE friendships (
    friendship_id  SERIAL PRIMARY KEY,
    user_id_1      INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    user_id_2      INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    action_user_id INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    status         VARCHAR(20) DEFAULT 'pending',
    created_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id_1, user_id_2),
    CONSTRAINT chk_friendships_distinct_users
        CHECK (user_id_1 <> user_id_2),
    CONSTRAINT chk_friendships_status
        CHECK (status IN ('pending', 'accepted', 'blocked'))
);

-- Multiplayer room lifecycle and ownership.
CREATE TABLE multiplayer_rooms (
    room_id            SERIAL PRIMARY KEY,
    room_code          VARCHAR(10) UNIQUE NOT NULL,
    game_id            INTEGER REFERENCES games(game_id) ON DELETE CASCADE,
    variation_id       INTEGER REFERENCES game_variations(variation_id) ON DELETE CASCADE,
    created_by_user_id INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    admin_user_id      INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    is_private         BOOLEAN DEFAULT FALSE,
    status             VARCHAR(20) DEFAULT 'lobby',
    created_at         TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    started_at         TIMESTAMPTZ,
    ended_at           TIMESTAMPTZ,
    CONSTRAINT chk_multiplayer_rooms_status
        CHECK (status IN ('lobby', 'playing', 'finished'))
);

-- Users currently or historically attached to a room.
CREATE TABLE room_participants (
    room_id   INTEGER REFERENCES multiplayer_rooms(room_id) ON DELETE CASCADE,
    user_id   INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    left_at   TIMESTAMPTZ,
    PRIMARY KEY (room_id, user_id)
);

-- Matchmaking requests before room assignment.
CREATE TABLE matchmaking_queue (
    queue_id     SERIAL PRIMARY KEY,
    user_id      INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    game_id      INTEGER REFERENCES games(game_id) ON DELETE CASCADE,
    variation_id INTEGER REFERENCES game_variations(variation_id) ON DELETE CASCADE,
    joined_at    TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    status       VARCHAR(20) DEFAULT 'waiting',
    room_id      INTEGER REFERENCES multiplayer_rooms(room_id) ON DELETE SET NULL,
    matched_at   TIMESTAMPTZ,
    CONSTRAINT chk_matchmaking_queue_status
        CHECK (status IN ('waiting', 'matched', 'cancelled')),
    UNIQUE (user_id, game_id, variation_id)
);

-- Finalized multiplayer match results.
CREATE TABLE multiplayer_matches (
    match_id         SERIAL PRIMARY KEY,
    room_id          INTEGER REFERENCES multiplayer_rooms(room_id) ON DELETE CASCADE,
    winner_user_id   INTEGER REFERENCES users(user_id) ON DELETE SET NULL,
    result_data_json JSONB DEFAULT '{}',
    created_at       TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ended_at         TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Client sync snapshots keyed by user and dataset.
CREATE TABLE sync_state (
    user_id        INTEGER REFERENCES users(user_id) ON DELETE CASCADE,
    dataset_name   VARCHAR(50) NOT NULL,
    last_synced_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    data_snapshot  JSONB DEFAULT '{}',
    PRIMARY KEY (user_id, dataset_name)
);


-- =============================================================
-- INDEXES
-- =============================================================

-- Read-path indexes used by routers, views, and cleanup procedures.
CREATE INDEX idx_words_length        ON words(length);
CREATE INDEX idx_words_difficulty    ON words(difficulty_level);
CREATE INDEX idx_words_text_lower    ON words(LOWER(text));
CREATE INDEX idx_words_active        ON words(is_soft_deleted) WHERE is_soft_deleted = FALSE;
CREATE INDEX idx_users_active        ON users(is_soft_deleted) WHERE is_soft_deleted = FALSE;
CREATE INDEX idx_friendships_user1   ON friendships(user_id_1);
CREATE INDEX idx_friendships_user2   ON friendships(user_id_2);
CREATE INDEX idx_friendships_status  ON friendships(status);
CREATE INDEX idx_friendships_user1_status ON friendships(user_id_1, status);
CREATE INDEX idx_friendships_user2_status ON friendships(user_id_2, status);
CREATE INDEX idx_evt_user            ON email_verification_tokens(user_id);
CREATE INDEX idx_evt_token           ON email_verification_tokens(token);
CREATE INDEX idx_queue_user_active ON matchmaking_queue(user_id) WHERE status = 'waiting';
CREATE INDEX idx_queue_lookup        ON matchmaking_queue(game_id, variation_id, status);
CREATE INDEX idx_subs_user_active    ON user_subscriptions(user_id, status);
CREATE INDEX idx_subs_access_lookup  ON user_subscriptions(user_id, status, is_active, ends_at);
CREATE INDEX idx_rooms_public        ON multiplayer_rooms(status) WHERE is_private = FALSE;
CREATE INDEX idx_reports_status      ON word_reports(status);
CREATE INDEX idx_reports_reporter_created ON word_reports(reporter_user_id, created_at DESC);
CREATE INDEX idx_daily_challenges_date ON daily_challenges(challenge_date);
CREATE INDEX idx_submissions_user    ON daily_challenge_submissions(user_id);
CREATE INDEX idx_users_total_score ON users(total_score DESC);
CREATE INDEX idx_room_participants_user ON room_participants(user_id);
CREATE INDEX idx_room_participants_room ON room_participants(room_id);
CREATE INDEX idx_sync_state_user_dataset ON sync_state(user_id, dataset_name);
CREATE INDEX idx_plan_variation_access_variation_plan ON plan_variation_access(variation_id, plan_id);

-- =============================================================
-- FUNCTIONS
-- =============================================================

-- Shared trigger function for tables with updated_at.
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Maintain words.length whenever words.text changes.
CREATE OR REPLACE FUNCTION fn_set_word_length()
RETURNS TRIGGER AS $$
BEGIN
    NEW.length := char_length(NEW.text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Normalize friendship pairs so (A,B) and (B,A) share one row.
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

-- Keep users.total_score aligned with daily challenge submissions.
CREATE OR REPLACE FUNCTION fn_add_submission_score()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE users
           SET total_score = total_score + COALESCE(NEW.score, 0)
         WHERE user_id = NEW.user_id;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        UPDATE users
           SET total_score = total_score - COALESCE(OLD.score, 0) + COALESCE(NEW.score, 0)
         WHERE user_id = NEW.user_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE users
           SET total_score = total_score - COALESCE(OLD.score, 0)
         WHERE user_id = OLD.user_id;
        RETURN OLD;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Generate a unique 6-character multiplayer room code.
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

-- Return true when a variation is free or covered by an active user plan.
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


-- =============================================================
-- TRIGGERS
-- =============================================================

-- Timestamp maintenance.
CREATE TRIGGER trg_users_updated
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_friendships_updated
    BEFORE UPDATE ON friendships
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_word_reports_updated
    BEFORE UPDATE ON word_reports
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_user_subscriptions_updated
    BEFORE UPDATE ON user_subscriptions
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_multiplayer_rooms_updated
    BEFORE UPDATE ON multiplayer_rooms
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Derived word metadata.
CREATE TRIGGER trg_words_length
    BEFORE INSERT OR UPDATE OF text ON words
    FOR EACH ROW EXECUTE FUNCTION fn_set_word_length();

-- Friendship normalization.
CREATE TRIGGER trg_friendships_normalize
    BEFORE INSERT OR UPDATE ON friendships
    FOR EACH ROW EXECUTE FUNCTION fn_normalize_friendship();

-- Score denormalization.
DROP TRIGGER IF EXISTS trg_submission_score ON daily_challenge_submissions;
CREATE TRIGGER trg_submission_score
    AFTER INSERT OR UPDATE OR DELETE ON daily_challenge_submissions
    FOR EACH ROW EXECUTE FUNCTION fn_add_submission_score();


-- =============================================================
-- STORED PROCEDURES
-- =============================================================

-- Mark active subscriptions as expired after ends_at.
CREATE OR REPLACE PROCEDURE sp_expire_subscriptions()
LANGUAGE plpgsql AS $$
DECLARE
    expired_count INTEGER;
BEGIN
    WITH updated AS (
        UPDATE user_subscriptions
           SET status = 'expired', 
               is_active = FALSE
         WHERE status = 'active'
           AND ends_at < CURRENT_TIMESTAMP
        RETURNING subscription_id
    )
    SELECT count(*) INTO expired_count FROM updated;

    RAISE NOTICE 'sp_expire_subscriptions: % subscription(s) expired', expired_count;
END;
$$;


-- Delete pending friend requests older than the configured threshold.
CREATE OR REPLACE PROCEDURE sp_cleanup_old_friend_requests(days_old INTEGER DEFAULT 30)
LANGUAGE plpgsql AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    WITH deleted AS (
        DELETE FROM friendships 
         WHERE status = 'pending'
           AND created_at < (CURRENT_TIMESTAMP - make_interval(days => days_old))
        RETURNING friendship_id
    )
    SELECT count(*) INTO deleted_count FROM deleted;

    RAISE NOTICE 'sp_cleanup_old_friend_requests: % request(s) removed', deleted_count;
END;
$$;

-- Remove waiting matchmaking entries older than the configured threshold.
CREATE OR REPLACE PROCEDURE sp_cleanup_stale_matchmaking(minutes_old INTEGER DEFAULT 5)
LANGUAGE plpgsql AS $$
DECLARE
    removed_count INTEGER;
BEGIN
    WITH deleted AS (
        DELETE FROM matchmaking_queue
         WHERE status = 'waiting'
           AND joined_at < (CURRENT_TIMESTAMP - make_interval(mins => minutes_old))
        RETURNING user_id
    )
    SELECT count(*) INTO removed_count FROM deleted;

    RAISE NOTICE 'sp_cleanup_stale_matchmaking: % stale entries removed from queue', removed_count;
END;
$$;


-- Soft-delete guest users that never converted after the configured threshold.
CREATE OR REPLACE PROCEDURE sp_purge_inactive_guests(days_inactive INTEGER DEFAULT 90)
LANGUAGE plpgsql AS $$
DECLARE
    purged_count INTEGER;
BEGIN
    WITH updated AS (
        UPDATE users
           SET is_soft_deleted = TRUE,
               updated_at = CURRENT_TIMESTAMP
         WHERE is_guest = TRUE
           AND is_soft_deleted = FALSE
           AND created_at < (CURRENT_TIMESTAMP - make_interval(days => days_inactive))
        RETURNING user_id
    )
    SELECT count(*) INTO purged_count FROM updated;

    RAISE NOTICE 'sp_purge_inactive_guests: % inactive guest(s) soft-deleted', purged_count;
END;
$$;


-- Finish rooms that have stayed in lobby/playing beyond the configured threshold.
CREATE OR REPLACE PROCEDURE sp_finalize_abandoned_rooms(hours_old INTEGER DEFAULT 2)
LANGUAGE plpgsql AS $$
DECLARE
    finalized_count INTEGER;
BEGIN
    WITH updated AS (
        UPDATE multiplayer_rooms
           SET status = 'finished',
               ended_at = COALESCE(ended_at, CURRENT_TIMESTAMP),
               updated_at = CURRENT_TIMESTAMP
         WHERE status IN ('lobby', 'playing')
           AND created_at < (CURRENT_TIMESTAMP - make_interval(hours => hours_old))
        RETURNING room_id
    )
    SELECT count(*) INTO finalized_count FROM updated;

    RAISE NOTICE 'sp_finalize_abandoned_rooms: % abandoned room(s) finalized', finalized_count;
END;
$$;

-- =============================================================
-- VIEWS
-- =============================================================

-- Active user projection for public/user-facing reads.
CREATE OR REPLACE VIEW vw_active_users AS
SELECT user_id, 
       username, 
       email, 
       total_score, 
       is_guest, 
       created_at
  FROM users
 WHERE is_soft_deleted = FALSE;


-- Ranked global leaderboard for users with non-zero score.
CREATE OR REPLACE VIEW vw_global_leaderboard AS
SELECT user_id,
       username,
       total_score,
       RANK() OVER (ORDER BY total_score DESC) as rank
  FROM users
 WHERE is_soft_deleted = FALSE 
   AND total_score > 0;


-- Public lobby read model with creator and participant count.
CREATE OR REPLACE VIEW vw_active_rooms AS
SELECT r.room_id, 
       r.room_code,
       r.game_id,
       r.variation_id,
       r.created_by_user_id,
       r.admin_user_id,
       r.status, 
       r.is_private, 
       r.created_at,
       r.started_at,
       r.ended_at,
       u.username AS creator_username,
       COUNT(rp.user_id) AS current_player_count
  FROM multiplayer_rooms r
  JOIN users u ON r.created_by_user_id = u.user_id
  LEFT JOIN room_participants rp ON r.room_id = rp.room_id
 WHERE r.status = 'lobby'
   AND u.is_soft_deleted = FALSE
 GROUP BY r.room_id, r.room_code, r.game_id, r.variation_id,
          r.created_by_user_id, r.admin_user_id, r.status, r.is_private,
          r.created_at, r.started_at, r.ended_at, u.username;


-- Per-challenge rankings based on score and completion time.
CREATE OR REPLACE VIEW vw_daily_challenge_leaderboard AS
SELECT dc.daily_challenge_id,
       dc.challenge_date,
       ds.user_id,
       u.username,
       ds.score,
       ds.completed_at,
       RANK() OVER (PARTITION BY dc.daily_challenge_id 
                    ORDER BY ds.score DESC, ds.completed_at ASC) as daily_rank
  FROM daily_challenges dc
  JOIN daily_challenge_submissions ds ON dc.daily_challenge_id = ds.daily_challenge_id
  JOIN users u ON ds.user_id = u.user_id
 WHERE u.is_soft_deleted = FALSE;


-- Current active subscription plans with plan display data.
CREATE OR REPLACE VIEW vw_user_active_plans AS
SELECT us.user_id,
       us.subscription_id,
       us.plan_id,
       sp.name AS plan_name,
       us.starts_at,
       us.is_active,
       us.status,
       us.ends_at
  FROM user_subscriptions us
  JOIN subscription_plans sp ON us.plan_id = sp.plan_id
 WHERE us.is_active = TRUE 
   AND us.status = 'active'
   AND us.ends_at > CURRENT_TIMESTAMP;


-- User profile read model with current subscription summary.
CREATE OR REPLACE VIEW vw_user_full_profile AS
SELECT u.user_id,
       u.username,
       u.email,
       u.is_guest,
       u.is_admin,
       u.is_verified,
       u.coins,
       u.total_score,
       u.is_report_blocked,
       u.created_at,
       u.last_login_at,
       u.upgraded_at,
       vp.plan_name AS current_plan_name,
       vp.ends_at AS plan_ends_at,
       CASE WHEN vp.plan_name IS NOT NULL THEN TRUE ELSE FALSE END AS has_active_subscription
  FROM users u
  LEFT JOIN vw_user_active_plans vp ON u.user_id = vp.user_id
 WHERE u.is_soft_deleted = FALSE;

COMMIT;
