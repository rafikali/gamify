# Prompt Change Log

This file tracks what changed for each prompt in this repo.

## 2026-04-13

### Prompt 001
User request: Fix the Supabase MCP startup failure first.

Changes made:
- Inspected the local Codex MCP configuration and verified the `supabase` server entry existed.
- Verified the Supabase MCP endpoint was reachable.
- Started and completed the `codex mcp login supabase` OAuth flow.

Result:
- Supabase MCP authentication was repaired for the local Codex setup.
- A fresh Codex session/reload is still needed for the newly authenticated server to appear cleanly in-thread.

### Prompt 002
User request: Build a production-ready Flutter mobile app for Learnify.

Changes made:
- Replaced the default Flutter counter app in [lib/main.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/main.dart).
- Added app bootstrap, router, and theme files under [lib/app](/Users/rafik/MobileAppDevelopment/learnify/lib/app) and [lib/core](/Users/rafik/MobileAppDevelopment/learnify/lib/core).
- Added session/auth scaffolding under [lib/features/session](/Users/rafik/MobileAppDevelopment/learnify/lib/features/session).
- Added learning dashboard, mock lesson data, repository contracts, gameplay bloc, and game UI under [lib/features/learning](/Users/rafik/MobileAppDevelopment/learnify/lib/features/learning).
- Added a Supabase schema scaffold at [supabase/learnify_schema.sql](/Users/rafik/MobileAppDevelopment/learnify/supabase/learnify_schema.sql).
- Updated package dependencies in [pubspec.yaml](/Users/rafik/MobileAppDevelopment/learnify/pubspec.yaml).
- Added microphone and internet permissions in [AndroidManifest.xml](/Users/rafik/MobileAppDevelopment/learnify/android/app/src/main/AndroidManifest.xml) and speech permission strings in [Info.plist](/Users/rafik/MobileAppDevelopment/learnify/ios/Runner/Info.plist).
- Replaced the starter widget test in [test/widget_test.dart](/Users/rafik/MobileAppDevelopment/learnify/test/widget_test.dart).

Status:
- The Phase 1 app structure is in place.
- Formatting and verification were not completed yet because the turn was interrupted while requesting sandbox escalation for toolchain commands.

### Prompt 003
User request: Keep a logger file of what changes were done for every prompt.

Changes made:
- Created this file at [PROMPT_CHANGE_LOG.md](/Users/rafik/MobileAppDevelopment/learnify/PROMPT_CHANGE_LOG.md).
- Added entries for the prompts already handled in this thread.
- Logging policy updated: going forward, this file will record only prompts that caused actual repo changes.

Going forward:
- I will append entries only when I actually change files in this repo.

### Prompt 004
User request: Implement the live Supabase auth flow and make completed games persist.

Changes made:
- Added email sign-up support to the session contract in [session_repository.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/features/session/domain/session_repository.dart) and implemented it in [session_repository_impl.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/features/session/data/session_repository_impl.dart).
- Expanded session state handling in [session_cubit.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/features/session/presentation/session_cubit.dart) to support sign-up, confirmation notices, and cleaner auth/guest transitions.
- Reworked the active auth screen in [auth_gate_page.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/features/session/presentation/auth_gate_page.dart) so users can sign in, create an account, or continue as guest.
- Changed onboarding to route into auth instead of forcing guest mode in [onboarding_page.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/features/session/presentation/onboarding_page.dart).
- Added a live `/auth` route and updated unauthenticated redirects in [learnify_router.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/app/learnify_router.dart).
- Fixed Supabase persistence ordering in [learning_repository_impl.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/features/learning/data/learning_repository_impl.dart) so `profiles` is upserted before inserting into `game_sessions`.

Result:
- The active app flow now supports live Supabase auth instead of only guest/mock mode.
- Completed games from authenticated users now have a valid profile row before session inserts are attempted.

### Prompt 005
User request: Redesign the gameplay screen and animation to match the provided Figma Make game screen.

Changes made:
- Rebuilt [game_page.dart](/Users/rafik/MobileAppDevelopment/learnify/lib/features/learning/presentation/game_page.dart) around the Figma Make game layout:
  - full-screen cyan-to-purple-to-charcoal gradient sky
  - animated star field
  - translucent HUD with lives, score, and power badges
  - floating word cards with motion and feedback rings
  - custom painted rocket with animated exhaust
  - bottom-center microphone dock with listening bars
  - speech status overlay tied to the gameplay state
- Kept the existing gameplay bloc integration and result routing intact while replacing the old card-based game presentation.

Verification:
- `flutter analyze` passed with no issues.
- `flutter test` passed.
