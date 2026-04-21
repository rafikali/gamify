# learnify

Learnify is a Flutter vocabulary game with guest mode plus a live backend path powered by Firebase Authentication and Cloud Firestore.

Current Firebase project created for this workspace: `learnify-rafik-20260421`.

## Firebase setup

The app now reads Firebase configuration from Flutter dart-defines instead of hardcoding project values in source.

1. Create a Firebase project.
2. Register these app IDs if you keep the current defaults:
   - Android package: `com.example.learnify`
   - iOS bundle ID: `com.example.learnify`
3. Enable Email/Password sign-in in Firebase Authentication.
4. Create a Cloud Firestore database in Native mode.
5. Use the checked-out local [`firebase.env.json`](./firebase.env.json) file, or regenerate it from [`firebase.env.example.json`](./firebase.env.example.json) if you point the app at another Firebase project later.
6. Run the app with:

```bash
flutter run --dart-define-from-file=firebase.env.json
```

For web:

```bash
flutter run -d chrome --dart-define-from-file=firebase.env.json
```

If the Firebase values are missing or invalid, the app stays usable in mock mode.

## Google sign-in

Google sign-in is configured for the current Firebase project on the app side.

- The Firebase project has Google as an enabled auth provider.
- The Android debug SHA fingerprints for this machine are already registered in Firebase.
- iOS URL scheme support is added in [`ios/Runner/Info.plist`](./ios/Runner/Info.plist).

If you change the Firebase project later, update:

- [`firebase.env.json`](./firebase.env.json)
- [`firebase.env.example.json`](./firebase.env.example.json)
- [`ios/Runner/Info.plist`](./ios/Runner/Info.plist)

If you want Google sign-in to work in Android release builds, add the release keystore SHA-1 and SHA-256 to the Firebase Android app as well.

## Firestore structure

This app expects these collections:

- `categories`
- `words`
- `profiles`
- `profiles/{userId}/achievements`
- `profiles/{userId}/game_sessions`

Document fields match the previous backend model:

- `categories`: `title`, `description`, `icon_name`, `accent_hex`, `emoji`, `image_url`, `total_words`, `mastery_percent`, `sort_order`
- `words`: `category_id`, `answer`, `emoji`, `image_url`, `fun_fact`, `pronunciation_hint`
- `profiles`: `display_name`, `streak_days`, `total_xp`, `updated_at`
- `achievements`: `title`, `description`, `emoji`, `progress`, `unlocked`
- `game_sessions`: `category_id`, `score`, `correct_answers`, `wrong_answers`, `cleared_all`, `elapsed_seconds`, `created_at`

Security rules and Firebase CLI config are included in:

- [`firestore.rules`](./firestore.rules)
- [`firestore.indexes.json`](./firestore.indexes.json)
- [`firebase.json`](./firebase.json)
