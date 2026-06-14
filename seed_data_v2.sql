-- ==============================================================================
-- Seed Data for Schema v2
-- ==============================================================================

-- 1. پاکسازی داده‌های قبلی (برای قابلیت اجرای مجدد اسکریپت)
TRUNCATE TABLE 
    users, games, game_variations, words, word_reports, 
    email_verification_tokens, daily_challenges, daily_challenge_submissions, 
    subscription_plans, plan_variation_access, user_subscriptions, 
    friendships, multiplayer_rooms, room_participants, 
    matchmaking_queue, multiplayer_matches, sync_state 
RESTART IDENTITY CASCADE;

-- ==============================================================================
-- 2. Users (کاربران: ادمین، کاربران عادی تایید شده و نشده، مهمان)
-- ==============================================================================
INSERT INTO users (username, email, password_hash, is_guest, is_admin, is_verified, coins, total_score) VALUES
('admin_user', 'admin@example.com', 'dummy_hash_123', FALSE, TRUE, TRUE, 10000, 5000),
('alice_pro', 'alice@example.com', 'dummy_hash_123', FALSE, FALSE, TRUE, 500, 1200),
('bob_newbie', 'bob@example.com', 'dummy_hash_123', FALSE, FALSE, FALSE, 50, 0),
('guest_9982', NULL, NULL, TRUE, FALSE, FALSE, 0, 10),
('charlie_deleted', 'charlie@example.com', 'dummy_hash_123', FALSE, FALSE, TRUE, 100, 400);

-- فرضی: چارلی سافت‌دیلیت شده است
UPDATE users SET is_soft_deleted = TRUE WHERE username = 'charlie_deleted';

-- ==============================================================================
-- 3. Games & Variations (بازی‌ها و انواع آن‌ها)
-- ==============================================================================
INSERT INTO games (game_id, name, description, has_daily_challenge, has_multiplayer, status) VALUES
(1, 'Word Guess', 'Guess the hidden word in 6 tries.', TRUE, TRUE, 'active'),
(2, 'Speed Type', 'Type as many words as possible in 60s.', FALSE, TRUE, 'active');

INSERT INTO game_variations (variation_id, game_id, name, params_json, player_count) VALUES
(1, 1, 'Classic 5-Letter', '{"word_length": 5, "max_attempts": 6}', 1),
(2, 1, 'Multiplayer Duel', '{"word_length": 5, "max_attempts": 6, "turn_time": 30}', 2),
(3, 2, '1v1 Speed Battle', '{"duration_sec": 60}', 2);

-- ==============================================================================
-- 4. Subscription Plans & Access (اشتراک‌ها و سطوح دسترسی)
-- ==============================================================================
INSERT INTO subscription_plans (plan_id, name, price_coins, duration_days, features_json) VALUES
(1, 'Basic Free', 0, 3650, '{"ads": true, "daily_limit": 5}'),
(2, 'Premium VIP', 500, 30, '{"ads": false, "daily_limit": 999, "exclusive_avatars": true}');

INSERT INTO plan_variation_access (plan_id, variation_id) VALUES
(1, 1), -- کاربران رایگان فقط به حالت کلاسیک دسترسی دارند
(2, 1), 
(2, 2), -- حالت دونفره پریمیوم
(2, 3); -- حالت سرعتی پریمیوم

