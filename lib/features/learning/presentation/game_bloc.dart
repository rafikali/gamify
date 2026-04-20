import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/voice/speech_recognition_service.dart';
import '../../session/domain/session_user.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';

sealed class GameEvent {
  const GameEvent();
}

class GameStarted extends GameEvent {
  const GameStarted(this.categoryId);

  final String categoryId;
}

class ListenPressed extends GameEvent {
  const ListenPressed();
}

class _TranscriptReceived extends GameEvent {
  const _TranscriptReceived(this.text, this.isFinal);

  final String text;
  final bool isFinal;
}

class _RoundTicked extends GameEvent {
  const _RoundTicked();
}

class _AdvanceRoundRequested extends GameEvent {
  const _AdvanceRoundRequested();
}

class _SpeechFailed extends GameEvent {
  const _SpeechFailed(this.message);

  final String message;
}

enum GamePhase { loading, ready, listening, feedback, completed, failure }

class GameState {
  const GameState({
    required this.phase,
    required this.challenges,
    required this.currentIndex,
    required this.score,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.remainingLives,
    required this.secondsLeft,
    required this.combo,
    required this.speechReady,
    this.category,
    this.feedback,
    this.transcript = '',
    this.updatedUser,
    this.errorMessage,
  });

  const GameState.initial()
    : this(
        phase: GamePhase.loading,
        challenges: const <WordChallenge>[],
        currentIndex: 0,
        score: 0,
        correctAnswers: 0,
        wrongAnswers: 0,
        remainingLives: 3,
        secondsLeft: 8,
        combo: 0,
        speechReady: false,
      );

  final GamePhase phase;
  final LearningCategory? category;
  final List<WordChallenge> challenges;
  final int currentIndex;
  final int score;
  final int correctAnswers;
  final int wrongAnswers;
  final int remainingLives;
  final int secondsLeft;
  final int combo;
  final bool speechReady;
  final String? feedback;
  final String transcript;
  final SessionUser? updatedUser;
  final String? errorMessage;

  WordChallenge? get currentChallenge =>
      currentIndex < challenges.length ? challenges[currentIndex] : null;

  bool get canListen =>
      phase == GamePhase.ready || phase == GamePhase.listening;

