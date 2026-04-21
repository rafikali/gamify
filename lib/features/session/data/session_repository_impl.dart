import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/session_repository.dart';
import '../domain/session_user.dart';

class SessionRepositoryImpl implements SessionRepository {
  SessionRepositoryImpl({
    required this.firebaseAuth,
    required this.firestore,
    required this.googleWebClientId,
    required this.googleIosClientId,
  });

  final FirebaseAuth? firebaseAuth;
  final FirebaseFirestore? firestore;
  final String googleWebClientId;
  final String googleIosClientId;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  Future<void>? _googleInitialization;

  @override
  Future<SessionUser?> restore() async {
    final user = firebaseAuth?.currentUser;

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
    if (firebaseAuth == null) {
      throw const SessionFailure(
        'Live auth is disabled. Add the Firebase dart-defines first.',
      );
    }

    try {
      final credential = await firebaseAuth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const SessionFailure('No user was returned from Firebase Auth.');
      }

      return _mapUser(user);
    } on FirebaseAuthException catch (error) {
      throw SessionFailure(_authErrorMessage(error));
    }
  }

  @override
  Future<SessionUser> signInWithGoogle() async {
    if (firebaseAuth == null) {
      throw const SessionFailure(
        'Live auth is disabled. Add the Firebase dart-defines first.',
      );
    }

    try {
      if (kIsWeb) {
        final userCredential = await firebaseAuth!.signInWithPopup(
          GoogleAuthProvider(),
        );
        final user = userCredential.user;
        if (user == null) {
          throw const SessionFailure(
            'No user was returned from Google sign-in.',
          );
        }
        return _mapUser(user);
      }

      if (!_googleSignIn.supportsAuthenticate()) {
        throw const SessionFailure(
          'Google sign-in is not supported on this platform.',
        );
      }

      await _ensureGoogleInitialized();

      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null || idToken.trim().isEmpty) {
        throw const SessionFailure(
          'Google sign-in did not return an ID token.',
        );
      }

      final userCredential = await firebaseAuth!.signInWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      final user = userCredential.user;
      if (user == null) {
        throw const SessionFailure('No user was returned from Google sign-in.');
      }

      return _mapUser(user);
    } on GoogleSignInException catch (error) {
      throw SessionFailure(_googleErrorMessage(error));
    } on FirebaseAuthException catch (error) {
      throw SessionFailure(_authErrorMessage(error));
    }
  }

  @override
  Future<SessionSignUpResult> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    if (firebaseAuth == null) {
      throw const SessionFailure(
        'Live auth is disabled. Add the Firebase dart-defines first.',
      );
    }

    try {
      final credential = await firebaseAuth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const SessionFailure('No user was returned from Firebase Auth.');
      }

      final displayName = _displayNameFromEmail(email);
      await user.updateDisplayName(displayName);
      await _upsertProfile(
        userId: user.uid,
        displayName: displayName,
        streakDays: 3,
        totalXp: 120,
      );

      return SessionSignUpResult.signedIn(await _mapUser(user));
    } on FirebaseAuthException catch (error) {
      throw SessionFailure(_authErrorMessage(error));
    }
  }

  @override
  Future<void> signOut() async {
    final isGoogleUser =
        firebaseAuth?.currentUser?.providerData.any(
          (UserInfo provider) => provider.providerId == 'google.com',
        ) ??
        false;

    await firebaseAuth?.signOut();
    if (!kIsWeb && isGoogleUser) {
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Firebase sign-out is the source of truth. Ignore Google SDK cleanup failures.
      }
    }
  }

  Future<SessionUser> _mapUser(User user) async {
    var displayName = user.displayName;
    var streakDays = 3;
    var totalXp = 120;

    if (firestore != null) {
      try {
        final profile = await firestore!
            .collection('profiles')
            .doc(user.uid)
            .get();

        if (profile.exists) {
          final data = profile.data();
          displayName = data?['display_name'] as String? ?? displayName;
          streakDays = _intValue(data?['streak_days'], fallback: streakDays);
          totalXp = _intValue(data?['total_xp'], fallback: totalXp);
        } else {
          await _upsertProfile(
            userId: user.uid,
            displayName: displayName ?? user.email ?? 'Rocket Reader',
            streakDays: streakDays,
            totalXp: totalXp,
          );
        }
      } catch (_) {
        // The app should stay usable while the backend schema is still being set up.
      }
    }

    return SessionUser(
      id: user.uid,
      displayName: displayName ?? user.email ?? 'Rocket Reader',
      streakDays: streakDays,
      totalXp: totalXp,
      isGuest: false,
    );
  }

  Future<void> _upsertProfile({
    required String userId,
    required String displayName,
    required int streakDays,
    required int totalXp,
  }) async {
    if (firestore == null) {
      return;
    }

    await firestore!.collection('profiles').doc(userId).set(<String, dynamic>{
      'display_name': displayName,
      'streak_days': streakDays,
      'total_xp': totalXp,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String _displayNameFromEmail(String email) {
    final localPart = email.split('@').first.trim();
    if (localPart.isEmpty) {
      return 'Rocket Reader';
    }
    return localPart.replaceAll(RegExp(r'[._-]+'), ' ');
  }

  int _intValue(Object? value, {required int fallback}) {
    return (value as num?)?.toInt() ?? fallback;
  }

  Future<void> _ensureGoogleInitialized() {
    _googleInitialization ??= _initializeGoogleSignIn();
    return _googleInitialization!;
  }

  Future<void> _initializeGoogleSignIn() {
    final clientId = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => _nonEmptyOrNull(googleIosClientId),
      _ => null,
    };
    final serverClientId = _nonEmptyOrNull(googleWebClientId);

    if (defaultTargetPlatform == TargetPlatform.android &&
        serverClientId == null) {
      throw const SessionFailure(
        'Google sign-in needs GOOGLE_WEB_CLIENT_ID for Android.',
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS && clientId == null) {
      throw const SessionFailure(
        'Google sign-in needs GOOGLE_IOS_CLIENT_ID for iOS.',
      );
    }

    return _googleSignIn.initialize(
      clientId: clientId,
      serverClientId: serverClientId,
    );
  }

  String? _nonEmptyOrNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'That email is already in use. Try signing in instead.';
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email or password is incorrect.';
      case 'weak-password':
        return 'Choose a stronger password with at least 6 characters.';
      case 'operation-not-allowed':
        return 'Enable Email/Password sign-in in Firebase Authentication first.';
      case 'network-request-failed':
        return 'Network request failed. Check the connection and try again.';
      default:
        return error.message ?? 'Firebase Auth failed. Try again.';
    }
  }

  String _googleErrorMessage(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Google sign-in was canceled.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in is not configured correctly for this app.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Google sign-in UI is not available right now.';
      case GoogleSignInExceptionCode.interrupted:
        return 'Google sign-in was interrupted. Try again.';
      default:
        return error.description ?? 'Google sign-in failed. Try again.';
    }
  }
}

class SessionFailure implements Exception {
  const SessionFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
