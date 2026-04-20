import 'session_user.dart';

class SessionSignUpResult {
  const SessionSignUpResult._({
    this.user,
    this.requiresEmailConfirmation = false,
    this.message,
  });

  const SessionSignUpResult.signedIn(SessionUser user) : this._(user: user);

  const SessionSignUpResult.emailConfirmationRequired(String message)
    : this._(
        requiresEmailConfirmation: true,
        message: message,
      );

  final SessionUser? user;
  final bool requiresEmailConfirmation;
  final String? message;
}

abstract class SessionRepository {
  Future<SessionUser?> restore();

  Future<SessionUser> continueAsGuest();

  Future<SessionUser> signInWithEmail({
    required String email,
    required String password,
  });

  Future<SessionSignUpResult> signUpWithEmail({
    required String email,
    required String password,
  });

  Future<void> signOut();
}