-- اختصاص اشتراک پریمیوم به Alice
INSERT INTO user_subscriptions (user_id, plan_id, starts_at, ends_at, is_active, status) VALUES
((SELECT user_id FROM users WHERE username = 'alice_pro'), 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days', TRUE, 'active');

-- ==============================================================================
-- 5. Words & Reports (کلمات و گزارش‌های خرابی کلمه)
-- ==============================================================================
-- نکته: طول کلمه (length) با تریگر حساب می‌شود، بنابراین نیازی به اینسرت دستی آن نیست
INSERT INTO words (text, language, difficulty_level) VALUES
('apple', 'en', 1),
('brain', 'en', 2),
('crypt', 'en', 3),
('سلام', 'fa', 1);

INSERT INTO word_reports (word_id, reporter_user_id, reason, status) VALUES
(4, (SELECT user_id FROM users WHERE username = 'bob_newbie'), 'Should be restricted to English words only', 'pending');

-- ==============================================================================
-- 6. Daily Challenges & Submissions (چالش‌های روزانه)
-- ==============================================================================
INSERT INTO daily_challenges (daily_challenge_id, game_id, variation_id, challenge_date, status) VALUES
(1, 1, 1, CURRENT_DATE, 'active'),
(2, 1, 1, CURRENT_DATE - INTERVAL '1 day', 'expired');

INSERT INTO daily_challenge_submissions (user_id, daily_challenge_id, score, completed_at) VALUES
((SELECT user_id FROM users WHERE username = 'alice_pro'), 2, 100, CURRENT_TIMESTAMP - INTERVAL '12 hours'),
((SELECT user_id FROM users WHERE username = 'alice_pro'), 1, 150, CURRENT_TIMESTAMP);

-- ==============================================================================
-- 7. Friendships (دوستی‌ها - رعایت استاتوس‌های pending, accepted, blocked)
-- ==============================================================================
INSERT INTO friendships (user_id_1, user_id_2, action_user_id, status) VALUES
(1, 2, 1, 'accepted'), -- Admin and Alice are friends
(2, 3, 3, 'pending'),  -- Bob requested to be friends with Alice
(2, 4, 2, 'blocked');  -- Alice blocked Guest

-- ==============================================================================
-- 8. Multiplayer Rooms & Participants (اتاق‌های بازی: لابی، در حال بازی، تمام شده)
-- ==============================================================================
-- اتاق 1: در حالت لابی (فقط ادمین ساخته و منتظره)
INSERT INTO multiplayer_rooms (room_id, room_code, game_id, variation_id, created_by_user_id, admin_user_id, is_private, status) VALUES
(1, 'LOBBY123', 1, 2, 1, 1, FALSE, 'lobby');

INSERT INTO room_participants (room_id, user_id, joined_at) VALUES
(1, 1, CURRENT_TIMESTAMP);

-- اتاق 2: در حال بازی (Alice و Bob)
INSERT INTO multiplayer_rooms (room_id, room_code, game_id, variation_id, created_by_user_id, admin_user_id, status, started_at) VALUES
(2, 'PLAY9999', 2, 3, 2, 2, 'playing', CURRENT_TIMESTAMP - INTERVAL '2 minutes');

INSERT INTO room_participants (room_id, user_id, joined_at) VALUES
(2, 2, CURRENT_TIMESTAMP - INTERVAL '3 minutes'),
(2, 3, CURRENT_TIMESTAMP - INTERVAL '2 minutes');

-- اتاق 3: به اتمام رسیده
INSERT INTO multiplayer_rooms (room_id, room_code, game_id, variation_id, created_by_user_id, admin_user_id, status, started_at, ended_at) VALUES
(3, 'DONE5555', 1, 2, 2, 2, 'finished', CURRENT_TIMESTAMP - INTERVAL '1 hour', CURRENT_TIMESTAMP - INTERVAL '50 minutes');

-- ==============================================================================
-- 9. Matches (نتایج بازی‌های تمام شده)
-- ==============================================================================
INSERT INTO multiplayer_matches (room_id, winner_user_id, result_data_json) VALUES
(3, 2, '{"alice_score": 500, "opponent_score": 200, "turns": 4}');

-- ==============================================================================
-- 10. Matchmaking Queue (صف انتظار برای مچ‌میکینگ)
-- ==============================================================================
-- باب منتظر پیدا شدن رقیب در بازی 1 و وریشن 2 است
INSERT INTO matchmaking_queue (user_id, game_id, variation_id, status) VALUES
((SELECT user_id FROM users WHERE username = 'bob_newbie'), 1, 2, 'waiting');

-- ==============================================================================
-- 11. Sync State (وضعیت سینک داده‌های کلاینت)
-- ==============================================================================
INSERT INTO sync_state (user_id, dataset_name, data_snapshot) VALUES
(2, 'inventory', '{"items": ["avatar_1", "theme_dark"]}'),
(2, 'preferences', '{"sound": true, "notifications": false}');