  GameState copyWith({
    GamePhase? phase,
    LearningCategory? category,
    List<WordChallenge>? challenges,
    int? currentIndex,
    int? score,
    int? correctAnswers,
    int? wrongAnswers,
    int? remainingLives,
    int? secondsLeft,
    int? combo,
    bool? speechReady,
    String? feedback,
    String? transcript,
    SessionUser? updatedUser,
    String? errorMessage,
    bool clearFeedback = false,
    bool clearError = false,
  }) {
    return GameState(
      phase: phase ?? this.phase,
      category: category ?? this.category,
      challenges: challenges ?? this.challenges,
      currentIndex: currentIndex ?? this.currentIndex,
      score: score ?? this.score,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      wrongAnswers: wrongAnswers ?? this.wrongAnswers,
      remainingLives: remainingLives ?? this.remainingLives,
      secondsLeft: secondsLeft ?? this.secondsLeft,
      combo: combo ?? this.combo,
      speechReady: speechReady ?? this.speechReady,
      feedback: clearFeedback ? null : feedback ?? this.feedback,
      transcript: transcript ?? this.transcript,
      updatedUser: updatedUser ?? this.updatedUser,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

class GameBloc extends Bloc<GameEvent, GameState> {
  GameBloc({
    required LearningRepository learningRepository,
    required SpeechRecognitionService speechRecognitionService,
    required SessionUser user,
  }) : _learningRepository = learningRepository,
       _speechRecognitionService = speechRecognitionService,
       _user = user,
       super(const GameState.initial()) {
    on<GameStarted>(_onStarted);
    on<ListenPressed>(_onListenPressed);
    on<_TranscriptReceived>(_onTranscriptReceived);
    on<_RoundTicked>(_onRoundTicked);
    on<_AdvanceRoundRequested>(_onAdvanceRoundRequested);
    on<_SpeechFailed>(_onSpeechFailed);
  }

  final LearningRepository _learningRepository;
  final SpeechRecognitionService _speechRecognitionService;
  final SessionUser _user;

  Timer? _roundTimer;
  Timer? _advanceTimer;
  DateTime? _startedAt;

  Future<void> _onStarted(GameStarted event, Emitter<GameState> emit) async {
    _startedAt = DateTime.now();

    emit(const GameState.initial());

    final speechReady = await _speechRecognitionService.initialize();
    final session = await _learningRepository.startGame(
      user: _user,
      categoryId: event.categoryId,
    );

    emit(
      state.copyWith(
        phase: GamePhase.ready,
        category: session.category,
        challenges: session.challenges,
        speechReady: speechReady,
        clearFeedback: true,
        clearError: true,
      ),
    );

    _startRoundTimer(emit);
  }

  Future<void> _onListenPressed(
    ListenPressed event,
    Emitter<GameState> emit,
  ) async {
    if (!state.speechReady || !state.canListen) {
      emit(
        state.copyWith(
          feedback: 'Speech is not ready yet. You can still play in mock mode.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        phase: GamePhase.listening,
        feedback: 'Listening for the answer...',
        transcript: '',
      ),
    );

    await _speechRecognitionService.listen(
      onResult: (String transcript, bool isFinal) {
        add(_TranscriptReceived(transcript, isFinal));
      },
      onError: (String message) {
        add(_SpeechFailed(message));
      },
    );
  }

  Future<void> _onTranscriptReceived(
    _TranscriptReceived event,
    Emitter<GameState> emit,
  ) async {
    final challenge = state.currentChallenge;
    if (challenge == null) {
      return;
    }

    emit(state.copyWith(transcript: event.text));

    final normalizedAnswer = _normalize(challenge.answer);
    final normalizedSpoken = _normalize(event.text);

    if (normalizedSpoken.contains(normalizedAnswer)) {
      await _speechRecognitionService.stop();
      _cancelRoundTimer();
      emit(
        state.copyWith(
          phase: GamePhase.feedback,
          score: state.score + 12 + (state.combo * 2),
          correctAnswers: state.correctAnswers + 1,
          combo: state.combo + 1,
          feedback: 'Boost! ${challenge.answer.toUpperCase()} cleared.',
        ),
      );
      _queueAdvance();
      return;
    }

    if (event.isFinal) {
      await _speechRecognitionService.stop();
      _cancelRoundTimer();
      emit(
        state.copyWith(
          phase: GamePhase.feedback,
          wrongAnswers: state.wrongAnswers + 1,
          remainingLives: state.remainingLives - 1,
          combo: 0,
          feedback: 'Crash! Say "${challenge.answer}" to keep flying.',
        ),
      );
      _queueAdvance();
    }
  }

  void _onRoundTicked(_RoundTicked event, Emitter<GameState> emit) {
    if (state.secondsLeft <= 1) {
      _cancelRoundTimer();
      emit(
        state.copyWith(
          phase: GamePhase.feedback,
          wrongAnswers: state.wrongAnswers + 1,
          remainingLives: state.remainingLives - 1,
          combo: 0,
          feedback:
              'Out of time. The answer was "${state.currentChallenge?.answer}".',
        ),
      );
      _queueAdvance();
      return;
    }

    emit(state.copyWith(secondsLeft: state.secondsLeft - 1));
  }

  Future<void> _onAdvanceRoundRequested(
    _AdvanceRoundRequested event,
    Emitter<GameState> emit,
  ) async {
    final nextIndex = state.currentIndex + 1;
    final isOutOfLives = state.remainingLives <= 0;
    final hasMoreRounds = nextIndex < state.challenges.length;

    if (!hasMoreRounds || isOutOfLives) {
      await _finishGame(emit);
      return;
    }

    emit(
      state.copyWith(
        phase: GamePhase.ready,
        currentIndex: nextIndex,
        secondsLeft: 8,
        transcript: '',
        clearFeedback: true,
      ),
    );
    _startRoundTimer(emit);
  }

  Future<void> _onSpeechFailed(
    _SpeechFailed event,
    Emitter<GameState> emit,
  ) async {
    await _speechRecognitionService.stop();
    emit(state.copyWith(phase: GamePhase.ready, feedback: event.message));
  }

  Future<void> _finishGame(Emitter<GameState> emit) async {
    _cancelRoundTimer();
    final startedAt = _startedAt ?? DateTime.now();
    final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
    final updatedUser = await _learningRepository.completeGame(
      user: _user,
      summary: GameSummary(
        categoryId: state.category?.id ?? 'unknown',
        score: state.score,
        correctAnswers: state.correctAnswers,
        wrongAnswers: state.wrongAnswers,
        clearedAll: state.remainingLives > 0,
        elapsedSeconds: elapsedSeconds,
      ),
    );

    emit(
      state.copyWith(
        phase: GamePhase.completed,
        updatedUser: updatedUser,
        feedback: state.remainingLives > 0
            ? 'Mission complete. Nice flying.'
            : 'Mission over. Refuel and try again.',
      ),
    );
  }

  void _startRoundTimer(Emitter<GameState> emit) {
    _cancelRoundTimer();
    emit(state.copyWith(secondsLeft: 8, phase: GamePhase.ready));
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      add(const _RoundTicked());
    });
  }

  void _queueAdvance() {
    _advanceTimer?.cancel();
    _advanceTimer = Timer(const Duration(milliseconds: 1200), () {
      add(const _AdvanceRoundRequested());
    });
  }

  void _cancelRoundTimer() {
    _roundTimer?.cancel();
  }

  String _normalize(String value) {
    final cleaned = value.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  Future<void> close() async {
    _cancelRoundTimer();
    _advanceTimer?.cancel();
    await _speechRecognitionService.stop();
    return super.close();
  }
}
