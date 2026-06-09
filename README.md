# Golvazhe Game - Database

PostgreSQL schema and seed data for local development of the Golvazhe word game.

## Quick Start

### 1. Create Schema

```bash
# Login to PostgreSQL
psql postgresql://parham:parhambeikdatabase534912768@localhost:5432/postgres

# Then run the schema file
psql postgresql://parham:parhambeikdatabase534912768@localhost:5432/postgres -f schema_v1.sql

# Or from psql prompt
\i schema_v1.sql
```

### 2. Verify Tables

```bash
# List all tables
psql postgresql://parham:parhambeikdatabase534912768@localhost:5432/postgres -c "\dt"

# Expected output:
# public | daily_challenges      | table
# public | friendships           | table
# public | game_variations       | table
# public | games                 | table
# public | multiplayer_matches   | table
# public | multiplayer_rooms     | table
# public | room_participants     | table
# public | users                 | table
# public | words                 | table
```

## Schema Overview

### Tables

1. **users** - User profiles and authentication
   - `user_id` (SERIAL PK)
   - `username`, `email`, `password_hash`
   - `coins`, `total_score`
   - `is_guest`, `is_report_blocked`

2. **games** - Game definitions
   - `game_id` (SERIAL PK)
   - `name`, `description`
   - `has_daily_challenge`, `has_multiplayer`, `status`

3. **game_variations** - Game rule variations
   - `variation_id` (SERIAL PK)
   - `name`, `params_json` (JSONB)
   - `player_count`, `game_id` (FK)

4. **words** - Word database (optimized for queries)
   - `word_id` (SERIAL PK)
   - `text`, `length`, `difficulty_level`
   - `is_soft_deleted`
   - **Indexes:** length, difficulty, text (case-insensitive)

5. **daily_challenges** - Daily challenge setup
   - `daily_challenge_id` (SERIAL PK)
   - `challenge_date`, `data_json` (JSONB)
   - `status`, `game_id`, `variation_id` (FKs)

6. **friendships** - User friend relationships
   - `friendship_id` (SERIAL PK)
   - `user_id_1`, `user_id_2` (FKs to users)
   - `status` (pending, accepted, blocked)
   - **Constraints:**
     - UNIQUE(user_id_1, user_id_2) - prevent duplicates
     - CHECK(user_id_1 <> user_id_2) - prevent self-friendship

7. **multiplayer_rooms** - Active/ended multiplayer game rooms
   - `room_id` (SERIAL PK)
   - `room_code` (unique join code)
   - `status` (lobby, active, ended)
   - `created_by_user_id`, `admin_user_id` (FKs)
   - `game_id`, `variation_id` (FKs)

8. **room_participants** - Many-to-many join table for room membership
   - `room_id`, `user_id` (composite PK)
   - `joined_at`, `left_at` timestamps

9. **multiplayer_matches** - Match results
   - `match_id` (SERIAL PK)
   - `result_data_json` (JSONB)
   - `room_id`, `winner_user_id` (FKs)

## Key Features

### SERIAL Primary Keys
All tables use `SERIAL` (auto-incrementing) primary keys for easy manual test data insertion:
```sql
INSERT INTO users (username, email, password_hash) 
VALUES ('testuser', 'test@example.com', 'hash123');
-- user_id will auto-increment
```

### JSONB Fields
Structured data stored as JSONB for efficient queries and indexing:
- `games_variations.params_json` - Game-specific parameters
- `daily_challenges.data_json` - Challenge configuration
- `multiplayer_matches.result_data_json` - Match results

Example:
```json
{
  "max_attempts": 6,
  "time_limit_sec": 60,
  "difficulty": "medium"
}
```

### Optimized Word Lookups
- `idx_words_length` - Fast filtering by word length
- `idx_words_difficulty` - Fast filtering by difficulty level
- `idx_words_text_lower` - Case-insensitive text search

## Manual Data Insertion

### Create a Game

```sql
INSERT INTO games (name, description, has_daily_challenge, has_multiplayer, status)
VALUES ('Wordle', 'Guess the 5-letter word in 6 tries', true, false, 'active');
```

### Create Game Variation

```sql
INSERT INTO game_variations (name, params_json, player_count, game_id)
VALUES (
  'Classic',
  '{"max_attempts": 6, "word_length": 5}'::jsonb,
  1,
  1
);
```

### Add Words

```sql
INSERT INTO words (text, length, difficulty_level)
VALUES 
  ('apple', 5, 1),
  ('python', 6, 2),
  ('extraordinary', 13, 5);
```

### Create Users

```sql
INSERT INTO users (username, email, password_hash, is_guest, coins, total_score)
VALUES 
  ('user1', 'user1@example.com', 'hash1', false, 100, 500),
  ('user2', 'user2@example.com', 'hash2', false, 50, 300),
  ('guest1', NULL, NULL, true, 0, 0);
```

### Create Friendships

```sql
INSERT INTO friendships (user_id_1, user_id_2, status)
VALUES (1, 2, 'accepted');
```

## Useful Queries

### Get Word Statistics

```sql
SELECT
  COUNT(*) as total_words,
  AVG(length) as avg_length,
  MAX(difficulty_level) as max_difficulty
FROM words
WHERE is_soft_deleted = FALSE;
```

### Get Top Players

```sql
SELECT user_id, username, total_score, coins
FROM users
ORDER BY total_score DESC
LIMIT 10;
```

### Get Active Rooms

```sql
SELECT r.room_id, r.room_code, r.status, COUNT(p.user_id) as player_count
FROM multiplayer_rooms r
LEFT JOIN room_participants p ON r.room_id = p.room_id
WHERE r.status IN ('lobby', 'active')
GROUP BY r.room_id
ORDER BY r.created_at DESC;
```

### Soft-Delete Words

```sql
UPDATE words
SET is_soft_deleted = TRUE
WHERE text ILIKE '%badword%';
```

### Reset Sequences (if needed for testing)

```sql
-- Reset user sequence to start after highest ID
SELECT setval('users_user_id_seq', (SELECT MAX(user_id) FROM users), true);

-- Reset all sequences
SELECT setval(pg_get_serial_sequence(tablename,'id'), 
              COALESCE((SELECT MAX(id) FROM '||tablename), 1), true)
FROM information_schema.tables 
WHERE table_schema='public' AND table_type='BASE TABLE';
```

## Development Workflow

1. **Schema setup:** Run `schema_v1.sql` once
2. **Manual testing:** Insert test data directly with INSERT statements
3. **Backend testing:** Use FastAPI endpoints to read/modify data
4. **Reset data:** Delete rows and re-insert as needed (sequences auto-increment)

## Important Notes

- **Local-only:** This schema is optimized for ease of development, not production security
- **No triggers:** Timestamps must be managed by application logic
- **No constraints:** Foreign key constraints use `ON DELETE CASCADE` for easy testing
- **SERIAL vs GENERATED:** Uses SERIAL (compatible with `psql` and direct SQL) instead of GENERATED ALWAYS AS IDENTITY

## Troubleshooting

### Connection Error
```
psql: error: could not connect to server
```
→ Make sure PostgreSQL is running: `brew services list` or check system services

### Permission Denied
```
ERROR: permission denied for schema public
```
→ Verify connection credentials: `psql postgresql://USER:PASS@localhost:5432/DATABASE`

### Constraint Violation (Friendships)
```
ERROR: new row for relation "friendships" violates check constraint "no_self_friendship"
```
→ user_id_1 and user_id_2 must be different users

## Next Steps

- Create seed data loading script
- Add migration versioning system (e.g., Flyway, liquibase)
- Add data backup/restore procedures
- Create development vs. test database separation
