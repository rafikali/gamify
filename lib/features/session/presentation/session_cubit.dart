import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/session_repository_impl.dart';
import '../domain/session_repository.dart';
import '../domain/session_user.dart';

enum SessionStatus {
  checking,
  signedOut,
  authenticating,
  guest,
  authenticated,
  failure,
}

class SessionState {
  const SessionState({
    required this.status,
    required this.backendConfigured,
    this.user,
    this.errorMessage,
    this.noticeMessage,
    this.bootstrapWarning,
  });

  const SessionState.initial({
    required bool backendConfigured,
    required String? bootstrapWarning,
  }) : this(
         status: SessionStatus.checking,
         backendConfigured: backendConfigured,
         bootstrapWarning: bootstrapWarning,
       );

  final SessionStatus status;
  final SessionUser? user;
  final bool backendConfigured;
  final String? errorMessage;
  final String? noticeMessage;
  final String? bootstrapWarning;

  SessionState copyWith({
    SessionStatus? status,
    SessionUser? user,
    bool? backendConfigured,
    String? errorMessage,
    String? noticeMessage,
    String? bootstrapWarning,
    bool clearError = false,
    bool clearNotice = false,
  }) {
    return SessionState(
      status: status ?? this.status,
      user: user ?? this.user,
      backendConfigured: backendConfigured ?? this.backendConfigured,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      noticeMessage: clearNotice ? null : noticeMessage ?? this.noticeMessage,
      bootstrapWarning: bootstrapWarning ?? this.bootstrapWarning,
    );
  }
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit({
    required SessionRepository sessionRepository,
    required bool backendConfigured,
    required String? bootstrapWarning,
  }) : _sessionRepository = sessionRepository,
       super(
         SessionState.initial(
           backendConfigured: backendConfigured,
           bootstrapWarning: bootstrapWarning,
         ),
       );

  final SessionRepository _sessionRepository;

  Future<void> restoreSession() async {
    try {
      final user = await _sessionRepository.restore();
      if (user == null) {
        emit(
          state.copyWith(
            status: SessionStatus.signedOut,
            clearError: true,
            clearNotice: true,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          status: user.isGuest
              ? SessionStatus.guest
              : SessionStatus.authenticated,
          user: user,
          clearError: true,
          clearNotice: true,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: SessionStatus.signedOut,
          clearError: true,
          clearNotice: true,
        ),
      );
    }
  }

  Future<void> continueAsGuest() async {
    emit(
      state.copyWith(
        status: SessionStatus.authenticating,
        clearError: true,
        clearNotice: true,
      ),
    );
    final guest = await _sessionRepository.continueAsGuest();
    emit(
      state.copyWith(
        status: SessionStatus.guest,
        user: guest,
        clearError: true,
        clearNotice: true,
      ),
    );
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    emit(
      state.copyWith(
        status: SessionStatus.authenticating,
        clearError: true,
        clearNotice: true,
      ),
    );

    try {
      final user = await _sessionRepository.signInWithEmail(
        email: email,
        password: password,
      );
      emit(
        state.copyWith(
          status: SessionStatus.authenticated,
          user: user,
          clearError: true,
          clearNotice: true,
        ),
      );
    } on SessionFailure catch (failure) {
      emit(
        state.copyWith(
          status: SessionStatus.failure,
          errorMessage: failure.message,
        ),
      );
      emit(state.copyWith(status: SessionStatus.signedOut));
    } catch (error) {
      emit(
        state.copyWith(
          status: SessionStatus.failure,
          errorMessage: 'Sign-in failed: $error',
        ),
      );
      emit(state.copyWith(status: SessionStatus.signedOut));
    }
  }

  Future<void> signInWithGoogle() async {
    emit(
      state.copyWith(
        status: SessionStatus.authenticating,
        clearError: true,
        clearNotice: true,
      ),
    );

    try {
      final user = await _sessionRepository.signInWithGoogle();
      emit(
        state.copyWith(
          status: SessionStatus.authenticated,
          user: user,
          clearError: true,
          clearNotice: true,
        ),
      );
    } on SessionFailure catch (failure) {
      emit(
        state.copyWith(
          status: SessionStatus.failure,
          errorMessage: failure.message,
        ),
      );
      emit(state.copyWith(status: SessionStatus.signedOut));
    } catch (error) {
      emit(
        state.copyWith(
          status: SessionStatus.failure,
          errorMessage: 'Google sign-in failed: $error',
        ),
      );
      emit(state.copyWith(status: SessionStatus.signedOut));
    }
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    emit(
      state.copyWith(
        status: SessionStatus.authenticating,
        clearError: true,
        clearNotice: true,
      ),
    );

    try {
      final result = await _sessionRepository.signUpWithEmail(
        email: email,
        password: password,
      );

      if (result.user != null) {
        emit(
          state.copyWith(
            status: SessionStatus.authenticated,
            user: result.user,
            clearError: true,
            clearNotice: true,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          status: SessionStatus.signedOut,
          noticeMessage: result.message,
          clearError: true,
        ),
      );
    } on SessionFailure catch (failure) {
      emit(
        state.copyWith(
          status: SessionStatus.failure,
          errorMessage: failure.message,
        ),
      );
      emit(state.copyWith(status: SessionStatus.signedOut));
    } catch (error) {
      emit(
        state.copyWith(
          status: SessionStatus.failure,
          errorMessage: 'Sign-up failed: $error',
        ),
      );
      emit(state.copyWith(status: SessionStatus.signedOut));
    }
  }

  Future<void> signOut() async {
    await _sessionRepository.signOut();
    emit(
      state.copyWith(
        status: SessionStatus.signedOut,
        user: null,
        clearError: true,
        clearNotice: true,
      ),
    );
  }

  void syncUserProgress(SessionUser user) {
    emit(
      state.copyWith(
        user: user,
        status: user.isGuest
            ? SessionStatus.guest
            : SessionStatus.authenticated,
      ),
    );
  }
}
