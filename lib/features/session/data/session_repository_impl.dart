import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/session_repository.dart';
import '../domain/session_user.dart';

class SessionRepositoryImpl implements SessionRepository {
  const SessionRepositoryImpl({required this.supabaseClient});

  final SupabaseClient? supabaseClient;

  @override
  Future<SessionUser?> restore() async {
    final session = supabaseClient?.auth.currentSession;
    final user = session?.user;

    if (user == null) {
      return null;
    }

    return _mapUser(user);
  }

  @override
  Future<SessionUser> continueAsGuest() async {
    return const SessionUser.guest();
  }

  @override
  Future<SessionUser> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (supabaseClient == null) {
      throw const SessionFailure(
        'Live auth is disabled. Add SUPABASE_URL and SUPABASE_ANON_KEY first.',
      );
    }

    final response = await supabaseClient!.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = response.user;
    if (user == null) {
      throw const SessionFailure('No user was returned from Supabase auth.');
    }

    return _mapUser(user);
  }

  @override
  Future<SessionSignUpResult> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    if (supabaseClient == null) {
      throw const SessionFailure(
        'Live auth is disabled. Add SUPABASE_URL and SUPABASE_ANON_KEY first.',
      );
    }

    final response = await supabaseClient!.auth.signUp(
      email: email,
      password: password,
      data: <String, dynamic>{
        'display_name': _displayNameFromEmail(email),
      },
    );

    final user = response.user;
    if (user == null) {
      throw const SessionFailure('No user was returned from Supabase auth.');
    }

    if (response.session == null) {
      return const SessionSignUpResult.emailConfirmationRequired(
        'Account created. Confirm your email, then sign in to sync progress.',
      );
    }

    return SessionSignUpResult.signedIn(await _mapUser(user));
  }

  @override
  Future<void> signOut() async {
    await supabaseClient?.auth.signOut();
  }

  Future<SessionUser> _mapUser(User user) async {
    var displayName = user.userMetadata?['display_name'] as String?;
    var streakDays = 3;
    var totalXp = 120;

    if (supabaseClient != null) {
      try {
        final profile = await supabaseClient!
            .from('profiles')
            .select('display_name, streak_days, total_xp')
            .eq('id', user.id)
            .maybeSingle();

        if (profile != null) {
          displayName = profile['display_name'] as String? ?? displayName;
          streakDays = (profile['streak_days'] as num?)?.toInt() ?? streakDays;
          totalXp = (profile['total_xp'] as num?)?.toInt() ?? totalXp;
        }
      } catch (_) {
        // The app should stay usable while the backend schema is still being set up.
      }
    }

    return SessionUser(
      id: user.id,
      displayName: displayName ?? user.email ?? 'Rocket Reader',
      streakDays: streakDays,
      totalXp: totalXp,
      isGuest: false,
    );
  }

  String _displayNameFromEmail(String email) {
    final localPart = email.split('@').first.trim();
    if (localPart.isEmpty) {
      return 'Rocket Reader';
    }
    return localPart.replaceAll(RegExp(r'[._-]+'), ' ');
  }
}

class SessionFailure implements Exception {
  const SessionFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
