# Firebase Data Model

This app works best with these Firebase Authentication providers enabled:

- Anonymous
- Email/Password
- Google

## Firestore collections

The starter content for `categories` and `words` is available in
`firestore.seed.json` at the repo root.

### `categories/{categoryId}`

Seed this collection manually for the learning content shown on the dashboard.

Recommended fields:

- `title` `string`
- `description` `string`
- `icon_name` `string`
- `accent_hex` `string`
- `emoji` `string`
- `image_url` `string | null`
- `total_words` `number`
- `sort_order` `number`

### `words/{wordId}`

Seed this collection manually for the playable vocabulary.

Recommended fields:

- `category_id` `string`
- `answer` `string`
- `emoji` `string`
- `image_url` `string | null`
- `fun_fact` `string`
- `pronunciation_hint` `string`

### `profiles/{uid}`

Created and maintained automatically by the app for email, Google, and anonymous guest users.

Fields used by the app:

- `display_name` `string`
- `email` `string | null`
- `photo_url` `string | null`
- `is_guest` `bool`
- `auth_provider` `string`
- `streak_days` `number`
- `best_streak` `number`
- `total_xp` `number`
- `words_learned` `number`
- `games_played` `number`
- `last_category_id` `string | null`
- `last_played_at` `timestamp | null`
- `created_at` `timestamp`
- `updated_at` `timestamp`

### `profiles/{uid}/category_progress/{categoryId}`

Created and maintained automatically when a user finishes a game.

Fields used by the app:

- `category_id` `string`
- `times_played` `number`
- `correct_answers` `number`
- `wrong_answers` `number`
- `cleared_count` `number`
- `best_score` `number`
- `last_score` `number`
- `mastery_percent` `number`
- `last_played_at` `timestamp`
- `updated_at` `timestamp`

### `profiles/{uid}/game_sessions/{sessionId}`

Created and maintained automatically for weekly progress and game history.

Fields used by the app:

- `category_id` `string`
- `score` `number`
- `correct_answers` `number`
- `wrong_answers` `number`
- `cleared_all` `bool`
- `elapsed_seconds` `number`
- `created_at` `timestamp`

## Guest mode behavior

- If Anonymous auth is enabled, `Continue as Guest` signs the player in anonymously and saves guest progress in Firebase.
- If Anonymous auth is disabled, `Continue as Guest` falls back to a local-only guest session.
- When possible, guest accounts are upgraded into email or Google accounts so progress is preserved.
