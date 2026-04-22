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
    if (firebaseAuth == null) {
      return const SessionUser.guest();
    }

    final existingUser = firebaseAuth!.currentUser;
    if (existingUser != null) {
      return _mapUser(existingUser);
    }

    try {
      final credential = await firebaseAuth!.signInAnonymously();
      final user = credential.user;
      if (user == null) {
        throw const SessionFailure(
          'No user was returned from anonymous sign-in.',
        );
      }

      return _mapUser(user);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'operation-not-allowed') {
        return const SessionUser.guest();
      }
      throw SessionFailure(_authErrorMessage(error));
    }
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

    final guestBackup = await _captureGuestProgressIfNeeded();

    try {
      final credential = await firebaseAuth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const SessionFailure('No user was returned from Firebase Auth.');
      }

      await _mergeGuestProgressIfNeeded(
        targetUser: user,
        backup: guestBackup,
      );
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

    final guestBackup = await _captureGuestProgressIfNeeded();

    try {
      final currentUser = firebaseAuth!.currentUser;
      late final UserCredential userCredential;

      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        if (currentUser != null && currentUser.isAnonymous) {
          try {
            userCredential = await currentUser.linkWithPopup(provider);
          } on FirebaseAuthException catch (error) {
            if (!_shouldFallbackFromAnonymousLink(error)) {
              rethrow;
            }
            userCredential = await firebaseAuth!.signInWithPopup(provider);
          }
        } else {
          userCredential = await firebaseAuth!.signInWithPopup(provider);
        }
      } else {
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

        final credential = GoogleAuthProvider.credential(idToken: idToken);
        if (currentUser != null && currentUser.isAnonymous) {
          try {
            userCredential = await currentUser.linkWithCredential(credential);
          } on FirebaseAuthException catch (error) {
            if (!_shouldFallbackFromAnonymousLink(error)) {
              rethrow;
            }
            userCredential = await firebaseAuth!.signInWithCredential(
              credential,
            );
          }
        } else {
          userCredential = await firebaseAuth!.signInWithCredential(credential);
        }
      }

      final user = userCredential.user;
      if (user == null) {
        throw const SessionFailure('No user was returned from Google sign-in.');
      }

      await _mergeGuestProgressIfNeeded(
        targetUser: user,
        backup: guestBackup,
      );
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
      final currentUser = firebaseAuth!.currentUser;
      final emailCredential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      final credential =
          currentUser != null && currentUser.isAnonymous
          ? await currentUser.linkWithCredential(emailCredential)
          : await firebaseAuth!.createUserWithEmailAndPassword(
              email: email,
              password: password,
            );

      final user = credential.user;
      if (user == null) {
        throw const SessionFailure('No user was returned from Firebase Auth.');
      }

      final displayName = _displayNameFromEmail(email);
      await user.updateDisplayName(displayName);
      await user.reload();

      final refreshedUser = firebaseAuth!.currentUser ?? user;
      await _ensureProfileDocument(
        refreshedUser,
        preferredDisplayName: displayName,
      );

      return SessionSignUpResult.signedIn(await _mapUser(refreshedUser));
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
    if (firestore == null) {
      return _defaultSessionUser(user);
    }

    try {
      return await _ensureProfileDocument(user);
    } catch (_) {
      return _defaultSessionUser(user);
    }
  }

  Future<SessionUser> _ensureProfileDocument(
    User user, {
    String? preferredDisplayName,
  }) async {
    if (firestore == null) {
      return _defaultSessionUser(user, preferredDisplayName: preferredDisplayName);
    }

    final profileRef = firestore!.collection('profiles').doc(user.uid);
    final profileSnapshot = await profileRef.get();
    final sessionUser = _sessionUserFromProfile(
      user,
      profileSnapshot.data(),
      preferredDisplayName: preferredDisplayName,
    );

    await profileRef.set(
      _profileDataForUser(
        user,
        sessionUser,
        includeCreatedAt: !profileSnapshot.exists,
      ),
      SetOptions(merge: true),
    );

    return sessionUser;
  }

  SessionUser _defaultSessionUser(User user, {String? preferredDisplayName}) {
    final defaultName =
        preferredDisplayName ??
        user.displayName ??
        user.email ??
        (user.isAnonymous ? 'Cadet Learner' : 'Rocket Reader');

    return SessionUser(
      id: user.uid,
      displayName: defaultName,
      streakDays: 0,
      bestStreak: 0,
      totalXp: 0,
      wordsLearned: 0,
      gamesPlayed: 0,
      lastCategoryId: null,
      isGuest: user.isAnonymous,
    );
  }

  SessionUser _sessionUserFromProfile(
    User user,
    Map<String, dynamic>? data, {
    String? preferredDisplayName,
  }) {
    final fallback = _defaultSessionUser(
      user,
      preferredDisplayName: preferredDisplayName,
    );

    return SessionUser(
      id: user.uid,
      displayName: _stringOrNull(data?['display_name']) ?? fallback.displayName,
      streakDays: _intValue(data?['streak_days'], fallback: fallback.streakDays),
      bestStreak: _intValue(
        data?['best_streak'],
        fallback: _intValue(
          data?['streak_days'],
          fallback: fallback.bestStreak,
        ),
      ),
      totalXp: _intValue(data?['total_xp'], fallback: fallback.totalXp),
      wordsLearned: _intValue(
        data?['words_learned'],
        fallback: fallback.wordsLearned,
      ),
      gamesPlayed: _intValue(
        data?['games_played'],
        fallback: fallback.gamesPlayed,
      ),
      lastCategoryId:
          _stringOrNull(data?['last_category_id']) ?? fallback.lastCategoryId,
      isGuest: user.isAnonymous,
    );
  }

  Map<String, dynamic> _profileDataForUser(
    User user,
    SessionUser sessionUser, {
    required bool includeCreatedAt,
  }) {
    return <String, dynamic>{
      'display_name': sessionUser.displayName,
      'email': user.email,
      'photo_url': user.photoURL,
      'is_guest': user.isAnonymous,
      'auth_provider': _authProviderFor(user),
      'streak_days': sessionUser.streakDays,
      'best_streak': sessionUser.bestStreak,
      'total_xp': sessionUser.totalXp,
      'words_learned': sessionUser.wordsLearned,
      'games_played': sessionUser.gamesPlayed,
      'last_category_id': sessionUser.lastCategoryId,
      'updated_at': FieldValue.serverTimestamp(),
      if (includeCreatedAt) 'created_at': FieldValue.serverTimestamp(),
    };
  }

  Future<_GuestProgressBackup?> _captureGuestProgressIfNeeded() async {
    final currentUser = firebaseAuth?.currentUser;
    if (firestore == null || currentUser == null || !currentUser.isAnonymous) {
      return null;
    }

    try {
      final profileRef = firestore!.collection('profiles').doc(currentUser.uid);
      final results = await Future.wait<Object>(<Future<Object>>[
        profileRef.get(),
        profileRef.collection('category_progress').get(),
      ]);
      final profileSnapshot =
          results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final categoryProgressSnapshot =
          results[1] as QuerySnapshot<Map<String, dynamic>>;

      return _GuestProgressBackup(
        sourceUserId: currentUser.uid,
        profileData: profileSnapshot.data() ?? <String, dynamic>{},
        categoryProgress: categoryProgressSnapshot.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                  _DocumentBackup(id: doc.id, data: doc.data()),
            )
            .toList(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _mergeGuestProgressIfNeeded({
    required User targetUser,
    required _GuestProgressBackup? backup,
  }) async {
    if (firestore == null ||
        backup == null ||
        backup.sourceUserId == targetUser.uid) {
      return;
    }

    final profileRef = firestore!.collection('profiles').doc(targetUser.uid);
    final profileSnapshot = await profileRef.get();
    final existingProfile = profileSnapshot.data();
    final existingUser = _sessionUserFromProfile(targetUser, existingProfile);
    final guestStreak = _intValue(backup.profileData['streak_days'], fallback: 0);
    final guestBestStreak = _intValue(
      backup.profileData['best_streak'],
      fallback: guestStreak,
    );

    final mergedUser = existingUser.copyWith(
      streakDays: _maxInt(existingUser.streakDays, guestStreak),
      bestStreak: _maxInt(existingUser.bestStreak, guestBestStreak),
      totalXp:
          existingUser.totalXp +
          _intValue(backup.profileData['total_xp'], fallback: 0),
      wordsLearned:
          existingUser.wordsLearned +
          _intValue(backup.profileData['words_learned'], fallback: 0),
      gamesPlayed:
          existingUser.gamesPlayed +
          _intValue(backup.profileData['games_played'], fallback: 0),
      lastCategoryId: _resolveMergedLastCategoryId(
        targetCategoryId: existingUser.lastCategoryId,
        targetLastPlayedAt: _timestampValue(existingProfile?['last_played_at']),
        guestCategoryId: _stringOrNull(backup.profileData['last_category_id']),
        guestLastPlayedAt: _timestampValue(backup.profileData['last_played_at']),
      ),
      isGuest: targetUser.isAnonymous,
    );

    final mergedProfileData = _profileDataForUser(
      targetUser,
      mergedUser,
      includeCreatedAt: !profileSnapshot.exists,
    );
    final latestLastPlayedAt = _latestTimestamp(
      _timestampValue(existingProfile?['last_played_at']),
      _timestampValue(backup.profileData['last_played_at']),
    );
    if (latestLastPlayedAt != null) {
      mergedProfileData['last_played_at'] = latestLastPlayedAt;
    }

    await profileRef.set(mergedProfileData, SetOptions(merge: true));

    for (final backupDoc in backup.categoryProgress) {
      final progressRef = profileRef
          .collection('category_progress')
          .doc(backupDoc.id);
      final progressSnapshot = await progressRef.get();
      await progressRef.set(
        _mergeCategoryProgress(
          targetData: progressSnapshot.data(),
          guestData: backupDoc.data,
          categoryId: backupDoc.id,
        ),
        SetOptions(merge: true),
      );
    }
  }

  Map<String, dynamic> _mergeCategoryProgress({
    required Map<String, dynamic>? targetData,
    required Map<String, dynamic> guestData,
    required String categoryId,
  }) {
    final targetCorrect = _intValue(targetData?['correct_answers'], fallback: 0);
    final guestCorrect = _intValue(guestData['correct_answers'], fallback: 0);
    final targetWrong = _intValue(targetData?['wrong_answers'], fallback: 0);
    final guestWrong = _intValue(guestData['wrong_answers'], fallback: 0);
    final totalCorrect = targetCorrect + guestCorrect;
    final totalWrong = targetWrong + guestWrong;
    final totalAttempts = totalCorrect + totalWrong;

    final targetLastPlayedAt = _timestampValue(targetData?['last_played_at']);
    final guestLastPlayedAt = _timestampValue(guestData['last_played_at']);
    final guestIsLatest = _isMoreRecent(
      candidate: guestLastPlayedAt,
      baseline: targetLastPlayedAt,
    );

    return <String, dynamic>{
      'category_id':
          _stringOrNull(targetData?['category_id']) ??
          _stringOrNull(guestData['category_id']) ??
          categoryId,
      'correct_answers': totalCorrect,
      'wrong_answers': totalWrong,
      'times_played':
          _intValue(targetData?['times_played'], fallback: 0) +
          _intValue(guestData['times_played'], fallback: 0),
      'cleared_count':
          _intValue(targetData?['cleared_count'], fallback: 0) +
          _intValue(guestData['cleared_count'], fallback: 0),
      'best_score': _maxInt(
        _intValue(targetData?['best_score'], fallback: 0),
        _intValue(guestData['best_score'], fallback: 0),
      ),
      'last_score': guestIsLatest
          ? _intValue(
              guestData['last_score'],
              fallback: _intValue(targetData?['last_score'], fallback: 0),
            )
          : _intValue(
              targetData?['last_score'],
              fallback: _intValue(guestData['last_score'], fallback: 0),
            ),
      'mastery_percent': totalAttempts == 0 ? 0.0 : totalCorrect / totalAttempts,
      'last_played_at': _latestTimestamp(targetLastPlayedAt, guestLastPlayedAt),
      'updated_at': FieldValue.serverTimestamp(),
    };
  }

  String? _resolveMergedLastCategoryId({
    required String? targetCategoryId,
    required Timestamp? targetLastPlayedAt,
    required String? guestCategoryId,
    required Timestamp? guestLastPlayedAt,
  }) {
    if (_isMoreRecent(candidate: guestLastPlayedAt, baseline: targetLastPlayedAt)) {
      return guestCategoryId ?? targetCategoryId;
    }
    return targetCategoryId ?? guestCategoryId;
  }

  bool _isMoreRecent({
    required Timestamp? candidate,
    required Timestamp? baseline,
  }) {
    if (candidate == null) {
      return false;
    }
    if (baseline == null) {
      return true;
    }
    return candidate.toDate().isAfter(baseline.toDate());
  }

  Timestamp? _latestTimestamp(Timestamp? first, Timestamp? second) {
    if (first == null) {
      return second;
    }
    if (second == null) {
      return first;
    }
    return first.toDate().isAfter(second.toDate()) ? first : second;
  }

  bool _shouldFallbackFromAnonymousLink(FirebaseAuthException error) {
    return <String>{
      'credential-already-in-use',
      'email-already-in-use',
      'account-exists-with-different-credential',
    }.contains(error.code);
  }

  String _authProviderFor(User user) {
    if (user.isAnonymous) {
      return 'anonymous';
    }

    for (final provider in user.providerData) {
      if (provider.providerId != 'firebase') {
        return provider.providerId;
      }
    }
    return 'password';
  }

  String _displayNameFromEmail(String email) {
    final localPart = email.split('@').first.trim();
    if (localPart.isEmpty) {
      return 'Rocket Reader';
    }
    return localPart
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .trim()
        .split(' ')
        .where((String segment) => segment.isNotEmpty)
        .map(
          (String segment) =>
              '${segment[0].toUpperCase()}${segment.substring(1)}',
        )
        .join(' ');
  }

  int _intValue(Object? value, {required int fallback}) {
    return (value as num?)?.toInt() ?? fallback;
  }

  int _maxInt(int a, int b) => a > b ? a : b;

  String? _stringOrNull(Object? value) {
    final stringValue = value as String?;
    if (stringValue == null || stringValue.trim().isEmpty) {
      return null;
    }
    return stringValue;
  }

  Timestamp? _timestampValue(Object? value) {
    return value is Timestamp ? value : null;
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
        return 'Enable the required Firebase Authentication provider first.';
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

class _GuestProgressBackup {
  const _GuestProgressBackup({
    required this.sourceUserId,
    required this.profileData,
    required this.categoryProgress,
  });

  final String sourceUserId;
  final Map<String, dynamic> profileData;
  final List<_DocumentBackup> categoryProgress;
}

class _DocumentBackup {
  const _DocumentBackup({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class SessionFailure implements Exception {
  const SessionFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
