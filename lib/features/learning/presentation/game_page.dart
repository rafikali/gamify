import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/voice/speech_recognition_service.dart';
import '../../session/presentation/session_cubit.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'game_audio_controller.dart';
import 'game_bloc.dart';

// ────────────────────────────────────────────────────────────────────────────────
// Entry
// ────────────────────────────────────────────────────────────────────────────────

class GamePage extends StatelessWidget {
  const GamePage({
    super.key,
    required this.categoryId,
    required this.speechRecognitionService,
    this.gameType = GameType.rocketRush,
  });

  final String categoryId;
  final SpeechRecognitionService speechRecognitionService;
  final GameType gameType;

  @override
  Widget build(BuildContext context) {
    final user = context.read<SessionCubit>().state.user!;

    return BlocProvider<GameBloc>(
      create: (BuildContext context) => GameBloc(
        learningRepository: context.read<LearningRepository>(),
        speechRecognitionService: speechRecognitionService,
        user: user,
      )..add(GameStarted(categoryId)),
      child: MultiBlocListener(
        listeners: <BlocListener<GameBloc, GameState>>[
          BlocListener<GameBloc, GameState>(
            listenWhen: (GameState previous, GameState current) =>
                previous.updatedUser != current.updatedUser &&
                current.updatedUser != null,
            listener: (BuildContext context, GameState state) {
              dev.log(
                'BlocListener: syncUserProgress fired — '
                'xp=${state.updatedUser!.totalXp}, '
                'gamesPlayed=${state.updatedUser!.gamesPlayed}, '
                'wordsLearned=${state.updatedUser!.wordsLearned}',
                name: 'LEARNIFY.GamePage',
              );
              context.read<SessionCubit>().syncUserProgress(state.updatedUser!);
            },
          ),
          BlocListener<GameBloc, GameState>(
            listenWhen: (GameState previous, GameState current) =>
                previous.phase != current.phase &&
                current.phase == GamePhase.completed,
            listener: (BuildContext context, GameState state) {
              final attempts = state.correctAnswers + state.wrongAnswers;
              final accuracy = attempts == 0
                  ? 0
                  : ((state.correctAnswers / attempts) * 100).round();
              dev.log(
                'BlocListener: navigating to /result — '
                'score=${state.score}, accuracy=$accuracy%, '
                'correct=${state.correctAnswers}, wrong=${state.wrongAnswers}, '
                'category=${state.category?.id ?? categoryId}',
                name: 'LEARNIFY.GamePage',
              );
              final resultUri = Uri(
                path: '/result',
                queryParameters: <String, String>{
                  'score': '${state.score}',
                  'accuracy': '$accuracy',
                  'correct': '${state.correctAnswers}',
                  'mistakes': '${state.wrongAnswers}',
                  'category': state.category?.id ?? categoryId,
                },
              );
              context.go(resultUri.toString());
            },
          ),
        ],
        child: _GameView(gameType: gameType),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Main View
// ────────────────────────────────────────────────────────────────────────────────

class _GameView extends StatefulWidget {
  const _GameView({required this.gameType});

  final GameType gameType;

  @override
  State<_GameView> createState() => _GameViewState();
}

class _GameViewState extends State<_GameView> with TickerProviderStateMixin {
  late final GameAudioController _audioController;

  // Screen shake
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnim;
  int _prevLives = 3;
  String? _prevFeedback;
  GamePhase? _prevPhase;

  // Falling card
  late final AnimationController _fallController;
  int _prevIndex = -1;
  bool _cardCleared = false;

  // Correct burst
  late final AnimationController _burstController;

  // Crash flash
  late final AnimationController _crashController;

  // Rocket explosion
  late final AnimationController _explosionController;
  bool _rocketExploded = false;

  // Throttle danger audio sync (avoid calling audio APIs 60x/sec)
  double _lastDangerLevel = -1;

  @override
  void initState() {
    super.initState();

    _audioController = GameAudioController();
    unawaited(_audioController.warmUp());

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shakeAnim = TweenSequence<double>(
      <TweenSequenceItem<double>>[
        TweenSequenceItem(tween: Tween(begin: 0, end: 14), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 14, end: -12), weight: 1),
        TweenSequenceItem(tween: Tween(begin: -12, end: 8), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 8, end: -4), weight: 1),
        TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 1),
      ],
    ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

    _fallController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..addListener(_syncDangerAudio);

    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _crashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _explosionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _fallController.removeListener(_syncDangerAudio);
    _fallController.dispose();
    _burstController.dispose();
    _crashController.dispose();
    _explosionController.dispose();
    unawaited(_audioController.dispose());
    super.dispose();
  }

  void _syncDangerAudio() {
    if (!mounted) {
      return;
    }

    final state = context.read<GameBloc>().state;
    final shouldWarn =
        !_cardCleared &&
        (state.phase == GamePhase.ready || state.phase == GamePhase.listening);
    if (!shouldWarn) {
      if (_lastDangerLevel != 0) {
        _lastDangerLevel = 0;
        unawaited(_audioController.clearDanger());
      }
      return;
    }

    final dangerLevel = ((_fallController.value - 0.42) / 0.58)
        .clamp(0.0, 1.0)
        .toDouble();
    // Only update audio when danger level changes meaningfully (throttle)
    if ((dangerLevel - _lastDangerLevel).abs() > 0.03) {
      _lastDangerLevel = dangerLevel;
      unawaited(_audioController.setDangerLevel(dangerLevel));
    }
  }

  void _onStateChanged(GameState curr) {
    // New round → reset & start falling + auto-open mic
    if (curr.currentIndex != _prevIndex &&
        (curr.phase == GamePhase.ready || curr.phase == GamePhase.listening)) {
      _prevIndex = curr.currentIndex;
      _cardCleared = false;
      _rocketExploded = false;
      _burstController.reset();
      _crashController.reset();
      _explosionController.reset();
      // Speed increases per round: 8s → down to 5s
      final speedFactor = 1.0 + (curr.currentIndex * 0.06);
      _fallController.duration = Duration(
        milliseconds: (8000 / speedFactor).round(),
      );
      _fallController.forward(from: 0);
      unawaited(_audioController.startFlightLoop());
      _syncDangerAudio();
    }

    // Life lost → screen shake + rocket explosion
    if (curr.remainingLives < _prevLives) {
      _shakeController.forward(from: 0);
      _rocketExploded = true;
      _explosionController.forward(from: 0);
    }
    _prevLives = curr.remainingLives;

    // Feedback: correct
    if (_prevFeedback != curr.feedback &&
        curr.feedback != null &&
        curr.feedback!.startsWith('Boost!')) {
      _cardCleared = true;
      _fallController.stop();
      unawaited(_audioController.clearDanger());
      unawaited(_audioController.playBoost());
      _burstController.forward(from: 0);
    }

    // Feedback: wrong or timeout → rocket explodes
    if (_prevFeedback != curr.feedback &&
        curr.feedback != null &&
        (curr.feedback!.startsWith('Crash!') ||
            curr.feedback!.startsWith('Out of time.'))) {
      _cardCleared = true;
      _fallController.stop();
      unawaited(_audioController.playCrash());
      _crashController.forward(from: 0);
      _rocketExploded = true;
      _explosionController.forward(from: 0);
    }

    if (_prevPhase != GamePhase.listening &&
        curr.phase == GamePhase.listening) {
      unawaited(_audioController.playListenPing());
    }

    if (_prevPhase != curr.phase &&
        (curr.phase == GamePhase.completed || curr.phase == GamePhase.failure)) {
      unawaited(_audioController.stopAll());
    }

    _prevFeedback = curr.feedback;
    _prevPhase = curr.phase;
  }

  bool _isCorrect(String? fb) => fb != null && fb.startsWith('Boost!');
  bool _isWrong(String? fb) =>
      fb != null && (fb.startsWith('Crash!') || fb.startsWith('Out of time.'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<GameBloc, GameState>(
        listenWhen: (GameState prev, GameState curr) =>
            prev.phase != curr.phase ||
            prev.currentIndex != curr.currentIndex ||
            prev.feedback != curr.feedback ||
            prev.remainingLives != curr.remainingLives,
        listener: (BuildContext context, GameState state) {
          _onStateChanged(state);
        },
        // Avoid rebuilding the entire widget tree on transcript partial results
        buildWhen: (GameState prev, GameState curr) =>
            prev.phase != curr.phase ||
            prev.currentIndex != curr.currentIndex ||
            prev.feedback != curr.feedback ||
            prev.remainingLives != curr.remainingLives ||
            prev.score != curr.score ||
            prev.combo != curr.combo ||
            prev.correctAnswers != curr.correctAnswers ||
            prev.challenges != curr.challenges,
        builder: (BuildContext context, GameState state) {
          if (state.phase == GamePhase.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.phase == GamePhase.failure) {
            return Center(child: Text(state.errorMessage ?? 'Game failed.'));
          }
          switch (widget.gameType) {
            case GameType.rocketRush:
              return _buildGameScreen(context, state);
            case GameType.bubblePop:
              return _BubblePopScreen(
                state: state,
                shakeAnim: _shakeAnim,
                fallController: _fallController,
                burstController: _burstController,
                crashController: _crashController,
                isCorrectFn: _isCorrect,
                isWrongFn: _isWrong,
                cardCleared: _cardCleared,
              );
            case GameType.spellCast:
              return _SpellCastScreen(
                state: state,
                shakeAnim: _shakeAnim,
                fallController: _fallController,
                burstController: _burstController,
                crashController: _crashController,
                isCorrectFn: _isCorrect,
                isWrongFn: _isWrong,
                cardCleared: _cardCleared,
              );
            case GameType.speedBlitz:
              return _SpeedBlitzScreen(
                state: state,
                shakeAnim: _shakeAnim,
                fallController: _fallController,
                burstController: _burstController,
                crashController: _crashController,
                isCorrectFn: _isCorrect,
                isWrongFn: _isWrong,
                cardCleared: _cardCleared,
              );
            case GameType.meteorStorm:
              return _MeteorStormScreen(
                state: state,
                shakeAnim: _shakeAnim,
                fallController: _fallController,
                burstController: _burstController,
                crashController: _crashController,
                explosionController: _explosionController,
                cardCleared: _cardCleared,
                rocketExploded: _rocketExploded,
              );
            case GameType.crystalCave:
              return _CrystalCaveScreen(
                state: state,
                shakeAnim: _shakeAnim,
                fallController: _fallController,
                burstController: _burstController,
                crashController: _crashController,
                cardCleared: _cardCleared,
              );
            case GameType.bossBattle:
              return _BossBattleScreen(
                state: state,
                shakeAnim: _shakeAnim,
                fallController: _fallController,
                burstController: _burstController,
                crashController: _crashController,
                explosionController: _explosionController,
                cardCleared: _cardCleared,
              );
            case GameType.rhythmRush:
              return _RhythmRushScreen(
                state: state,
                shakeAnim: _shakeAnim,
                fallController: _fallController,
                burstController: _burstController,
                crashController: _crashController,
                cardCleared: _cardCleared,
              );
          }
        },
      ),
    );
  }

  Widget _buildGameScreen(BuildContext context, GameState state) {
    final challenge = state.currentChallenge;
    final isListening = state.phase == GamePhase.listening;
    final upcomingChallenges = state.challenges
        .skip(state.currentIndex + 1)
        .take(3)
        .toList();

    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(_shakeAnim.value, 0),
          child: child,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF4CC9F0),
              Color(0xFF7B6FD4),
              Color(0xFF3D2B6B),
              Color(0xFF1A1030),
            ],
            stops: <double>[0.0, 0.35, 0.7, 1.0],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              // Stars + nebula background (isolated repaint boundaries)
              const Positioned.fill(
                child: RepaintBoundary(child: _ParallaxStarField()),
              ),
              Positioned(
                top: MediaQuery.sizeOf(context).height * 0.2,
                left: -60,
                child: RepaintBoundary(
                  child: _NebulaOrb(
                    color: const Color(0xFF4CC9F0),
                    size: 200,
                    offsetPhase: 0,
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.sizeOf(context).height * 0.5,
                right: -50,
                child: RepaintBoundary(
                  child: _NebulaOrb(
                    color: const Color(0xFFA28AE5),
                    size: 160,
                    offsetPhase: 1.5,
                  ),
                ),
              ),

              // Danger zone at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: RepaintBoundary(
                  child: _DangerZone(fallProgress: _fallController),
                ),
              ),

              // Falling card
              if (challenge != null && !_cardCleared)
                Positioned.fill(
                  child: _FallingWordCard(
                    challenge: challenge,
                    fallController: _fallController,
                    isListening: isListening,
                  ),
                ),

              // Correct burst particles
              if (_burstController.isAnimating || _burstController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _CorrectBurstOverlay(controller: _burstController),
                  ),
                ),

              // Crash flash overlay
              if (_crashController.isAnimating || _crashController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _CrashFlashOverlay(controller: _crashController),
                  ),
                ),

              // Upcoming word previews (top-right)
              Positioned(
                top: 110,
                right: 20,
                child: _UpcomingWordsColumn(challenges: upcomingChallenges),
              ),

              // Back / quit button
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 28),
                  onPressed: () => context.pop(),
                ),
              ),

              // HUD
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: <Widget>[
                    _AnimatedTopHud(state: state),
                    const SizedBox(height: 14),
                    _AnimatedProgressPill(
                      completed: state.correctAnswers,
                      total: state.challenges.length,
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          ScaleTransition(
                            scale: a,
                            child: FadeTransition(opacity: a, child: child),
                          ),
                      child: state.combo > 2
                          ? _ComboPill(combo: state.combo)
                          : const SizedBox(height: 44, key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),

              // Rocket at bottom center (hidden during explosion)
              Positioned(
                left: 0,
                right: 0,
                bottom: 120,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _explosionController,
                    builder: (BuildContext context, Widget? child) {
                      if (_rocketExploded && _explosionController.value > 0) {
                        // Rocket shrinks and fades as it explodes
                        final t = _explosionController.value;
                        final scale = (1.0 - t * 0.8).clamp(0.0, 1.0);
                        final opacity = (1.0 - t).clamp(0.0, 1.0);
                        return Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: scale,
                            child: child,
                          ),
                        );
                      }
                      return child!;
                    },
                    child: _RocketDock(
                      isDamaged: _isWrong(state.feedback),
                      isBoosted: _isCorrect(state.feedback),
                      isListening: isListening,
                    ),
                  ),
                ),
              ),

              // Rocket explosion particles
              if (_rocketExploded &&
                  (_explosionController.isAnimating ||
                      _explosionController.value > 0))
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 80,
                  height: 200,
                  child: RepaintBoundary(
                    child: _RocketExplosionOverlay(
                      controller: _explosionController,
                    ),
                  ),
                ),

              // Mic button
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _MicDock(
                  isListening: isListening,
                  enabled: state.canListen,
                  onPressed: state.canListen
                      ? () =>
                            context.read<GameBloc>().add(const ListenPressed())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Falling word card
// ────────────────────────────────────────────────────────────────────────────────

class _FallingWordCard extends StatelessWidget {
  const _FallingWordCard({
    required this.challenge,
    required this.fallController,
    required this.isListening,
  });

  final WordChallenge challenge;
  final AnimationController fallController;

  final bool isListening;

  @override
  Widget build(BuildContext context) {
    // Use MediaQuery.sizeOf instead of LayoutBuilder to avoid per-frame layout
    final screenSize = MediaQuery.sizeOf(context);
    return AnimatedBuilder(
      animation: fallController,
      builder: (BuildContext context, Widget? child) {
        final t = fallController.value;
        // Card falls from top (y=0.08) to danger zone (y=0.65)
        final topFraction = 0.08 + t * 0.57;
        final top = screenSize.height * topFraction;

        // Gentle horizontal sway
        final sway = math.sin(t * math.pi * 4) * 20 * (1 - t * 0.5);
        final centerX = (screenSize.width / 2) - 70 + sway;

        // Slight rotation
        final rotation = math.sin(t * math.pi * 3) * 0.04;

        // Urgency: card glows red as it approaches bottom
        final urgency = (t - 0.5).clamp(0.0, 0.5) * 2;

        // Scale pulse when near bottom
        final pulse = 1.0 + math.sin(t * math.pi * 8) * urgency * 0.04;

        return Stack(
          children: <Widget>[
            // Trail particles as CustomPaint (avoids per-frame widget churn)
            if (t > 0.05)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _TrailPainter(
                      t: t,
                      screenWidth: screenSize.width,
                      screenHeight: screenSize.height,
                    ),
                  ),
                ),
              ),

            Positioned(
              left: centerX,
              top: top,
              child: Transform.rotate(
                angle: rotation,
                child: Transform.scale(
                  scale: pulse,
                  child: _WordCardBody(
                    challenge: challenge,
                    urgency: urgency,
                    isListening: isListening,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrailPainter extends CustomPainter {
  const _TrailPainter({
    required this.t,
    required this.screenWidth,
    required this.screenHeight,
  });

  final double t, screenWidth, screenHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (int i = 0; i < 6; i++) {
      final age = (i + 1) * 0.04;
      final trailT = (t - age).clamp(0.0, 1.0);
      final trailY = screenHeight * (0.08 + trailT * 0.57);
      final trailSway =
          math.sin(trailT * math.pi * 4) * 20 * (1 - trailT * 0.5);
      final trailX = (screenWidth / 2) + trailSway;
      final opacity = (0.3 - i * 0.05).clamp(0.0, 0.3);

      paint.color = const Color(0xFF4CC9F0).withValues(alpha: opacity);
      canvas.drawCircle(Offset(trailX, trailY), 4, paint);
      // Glow
      paint.color = const Color(0xFF4CC9F0).withValues(alpha: opacity * 0.5);
      canvas.drawCircle(Offset(trailX, trailY), 10, paint);
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => (old.t - t).abs() > 0.008;
}

class _WordCardBody extends StatelessWidget {
  const _WordCardBody({
    required this.challenge,
    required this.urgency,
    required this.isListening,
  });

  final WordChallenge challenge;
  final double urgency;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    final borderColor = urgency > 0.3
        ? Color.lerp(Colors.transparent, const Color(0xFFEF476F), urgency)!
        : (isListening ? const Color(0xFF4CC9F0) : Colors.transparent);

    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 3),
        boxShadow: <BoxShadow>[
          const BoxShadow(
            color: Color(0x30000000),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
          if (urgency > 0.3)
            BoxShadow(
              color: const Color(0xFFEF476F).withValues(alpha: urgency * 0.4),
              blurRadius: 24,
              spreadRadius: 4,
            ),
          if (isListening)
            BoxShadow(
              color: const Color(0xFF4CC9F0).withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 4,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(challenge.emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 10),
          Text(
            challenge.answer,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF2D2D2D),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Danger zone (pulsing red gradient at bottom)
// ────────────────────────────────────────────────────────────────────────────────

class _DangerZone extends StatefulWidget {
  const _DangerZone({required this.fallProgress});

  final AnimationController fallProgress;

  @override
  State<_DangerZone> createState() => _DangerZoneState();
}

class _DangerZoneState extends State<_DangerZone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _pulseController,
        widget.fallProgress,
      ]),
      builder: (BuildContext context, Widget? child) {
        // Danger intensifies as card falls
        final fallT = widget.fallProgress.value;
        final intensity = (fallT - 0.4).clamp(0.0, 0.6) / 0.6;
        final pulse = _pulseController.value * 0.3;
        final opacity = (intensity * 0.4 + pulse * intensity).clamp(0.0, 0.6);

        return Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Colors.transparent,
                const Color(0xFFEF476F).withValues(alpha: opacity * 0.3),
                const Color(0xFFEF476F).withValues(alpha: opacity),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Correct burst — sparkles explode upward
// ────────────────────────────────────────────────────────────────────────────────

class _CorrectBurstOverlay extends StatefulWidget {
  const _CorrectBurstOverlay({required this.controller});

  final AnimationController controller;

  @override
  State<_CorrectBurstOverlay> createState() => _CorrectBurstOverlayState();
}

class _CorrectBurstOverlayState extends State<_CorrectBurstOverlay> {
  late final List<_BurstParticle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _particles = List.generate(
      14,
      (_) => _BurstParticle(
        angle: rng.nextDouble() * math.pi * 2,
        speed: 80 + rng.nextDouble() * 200,
        size: 4 + rng.nextDouble() * 6,
        color: <Color>[
          const Color(0xFF80ED99),
          const Color(0xFF4CC9F0),
          const Color(0xFFFFD166),
          Colors.white,
        ][rng.nextInt(4)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _BurstPainter(
            particles: _particles,
            progress: widget.controller.value,
          ),
        );
      },
    );
  }
}

class _BurstParticle {
  _BurstParticle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });
  final double angle, speed, size;
  final Color color;
}

class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.particles, required this.progress});
  final List<_BurstParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.5;

    for (final p in particles) {
      final t = Curves.easeOut.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final dx = cx + math.cos(p.angle) * p.speed * t;
      final dy = cy + math.sin(p.angle) * p.speed * t - (t * 60); // drift up
      final r = p.size * (1 - progress * 0.6);

      canvas.drawCircle(
        Offset(dx, dy),
        r,
        Paint()..color = p.color.withValues(alpha: opacity * 0.9),
      );
      // Glow
      canvas.drawCircle(
        Offset(dx, dy),
        r * 2.5,
        Paint()..color = p.color.withValues(alpha: opacity * 0.15),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}

// ────────────────────────────────────────────────────────────────────────────────
// Crash flash — red vignette + debris
// ────────────────────────────────────────────────────────────────────────────────

class _CrashFlashOverlay extends StatelessWidget {
  const _CrashFlashOverlay({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final opacity = (1 - controller.value).clamp(0.0, 1.0) * 0.35;
        return IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: <Color>[
                  Colors.transparent,
                  const Color(0xFFEF476F).withValues(alpha: opacity),
                ],
                radius: 1.2,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Rocket explosion — fiery debris bursting outward from rocket position
// ────────────────────────────────────────────────────────────────────────────────

class _RocketExplosionOverlay extends StatefulWidget {
  const _RocketExplosionOverlay({required this.controller});
  final AnimationController controller;

  @override
  State<_RocketExplosionOverlay> createState() =>
      _RocketExplosionOverlayState();
}

class _RocketExplosionOverlayState extends State<_RocketExplosionOverlay> {
  late final List<_ExplosionDebris> _debris;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _debris = List.generate(
      18,
      (_) => _ExplosionDebris(
        angle: rng.nextDouble() * math.pi * 2,
        speed: 40 + rng.nextDouble() * 260,
        size: 3 + rng.nextDouble() * 8,
        rotationSpeed: (rng.nextDouble() - 0.5) * 6,
        color: <Color>[
          const Color(0xFFEF476F),
          const Color(0xFFF78C6B),
          const Color(0xFFFFD166),
          Colors.white,
          const Color(0xFF4CC9F0),
          const Color(0xFFA28AE5),
        ][rng.nextInt(6)],
        isFlame: rng.nextDouble() > 0.5,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _ExplosionPainter(
            debris: _debris,
            progress: widget.controller.value,
          ),
        );
      },
    );
  }
}

class _ExplosionDebris {
  _ExplosionDebris({
    required this.angle,
    required this.speed,
    required this.size,
    required this.rotationSpeed,
    required this.color,
    required this.isFlame,
  });
  final double angle, speed, size, rotationSpeed;
  final Color color;
  final bool isFlame;
}

class _ExplosionPainter extends CustomPainter {
  _ExplosionPainter({required this.debris, required this.progress});
  final List<_ExplosionDebris> debris;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.5;

    // Central flash — bright white/orange that fades fast
    if (progress < 0.3) {
      final flashOpacity = (1 - progress / 0.3).clamp(0.0, 1.0);
      final flashRadius = 30 + progress * 120;
      canvas.drawCircle(
        Offset(cx, cy),
        flashRadius,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            flashRadius,
            <Color>[
              Colors.white.withValues(alpha: flashOpacity * 0.9),
              const Color(0xFFFFD166).withValues(alpha: flashOpacity * 0.6),
              const Color(0xFFEF476F).withValues(alpha: flashOpacity * 0.3),
              Colors.transparent,
            ],
            <double>[0, 0.3, 0.6, 1.0],
          ),
      );
    }

    // Debris particles
    for (final d in debris) {
      final t = Curves.easeOutCubic.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final gravity = t * t * 80; // debris falls with gravity
      final dx = cx + math.cos(d.angle) * d.speed * t;
      final dy = cy + math.sin(d.angle) * d.speed * t + gravity;
      final r = d.size * (1 - progress * 0.5);

      if (d.isFlame) {
        // Flame-like debris with elongated shape
        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(d.rotationSpeed * t * math.pi);
        final rect = Rect.fromCenter(
          center: Offset.zero,
          width: r * 2,
          height: r * 3.5,
        );
        canvas.drawOval(
          rect,
          Paint()..color = d.color.withValues(alpha: opacity * 0.8),
        );
        // Glow
        canvas.drawOval(
          rect.inflate(r),
          Paint()..color = d.color.withValues(alpha: opacity * 0.15),
        );
        canvas.restore();
      } else {
        // Metal debris chunks
        canvas.save();
        canvas.translate(dx, dy);
        canvas.rotate(d.rotationSpeed * t * math.pi);
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: r * 1.5, height: r),
          Paint()..color = d.color.withValues(alpha: opacity * 0.9),
        );
        canvas.restore();

        // Spark glow
        canvas.drawCircle(
          Offset(dx, dy),
          r * 2,
          Paint()..color = d.color.withValues(alpha: opacity * 0.12),
        );
      }
    }

    // Smoke rings
    if (progress > 0.1 && progress < 0.8) {
      final smokeT = ((progress - 0.1) / 0.7).clamp(0.0, 1.0);
      final smokeOpacity = (1 - smokeT) * 0.2;
      for (int i = 0; i < 3; i++) {
        final ringRadius = 20 + smokeT * (80 + i * 30.0);
        canvas.drawCircle(
          Offset(cx + i * 8.0, cy - i * 10.0),
          ringRadius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6 - smokeT * 4
            ..color = Colors.white.withValues(alpha: smokeOpacity),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ExplosionPainter old) =>
      (old.progress - progress).abs() > 0.008;
}

// ────────────────────────────────────────────────────────────────────────────────
// Upcoming words preview column
// ────────────────────────────────────────────────────────────────────────────────

class _UpcomingWordsColumn extends StatelessWidget {
  const _UpcomingWordsColumn({required this.challenges});

  final List<WordChallenge> challenges;

  @override
  Widget build(BuildContext context) {
    if (challenges.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: challenges.asMap().entries.map((entry) {
        final i = entry.key;
        final c = entry.value;
        final opacity = 0.6 - (i * 0.15);
        final scale = 0.8 - (i * 0.08);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerRight,
            child: Opacity(
              opacity: opacity.clamp(0.15, 0.6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(c.emoji, style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 6),
                    Text(
                      c.answer,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Top HUD (animated hearts, score counter, shimmer badges)
// ────────────────────────────────────────────────────────────────────────────────

class _AnimatedTopHud extends StatelessWidget {
  const _AnimatedTopHud({required this.state});
  final GameState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: List<Widget>.generate(3, (int i) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _AnimatedHeart(
                isActive: i < state.remainingLives,
                index: i,
              ),
            );
          }),
        ),
        const Spacer(),
        Column(
          children: <Widget>[
            Text(
              'Score',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 2),
            _AnimatedScoreCounter(score: state.score),
          ],
        ),
        const Spacer(),
        const Row(
          children: <Widget>[
            _ShimmerPowerBadge(icon: Icons.security_rounded),
            SizedBox(width: 8),
            _ShimmerPowerBadge(icon: Icons.bolt_rounded),
          ],
        ),
      ],
    );
  }
}

class _AnimatedHeart extends StatefulWidget {
  const _AnimatedHeart({required this.isActive, required this.index});
  final bool isActive;
  final int index;

  @override
  State<_AnimatedHeart> createState() => _AnimatedHeartState();
}

class _AnimatedHeartState extends State<_AnimatedHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _wasActive = true;

  @override
  void initState() {
    super.initState();
    _wasActive = widget.isActive;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.5), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 0), weight: 2),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_AnimatedHeart old) {
    super.didUpdateWidget(old);
    if (_wasActive && !widget.isActive) _ctrl.forward(from: 0);
    _wasActive = widget.isActive;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (BuildContext context, Widget? child) {
        return Transform.scale(
          scale: widget.isActive ? 1 : _scale.value,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: widget.isActive ? 1 : (_ctrl.isAnimating ? 1 : 0.25),
            child: Icon(
              widget.isActive
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: const Color(0xFFEF476F),
              size: 28,
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedScoreCounter extends StatefulWidget {
  const _AnimatedScoreCounter({required this.score});
  final int score;

  @override
  State<_AnimatedScoreCounter> createState() => _AnimatedScoreCounterState();
}

class _AnimatedScoreCounterState extends State<_AnimatedScoreCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _bounce;
  int _prev = 0;

  @override
  void initState() {
    super.initState();
    _prev = widget.score;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bounce = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 1, end: 1.35), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.9), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_AnimatedScoreCounter old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      _prev = old.score;
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounce,
      builder: (BuildContext context, Widget? child) {
        final t = _ctrl.value;
        final display = (_prev + (widget.score - _prev) * t).round();
        return Transform.scale(
          scale: _bounce.value,
          child: Text(
            '$display',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }
}

class _ShimmerPowerBadge extends StatefulWidget {
  const _ShimmerPowerBadge({required this.icon});
  final IconData icon;

  @override
  State<_ShimmerPowerBadge> createState() => _ShimmerPowerBadgeState();
}

class _ShimmerPowerBadgeState extends State<_ShimmerPowerBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        final sx = (_ctrl.value * 3) - 1;
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ShaderMask(
            shaderCallback: (Rect b) => ui.Gradient.linear(
              Offset(b.width * sx, 0),
              Offset(b.width * (sx + 0.5), b.height),
              <Color>[Colors.white, Colors.white54, Colors.white],
              <double>[0, 0.5, 1],
            ),
            child: Icon(widget.icon, color: Colors.white, size: 24),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Progress pill with animated fill
// ────────────────────────────────────────────────────────────────────────────────

class _AnimatedProgressPill extends StatelessWidget {
  const _AnimatedProgressPill({required this.completed, required this.total});
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final frac = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    return Center(
      child: Container(
        width: 260,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: <Widget>[
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              widthFactor: frac == 0 ? 0.001 : frac,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[Color(0xFF80ED99), Color(0xFF4CC9F0)],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Center(
              child: Text(
                '$completed / $total words',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Combo pill with fire glow
// ────────────────────────────────────────────────────────────────────────────────

class _ComboPill extends StatefulWidget {
  const _ComboPill({required this.combo});
  final int combo;

  @override
  State<_ComboPill> createState() => _ComboPillState();
}

class _ComboPillState extends State<_ComboPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        final glow = 0.3 + (_ctrl.value * 0.4);
        return Container(
          key: ValueKey<int>(widget.combo),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                const Color(0xFFFFD166).withValues(alpha: 0.6),
                const Color(0xFFF78C6B).withValues(alpha: 0.6),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFF78C6B).withValues(alpha: glow),
                blurRadius: 24,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Text(
            'Combo x${widget.combo}  \u{1F525}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Rocket dock
// ────────────────────────────────────────────────────────────────────────────────

class _RocketDock extends StatefulWidget {
  const _RocketDock({
    required this.isDamaged,
    required this.isBoosted,
    this.isListening = false,
  });
  final bool isDamaged, isBoosted, isListening;

  @override
  State<_RocketDock> createState() => _RocketDockState();
}

class _RocketDockState extends State<_RocketDock>
    with TickerProviderStateMixin {
  late final AnimationController _idle;
  late final AnimationController _boost;
  late final Animation<double> _boostAnim;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _boost = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _boostAnim = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 0, end: -35), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -35, end: 0), weight: 2),
    ]).animate(CurvedAnimation(parent: _boost, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_RocketDock old) {
    super.didUpdateWidget(old);
    if (widget.isBoosted && !old.isBoosted) _boost.forward(from: 0);
    if (widget.isDamaged && !old.isDamaged) _boost.forward(from: 0);
  }

  @override
  void dispose() {
    _idle.dispose();
    _boost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_idle, _boost]),
      builder: (BuildContext context, Widget? child) {
        final bounce = math.sin(_idle.value * math.pi * 2) * 6;
        final flame = 0.95 + math.sin(_idle.value * math.pi * 8) * 0.1;
        final rot = widget.isDamaged ? -0.12 : 0.0;
        final by = widget.isBoosted
            ? _boostAnim.value
            : widget.isDamaged
            ? -_boostAnim.value * 0.4
            : 0.0;
        final gp = 0.3 + math.sin(_idle.value * math.pi * 4) * 0.15;

        return Transform.translate(
          offset: Offset(0, bounce + by),
          child: Transform.rotate(
            angle: rot,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: <Widget>[
                if (widget.isListening)
                  Container(
                    width: 120,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFFEF476F).withValues(alpha: gp),
                          blurRadius: 48,
                          spreadRadius: 18,
                        ),
                      ],
                    ),
                  ),
                if (widget.isBoosted)
                  Container(
                    width: 100,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(
                            0xFF80ED99,
                          ).withValues(alpha: (1 - _boost.value) * 0.5),
                          blurRadius: 40,
                          spreadRadius: 12,
                        ),
                      ],
                    ),
                  ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Transform.scale(
                      scaleY: flame * (widget.isBoosted ? 1.5 : 1),
                      child: const _RocketFlame(),
                    ),
                    const SizedBox(height: 2),
                    CustomPaint(
                      size: const Size(64, 100),
                      painter: _RocketPainter(
                        finColor: widget.isBoosted
                            ? const Color(0xFFFFD166)
                            : const Color(0xFFEF476F),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RocketFlame extends StatelessWidget {
  const _RocketFlame();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 50,
      height: 50,
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          Container(
            width: 26,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  Color(0xFFFFD166),
                  Color(0xFFF78C6B),
                  Colors.transparent,
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Container(
            width: 16,
            height: 30,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  Color(0xFFF78C6B),
                  Color(0xFFEF476F),
                  Colors.transparent,
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Container(
            width: 8,
            height: 20,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  Colors.white,
                  Color(0xFFFFD166),
                  Colors.transparent,
                ],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

class _RocketPainter extends CustomPainter {
  const _RocketPainter({required this.finColor});
  final Color finColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final s = size.width / 86; // scale factor from original 86-wide

    canvas.drawPath(
      Path()
        ..moveTo(cx, 0)
        ..lineTo(cx - 15 * s, 22 * s)
        ..lineTo(cx + 15 * s, 22 * s)
        ..close(),
      Paint()..color = finColor,
    );

    final body = RRect.fromLTRBR(
      cx - 15 * s,
      20 * s,
      cx + 15 * s,
      62 * s,
      Radius.circular(14 * s),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFF4CC9F0), Color(0xFFA28AE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(body.outerRect),
    );

    canvas.drawCircle(Offset(cx, 35 * s), 7 * s, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, 35 * s),
      7 * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x332D2D2D),
    );
    canvas.drawCircle(
      Offset(cx, 50 * s),
      3.5 * s,
      Paint()..color = Colors.white38,
    );

    for (final dir in <double>[-1, 1]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + 15 * s * dir, 54 * s)
          ..lineTo(cx + 25 * s * dir, 68 * s)
          ..lineTo(cx + 15 * s * dir, 68 * s)
          ..close(),
        Paint()..color = finColor,
      );
    }

    final nozzle = RRect.fromLTRBR(
      cx - 13 * s,
      62 * s,
      cx + 13 * s,
      70 * s,
      Radius.circular(2 * s),
    );
    canvas.drawRRect(
      nozzle,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFF6B6B6B), Color(0xFF2D2D2D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(nozzle.outerRect),
    );
  }

  @override
  bool shouldRepaint(_RocketPainter old) => old.finColor != finColor;
}

// ────────────────────────────────────────────────────────────────────────────────
// Mic dock with pulse rings
// ────────────────────────────────────────────────────────────────────────────────

class _MicDock extends StatelessWidget {
  const _MicDock({
    required this.isListening,
    required this.enabled,
    required this.onPressed,
  });
  final bool isListening, enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Stack(
          alignment: Alignment.center,
          children: <Widget>[
            if (isListening) const _PulseRings(),
            GestureDetector(
              onTap: enabled ? onPressed : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: isListening
                      ? const Color(0xFFEF476F)
                      : enabled
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: isListening
                          ? const Color(0x66EF476F)
                          : const Color(0x33000000),
                      blurRadius: isListening ? 32 : 24,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 42,
                  color: isListening ? Colors.white : const Color(0xFF4CC9F0),
                ),
              ),
            ),
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: isListening
              ? const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: _ListeningBars(),
                )
              : const SizedBox(height: 28),
        ),
      ],
    );
  }
}

class _PulseRings extends StatefulWidget {
  const _PulseRings();
  @override
  State<_PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<_PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: List<Widget>.generate(3, (int i) {
              final phase = ((_ctrl.value + i * 0.33) % 1.0);
              final scale = 1.0 + phase * 0.8;
              final opacity = (1 - phase).clamp(0.0, 0.4);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFEF476F).withValues(alpha: opacity),
                      width: 3,
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _ListeningBars extends StatefulWidget {
  const _ListeningBars();
  @override
  State<_ListeningBars> createState() => _ListeningBarsState();
}

class _ListeningBarsState extends State<_ListeningBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CustomPaint(
              size: const Size(40, 38),
              painter: _BarsPainter(t: _ctrl.value),
            ),
            const SizedBox(height: 8),
            child!,
          ],
        );
      },
      child: const Text(
        'Listening...',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final cx = size.width / 2;
    for (int i = 0; i < 5; i++) {
      final h = 18 + ((math.sin((t * math.pi * 2) + i * 0.5) + 1) * 10);
      final x = cx + (i - 2) * 8.0 - 2;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, 4, h),
        const Radius.circular(2),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => (old.t - t).abs() > 0.01;
}

// ────────────────────────────────────────────────────────────────────────────────
// Parallax starfield with shooting stars
// ────────────────────────────────────────────────────────────────────────────────

class _ParallaxStarField extends StatefulWidget {
  const _ParallaxStarField();
  @override
  State<_ParallaxStarField> createState() => _ParallaxStarFieldState();
}

class _ParallaxStarFieldState extends State<_ParallaxStarField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final math.Random _rng = math.Random(42);
  late final List<_Star> _far, _near;
  late final List<_Shooting> _shooting;

  @override
  void initState() {
    super.initState();
    _far = List.generate(
      18,
      (_) => _Star(
        _rng.nextDouble(),
        _rng.nextDouble(),
        1 + _rng.nextDouble() * 1.5,
        _rng.nextDouble() * math.pi * 2,
      ),
    );
    _near = List.generate(
      12,
      (_) => _Star(
        _rng.nextDouble(),
        _rng.nextDouble(),
        2.5 + _rng.nextDouble() * 2,
        _rng.nextDouble() * math.pi * 2,
      ),
    );
    _shooting = List.generate(
      3,
      (i) => _Shooting(
        0.2 + _rng.nextDouble() * 0.6,
        0.05 + _rng.nextDouble() * 0.25,
        0.5 + _rng.nextDouble() * 0.5,
        i * 0.33,
        0.08 + _rng.nextDouble() * 0.04,
      ),
    );
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _StarPainter(_far, _near, _shooting, _ctrl.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _Star {
  _Star(this.x, this.y, this.size, this.phase);
  final double x, y, size, phase;
}

class _Shooting {
  _Shooting(this.sx, this.sy, this.angle, this.trigger, this.speed);
  final double sx, sy, angle, trigger, speed;
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.far, this.near, this.shooting, this.t);
  final List<_Star> far, near;
  final List<_Shooting> shooting;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in far) {
      final p = (math.sin(t * math.pi * 2 + s.phase) + 1) / 2;
      final dy = (s.y + t * 0.02) % 1.0;
      canvas.drawCircle(
        Offset(s.x * size.width, dy * size.height),
        s.size * (0.8 + p * 0.3),
        Paint()..color = Colors.white.withValues(alpha: 0.15 + p * 0.35),
      );
    }
    for (final s in near) {
      final p = (math.sin(t * math.pi * 2 * 1.4 + s.phase) + 1) / 2;
      final dy = (s.y + t * 0.05) % 1.0;
      canvas.drawCircle(
        Offset(s.x * size.width, dy * size.height),
        s.size * (0.9 + p * 0.4),
        Paint()..color = Colors.white.withValues(alpha: 0.3 + p * 0.5),
      );
    }
    for (final ss in shooting) {
      final lt = ((t - ss.trigger) % 1.0);
      if (lt > ss.speed * 3) continue;
      final prog = lt / (ss.speed * 3);
      final op = (1 - prog).clamp(0.0, 1.0) * 0.8;
      final len = 60.0 * (1 - prog);
      final x = ss.sx * size.width + prog * ss.angle * 200;
      final y = ss.sy * size.height + prog * 120;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - len * ss.angle, y - len * 0.5),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, y),
            Offset(x - len * ss.angle, y - len * 0.5),
            <Color>[Colors.white.withValues(alpha: op), Colors.transparent],
          )
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => (old.t - t).abs() > 0.008;
}

// ────────────────────────────────────────────────────────────────────────────────
// Nebula orb
// ────────────────────────────────────────────────────────────────────────────────

class _NebulaOrb extends StatefulWidget {
  const _NebulaOrb({
    required this.color,
    required this.size,
    required this.offsetPhase,
  });
  final Color color;
  final double size, offsetPhase;

  @override
  State<_NebulaOrb> createState() => _NebulaOrbState();
}

class _NebulaOrbState extends State<_NebulaOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        final d = math.sin(_ctrl.value * math.pi * 2 + widget.offsetPhase) * 20;
        return Transform.translate(
          offset: Offset(d, d * 0.5),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: <Color>[
                  widget.color.withValues(alpha: 0.12),
                  widget.color.withValues(alpha: 0.04),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// BUBBLE POP GAME VIEW  🫧
// Words float UP in bubbles — underwater theme
// ════════════════════════════════════════════════════════════════════════════════

class _BubblePopScreen extends StatelessWidget {
  const _BubblePopScreen({
    required this.state,
    required this.shakeAnim,
    required this.fallController,
    required this.burstController,
    required this.crashController,
    required this.isCorrectFn,
    required this.isWrongFn,
    required this.cardCleared,
  });

  final GameState state;
  final Animation<double> shakeAnim;
  final AnimationController fallController;
  final AnimationController burstController;
  final AnimationController crashController;
  final bool Function(String?) isCorrectFn;
  final bool Function(String?) isWrongFn;
  final bool cardCleared;

  @override
  Widget build(BuildContext context) {
    final challenge = state.currentChallenge;
    final isListening = state.phase == GamePhase.listening;
    final screenSize = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: shakeAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(shakeAnim.value, 0),
          child: child,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF0A1628),
              Color(0xFF0D2847),
              Color(0xFF1A5276),
              Color(0xFF2E86AB),
              Color(0xFF48BFE3),
            ],
            stops: <double>[0.0, 0.25, 0.5, 0.75, 1.0],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              // Underwater particles (seaweed, light rays)
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: fallController,
                    builder: (BuildContext context, Widget? child) {
                      return CustomPaint(
                        painter: _UnderwaterBgPainter(t: fallController.value),
                      );
                    },
                  ),
                ),
              ),

              // Ambient bubbles background
              Positioned.fill(
                child: RepaintBoundary(
                  child: _AmbientBubbles(),
                ),
              ),

              // Rising bubble with word
              if (challenge != null && !cardCleared)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: fallController,
                    builder: (BuildContext context, Widget? child) {
                      // Bubble rises from bottom to top (inverted fall)
                      final t = fallController.value;
                      final bottomFrac = 0.75 - t * 0.65;
                      final top = screenSize.height * bottomFrac;
                      final wobble = math.sin(t * math.pi * 6) * 25;
                      final centerX = (screenSize.width / 2) - 65 + wobble;
                      final scale = 1.0 + math.sin(t * math.pi * 4) * 0.05;
                      final urgency = (t - 0.5).clamp(0.0, 0.5) * 2;

                      return Stack(
                        children: <Widget>[
                          Positioned(
                            left: centerX,
                            top: top,
                            child: Transform.scale(
                              scale: scale,
                              child: _BubbleWordCard(
                                challenge: challenge,
                                urgency: urgency,
                                isListening: isListening,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

              // Pop burst
              if (burstController.isAnimating || burstController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: burstController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          painter: _BubblePopBurstPainter(
                            progress: burstController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Crash overlay
              if (crashController.isAnimating || crashController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _CrashFlashOverlay(controller: crashController),
                  ),
                ),

              // Back button
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: () => context.pop(),
                ),
              ),

              // HUD
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: <Widget>[
                    _AnimatedTopHud(state: state),
                    const SizedBox(height: 14),
                    _AnimatedProgressPill(
                      completed: state.correctAnswers,
                      total: state.challenges.length,
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          ScaleTransition(
                            scale: a,
                            child: FadeTransition(opacity: a, child: child),
                          ),
                      child: state.combo > 2
                          ? _ComboPill(combo: state.combo)
                          : const SizedBox(height: 44, key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),

              // Mic button
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _MicDock(
                  isListening: isListening,
                  enabled: state.canListen,
                  onPressed: state.canListen
                      ? () => context.read<GameBloc>().add(const ListenPressed())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleWordCard extends StatelessWidget {
  const _BubbleWordCard({
    required this.challenge,
    required this.urgency,
    required this.isListening,
  });

  final WordChallenge challenge;
  final double urgency;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    final borderColor = urgency > 0.3
        ? Color.lerp(Colors.transparent, const Color(0xFFEF476F), urgency)!
        : (isListening ? const Color(0xFF48BFE3) : Colors.transparent);

    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.15),
        border: Border.all(
          color: borderColor.withValues(alpha: 0.6),
          width: 3,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF48BFE3).withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 8,
          ),
          if (isListening)
            BoxShadow(
              color: const Color(0xFF48BFE3).withValues(alpha: 0.4),
              blurRadius: 40,
              spreadRadius: 12,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(challenge.emoji, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 8),
          Text(
            challenge.answer,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmbientBubbles extends StatefulWidget {
  @override
  State<_AmbientBubbles> createState() => _AmbientBubblesState();
}

class _AmbientBubblesState extends State<_AmbientBubbles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _AmbientBubblePainter(t: _ctrl.value),
        );
      },
    );
  }
}

class _AmbientBubblePainter extends CustomPainter {
  const _AmbientBubblePainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(99);
    final paint = Paint()..style = PaintingStyle.stroke;

    for (int i = 0; i < 15; i++) {
      final baseX = rng.nextDouble() * size.width;
      final speed = 0.2 + rng.nextDouble() * 0.5;
      final radius = 3 + rng.nextDouble() * 12;
      final phase = rng.nextDouble();

      final y = size.height - ((t * speed + phase) % 1.0) * size.height * 1.3;
      final x = baseX + math.sin(t * math.pi * 2 + i) * 15;
      final opacity = (0.08 + rng.nextDouble() * 0.12);

      paint
        ..color = Colors.white.withValues(alpha: opacity)
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(x, y), radius, paint);

      // Inner highlight
      canvas.drawArc(
        Rect.fromCircle(center: Offset(x - radius * 0.2, y - radius * 0.2), radius: radius * 0.6),
        -math.pi * 0.8,
        math.pi * 0.6,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: opacity * 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientBubblePainter old) => (old.t - t).abs() > 0.008;
}

class _UnderwaterBgPainter extends CustomPainter {
  const _UnderwaterBgPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Light rays from surface
    for (int i = 0; i < 5; i++) {
      final x = size.width * (0.15 + i * 0.18);
      final sway = math.sin(t * math.pi * 2 + i * 1.2) * 20;
      final opacity = 0.03 + math.sin(t * math.pi * 4 + i) * 0.015;

      canvas.drawPath(
        Path()
          ..moveTo(x - 20 + sway, 0)
          ..lineTo(x + 20 + sway, 0)
          ..lineTo(x + 60 + sway * 0.5, size.height)
          ..lineTo(x - 60 + sway * 0.5, size.height)
          ..close(),
        Paint()..color = const Color(0xFF48BFE3).withValues(alpha: opacity.clamp(0.01, 0.06)),
      );
    }
  }

  @override
  bool shouldRepaint(_UnderwaterBgPainter old) => (old.t - t).abs() > 0.02;
}

class _BubblePopBurstPainter extends CustomPainter {
  const _BubblePopBurstPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.4;
    final rng = math.Random(77);

    // Ring expanding outward
    final ringRadius = 20 + progress * 120;
    final ringOpacity = (1 - progress).clamp(0.0, 1.0) * 0.4;
    canvas.drawCircle(
      Offset(cx, cy),
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * (1 - progress)
        ..color = const Color(0xFF48BFE3).withValues(alpha: ringOpacity),
    );

    // Small bubble fragments
    for (int i = 0; i < 12; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 60 + rng.nextDouble() * 180;
      final t = Curves.easeOut.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final r = 3 + rng.nextDouble() * 5;
      final dx = cx + math.cos(angle) * speed * t;
      final dy = cy + math.sin(angle) * speed * t - t * 40;

      canvas.drawCircle(
        Offset(dx, dy),
        r * (1 - progress * 0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = Colors.white.withValues(alpha: opacity * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_BubblePopBurstPainter old) => old.progress != progress;
}

// ════════════════════════════════════════════════════════════════════════════════
// SPELL CAST GAME VIEW  ✨
// Magical enchanted theme with orbiting runes
// ════════════════════════════════════════════════════════════════════════════════

class _SpellCastScreen extends StatelessWidget {
  const _SpellCastScreen({
    required this.state,
    required this.shakeAnim,
    required this.fallController,
    required this.burstController,
    required this.crashController,
    required this.isCorrectFn,
    required this.isWrongFn,
    required this.cardCleared,
  });

  final GameState state;
  final Animation<double> shakeAnim;
  final AnimationController fallController;
  final AnimationController burstController;
  final AnimationController crashController;
  final bool Function(String?) isCorrectFn;
  final bool Function(String?) isWrongFn;
  final bool cardCleared;

  @override
  Widget build(BuildContext context) {
    final challenge = state.currentChallenge;
    final isListening = state.phase == GamePhase.listening;

    return AnimatedBuilder(
      animation: shakeAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(shakeAnim.value, 0),
          child: child,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF0D0221),
              Color(0xFF1A0A3E),
              Color(0xFF3D1E6D),
              Color(0xFF8338EC),
            ],
            stops: <double>[0.0, 0.3, 0.65, 1.0],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              // Mystical particle field
              Positioned.fill(
                child: RepaintBoundary(child: _MagicParticleField()),
              ),

              // Magic circle behind card
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 0,
                  right: 0,
                  top: MediaQuery.sizeOf(context).height * 0.28,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: fallController,
                      builder: (BuildContext context, Widget? child) {
                        return _MagicCircle(
                          t: fallController.value,
                          isListening: isListening,
                        );
                      },
                    ),
                  ),
                ),

              // Central spell card
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 0,
                  right: 0,
                  top: MediaQuery.sizeOf(context).height * 0.30,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: fallController,
                      builder: (BuildContext context, Widget? child) {
                        final t = fallController.value;
                        final urgency = (t - 0.5).clamp(0.0, 0.5) * 2;
                        final float = math.sin(t * math.pi * 3) * 8;
                        final pulse = 1.0 + math.sin(t * math.pi * 6) * urgency * 0.04;

                        return Transform.translate(
                          offset: Offset(0, float),
                          child: Transform.scale(
                            scale: pulse,
                            child: _SpellCard(
                              challenge: challenge,
                              urgency: urgency,
                              isListening: isListening,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Timer ring around card
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 0,
                  right: 0,
                  top: MediaQuery.sizeOf(context).height * 0.30 - 15,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: fallController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          size: const Size(200, 200),
                          painter: _SpellTimerRingPainter(
                            progress: 1.0 - fallController.value,
                            urgency: (fallController.value - 0.5).clamp(0.0, 0.5) * 2,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Correct burst - magic sparkles
              if (burstController.isAnimating || burstController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _CorrectBurstOverlay(controller: burstController),
                  ),
                ),

              // Crash overlay
              if (crashController.isAnimating || crashController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _CrashFlashOverlay(controller: crashController),
                  ),
                ),

              // Back button
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: () => context.pop(),
                ),
              ),

              // HUD
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: <Widget>[
                    _AnimatedTopHud(state: state),
                    const SizedBox(height: 14),
                    _AnimatedProgressPill(
                      completed: state.correctAnswers,
                      total: state.challenges.length,
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          ScaleTransition(
                            scale: a,
                            child: FadeTransition(opacity: a, child: child),
                          ),
                      child: state.combo > 2
                          ? _ComboPill(combo: state.combo)
                          : const SizedBox(height: 44, key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),

              // Spell hint text at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 130,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: isListening
                      ? Text(
                          'Speak the enchantment...',
                          key: const ValueKey('spell-hint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFFA28AE5).withValues(alpha: 0.7),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('spell-empty')),
                ),
              ),

              // Mic button
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _MicDock(
                  isListening: isListening,
                  enabled: state.canListen,
                  onPressed: state.canListen
                      ? () => context.read<GameBloc>().add(const ListenPressed())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpellCard extends StatelessWidget {
  const _SpellCard({
    required this.challenge,
    required this.urgency,
    required this.isListening,
  });

  final WordChallenge challenge;
  final double urgency;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    final glowColor = urgency > 0.3
        ? Color.lerp(const Color(0xFFA28AE5), const Color(0xFFEF476F), urgency)!
        : (isListening ? const Color(0xFFA28AE5) : const Color(0xFF8338EC));

    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A3E).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: glowColor.withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: glowColor.withValues(alpha: 0.3),
            blurRadius: 30,
            spreadRadius: 8,
          ),
          if (isListening)
            BoxShadow(
              color: const Color(0xFFA28AE5).withValues(alpha: 0.4),
              blurRadius: 50,
              spreadRadius: 15,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(challenge.emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text(
            challenge.answer,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _MagicCircle extends StatelessWidget {
  const _MagicCircle({required this.t, required this.isListening});
  final double t;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(240, 240),
      painter: _MagicCirclePainter(t: t, isListening: isListening),
    );
  }
}

class _MagicCirclePainter extends CustomPainter {
  const _MagicCirclePainter({required this.t, required this.isListening});
  final double t;
  final bool isListening;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 10;
    final rotation = t * math.pi * 2;

    // Outer ring
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFA28AE5).withValues(alpha: isListening ? 0.5 : 0.2);
    canvas.drawCircle(Offset(cx, cy), radius, outerPaint);

    // Inner ring
    canvas.drawCircle(
      Offset(cx, cy),
      radius * 0.7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF8338EC).withValues(alpha: 0.25),
    );

    // Rotating runes (small circles on the ring)
    for (int i = 0; i < 8; i++) {
      final angle = rotation + (i * math.pi / 4);
      final rx = cx + math.cos(angle) * radius;
      final ry = cy + math.sin(angle) * radius;
      final runeOpacity = 0.3 + math.sin(t * math.pi * 4 + i) * 0.2;

      canvas.drawCircle(
        Offset(rx, ry),
        4,
        Paint()..color = const Color(0xFFA28AE5).withValues(alpha: runeOpacity.clamp(0.1, 0.5)),
      );

      // Connecting lines to center
      canvas.drawLine(
        Offset(rx, ry),
        Offset(cx, cy),
        Paint()
          ..color = const Color(0xFFA28AE5).withValues(alpha: runeOpacity * 0.15)
          ..strokeWidth = 0.5,
      );
    }

    // Inner rotating triangle
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(-rotation * 0.5);
    final triPath = Path();
    for (int i = 0; i < 3; i++) {
      final angle = i * math.pi * 2 / 3 - math.pi / 2;
      final x = math.cos(angle) * radius * 0.5;
      final y = math.sin(angle) * radius * 0.5;
      if (i == 0) {
        triPath.moveTo(x, y);
      } else {
        triPath.lineTo(x, y);
      }
    }
    triPath.close();
    canvas.drawPath(
      triPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFFA28AE5).withValues(alpha: 0.2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MagicCirclePainter old) => (old.t - t).abs() > 0.008;
}

class _SpellTimerRingPainter extends CustomPainter {
  const _SpellTimerRingPainter({required this.progress, required this.urgency});
  final double progress;
  final double urgency;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 5;

    // Background ring
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    // Progress arc
    final color = urgency > 0.3
        ? Color.lerp(const Color(0xFFA28AE5), const Color(0xFFEF476F), urgency)!
        : const Color(0xFFA28AE5);

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -math.pi / 2,
      progress * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(_SpellTimerRingPainter old) =>
      old.progress != progress || old.urgency != urgency;
}

class _MagicParticleField extends StatefulWidget {
  @override
  State<_MagicParticleField> createState() => _MagicParticleFieldState();
}

class _MagicParticleFieldState extends State<_MagicParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _MagicParticlePainter(t: _ctrl.value),
        );
      },
    );
  }
}

class _MagicParticlePainter extends CustomPainter {
  const _MagicParticlePainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(55);
    final paint = Paint();

    for (int i = 0; i < 30; i++) {
      final baseX = rng.nextDouble();
      final baseY = rng.nextDouble();
      final speed = 0.2 + rng.nextDouble() * 0.4;
      final radius = 1 + rng.nextDouble() * 2.5;
      final phase = rng.nextDouble() * math.pi * 2;
      final isGold = rng.nextDouble() > 0.7;

      final x = baseX * size.width +
          math.sin(t * math.pi * 2 * speed + phase) * 40;
      final y = (baseY + t * speed * 0.08) % 1.0 * size.height;
      final twinkle = (math.sin(t * math.pi * 4 + phase) + 1) / 2;
      final opacity = 0.1 + twinkle * 0.25;

      final color = isGold ? const Color(0xFFFFD166) : const Color(0xFFA28AE5);
      paint.color = color.withValues(alpha: opacity.clamp(0.05, 0.35));
      canvas.drawCircle(Offset(x, y), radius, paint);

      // Glow
      paint.color = color.withValues(alpha: opacity * 0.2);
      canvas.drawCircle(Offset(x, y), radius * 3, paint);
    }
  }

  @override
  bool shouldRepaint(_MagicParticlePainter old) => (old.t - t).abs() > 0.008;
}

// ════════════════════════════════════════════════════════════════════════════════
// SPEED BLITZ GAME VIEW  ⚡
// Rapid-fire neon cards — minimal, focused, intense
// ════════════════════════════════════════════════════════════════════════════════

class _SpeedBlitzScreen extends StatelessWidget {
  const _SpeedBlitzScreen({
    required this.state,
    required this.shakeAnim,
    required this.fallController,
    required this.burstController,
    required this.crashController,
    required this.isCorrectFn,
    required this.isWrongFn,
    required this.cardCleared,
  });

  final GameState state;
  final Animation<double> shakeAnim;
  final AnimationController fallController;
  final AnimationController burstController;
  final AnimationController crashController;
  final bool Function(String?) isCorrectFn;
  final bool Function(String?) isWrongFn;
  final bool cardCleared;

  @override
  Widget build(BuildContext context) {
    final challenge = state.currentChallenge;
    final isListening = state.phase == GamePhase.listening;
    final screenSize = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: shakeAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(shakeAnim.value, 0),
          child: child,
        );
      },
      child: Container(
        color: const Color(0xFF0A0A0F),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              // Neon grid background
              Positioned.fill(
                child: RepaintBoundary(child: _NeonGridBg()),
              ),

              // Scanning lines
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: fallController,
                    builder: (BuildContext context, Widget? child) {
                      return CustomPaint(
                        painter: _ScanLinePainter(t: fallController.value),
                      );
                    },
                  ),
                ),
              ),

              // Central word with timer ring
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 0,
                  right: 0,
                  top: screenSize.height * 0.28,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: fallController,
                      builder: (BuildContext context, Widget? child) {
                        final t = fallController.value;
                        final urgency = (t - 0.5).clamp(0.0, 0.5) * 2;
                        final glitch = urgency > 0.5
                            ? math.sin(t * 200) * urgency * 3
                            : 0.0;

                        return Transform.translate(
                          offset: Offset(glitch, 0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              // Timer ring
                              SizedBox(
                                width: 200,
                                height: 200,
                                child: CustomPaint(
                                  painter: _BlitzTimerPainter(
                                    progress: 1.0 - t,
                                    urgency: urgency,
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text(
                                          challenge.emoji,
                                          style: const TextStyle(fontSize: 56),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          challenge.answer,
                                          style: TextStyle(
                                            color: urgency > 0.5
                                                ? Color.lerp(
                                                    const Color(0xFFFFD166),
                                                    const Color(0xFFEF476F),
                                                    urgency,
                                                  )
                                                : const Color(0xFFFFD166),
                                            fontSize: 24,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Speed indicator
                              if (isListening)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFFFD166)
                                          .withValues(alpha: 0.3),
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Icon(
                                        Icons.flash_on_rounded,
                                        color: const Color(0xFFFFD166)
                                            .withValues(alpha: 0.7),
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'SAY IT NOW',
                                        style: TextStyle(
                                          color: const Color(0xFFFFD166)
                                              .withValues(alpha: 0.7),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Correct burst
              if (burstController.isAnimating || burstController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _CorrectBurstOverlay(controller: burstController),
                  ),
                ),

              // Crash overlay
              if (crashController.isAnimating || crashController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: _CrashFlashOverlay(controller: crashController),
                  ),
                ),

              // Back button
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: () => context.pop(),
                ),
              ),

              // HUD
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: <Widget>[
                    _AnimatedTopHud(state: state),
                    const SizedBox(height: 14),
                    _AnimatedProgressPill(
                      completed: state.correctAnswers,
                      total: state.challenges.length,
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          ScaleTransition(
                            scale: a,
                            child: FadeTransition(opacity: a, child: child),
                          ),
                      child: state.combo > 2
                          ? _ComboPill(combo: state.combo)
                          : const SizedBox(height: 44, key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),

              // Upcoming queue at bottom
              if (state.challenges.length > state.currentIndex + 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 130,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: state.challenges
                          .skip(state.currentIndex + 1)
                          .take(4)
                          .toList()
                          .asMap()
                          .entries
                          .map((entry) {
                        final i = entry.key;
                        final c = entry.value;
                        final opacity = 0.5 - i * 0.1;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Opacity(
                            opacity: opacity.clamp(0.15, 0.5),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFFFD166)
                                      .withValues(alpha: 0.3),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(c.emoji,
                                    style: const TextStyle(fontSize: 22)),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

              // Mic button
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _MicDock(
                  isListening: isListening,
                  enabled: state.canListen,
                  onPressed: state.canListen
                      ? () => context.read<GameBloc>().add(const ListenPressed())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BlitzTimerPainter extends CustomPainter {
  const _BlitzTimerPainter({required this.progress, required this.urgency});
  final double progress;
  final double urgency;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 8;

    // Background ring
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    // Progress arc with gradient color
    final color = urgency > 0.3
        ? Color.lerp(const Color(0xFFFFD166), const Color(0xFFEF476F), urgency)!
        : const Color(0xFFFFD166);

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -math.pi / 2,
      progress * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    // Dot at the end of the arc
    final dotAngle = -math.pi / 2 + progress * math.pi * 2;
    final dotX = cx + math.cos(dotAngle) * radius;
    final dotY = cy + math.sin(dotAngle) * radius;
    canvas.drawCircle(
      Offset(dotX, dotY),
      5,
      Paint()..color = color,
    );
    canvas.drawCircle(
      Offset(dotX, dotY),
      12,
      Paint()..color = color.withValues(alpha: 0.2),
    );
  }

  @override
  bool shouldRepaint(_BlitzTimerPainter old) =>
      old.progress != progress || old.urgency != urgency;
}

class _NeonGridBg extends StatefulWidget {
  @override
  State<_NeonGridBg> createState() => _NeonGridBgState();
}

class _NeonGridBgState extends State<_NeonGridBg>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _NeonGridPainter(t: _ctrl.value),
        );
      },
    );
  }
}

class _NeonGridPainter extends CustomPainter {
  const _NeonGridPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 0.5
      ..color = const Color(0xFFFFD166).withValues(alpha: 0.04);

    // Horizontal lines
    const spacing = 40.0;
    final offset = (t * spacing) % spacing;
    for (double y = offset; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Corner glow accents
    final cornerPaint = Paint();
    final glowOpacity = 0.06 + math.sin(t * math.pi * 2) * 0.03;
    cornerPaint.color = const Color(0xFFFFD166).withValues(alpha: glowOpacity);

    canvas.drawCircle(Offset.zero, 150, cornerPaint);
    canvas.drawCircle(Offset(size.width, size.height), 150, cornerPaint);
  }

  @override
  bool shouldRepaint(_NeonGridPainter old) => (old.t - t).abs() > 0.015;
}

class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Horizontal scan line that moves down
    final y = t * size.height;
    final opacity = 0.06;

    canvas.drawRect(
      Rect.fromLTWH(0, y - 1, size.width, 2),
      Paint()..color = const Color(0xFFFFD166).withValues(alpha: opacity),
    );

    // Trail glow
    canvas.drawRect(
      Rect.fromLTWH(0, y - 30, size.width, 30),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, y - 30),
          Offset(0, y),
          <Color>[
            Colors.transparent,
            const Color(0xFFFFD166).withValues(alpha: opacity * 0.5),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => (old.t - t).abs() > 0.01;
}

// ════════════════════════════════════════════════════════════════════════════════
// METEOR STORM GAME VIEW  ☄️
// Fiery meteors rain from all angles — volcanic apocalyptic theme
// Multi-layered particle inferno with impact craters and heat distortion
// ════════════════════════════════════════════════════════════════════════════════

class _MeteorStormScreen extends StatelessWidget {
  const _MeteorStormScreen({
    required this.state,
    required this.shakeAnim,
    required this.fallController,
    required this.burstController,
    required this.crashController,
    required this.explosionController,
    required this.cardCleared,
    required this.rocketExploded,
  });

  final GameState state;
  final Animation<double> shakeAnim;
  final AnimationController fallController;
  final AnimationController burstController;
  final AnimationController crashController;
  final AnimationController explosionController;
  final bool cardCleared;
  final bool rocketExploded;

  @override
  Widget build(BuildContext context) {
    final challenge = state.currentChallenge;
    final isListening = state.phase == GamePhase.listening;
    final screenSize = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: shakeAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(shakeAnim.value, shakeAnim.value * 0.5),
          child: child,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF0A0000),
              Color(0xFF1A0505),
              Color(0xFF2D0A0A),
              Color(0xFF4A1010),
              Color(0xFF1A0505),
            ],
            stops: <double>[0.0, 0.2, 0.5, 0.8, 1.0],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              // Volcanic sky with ember particles
              Positioned.fill(
                child: RepaintBoundary(child: _VolcanicSkyField()),
              ),

              // Ambient meteor streaks in background
              Positioned.fill(
                child: RepaintBoundary(child: _MeteorStreaks()),
              ),

              // Heat shimmer at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: fallController,
                    builder: (BuildContext context, Widget? child) {
                      final urgency =
                          (fallController.value - 0.4).clamp(0.0, 0.6) / 0.6;
                      return Container(
                        height: 200,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              Colors.transparent,
                              const Color(0xFFFF4400)
                                  .withValues(alpha: 0.05 + urgency * 0.15),
                              const Color(0xFFFF2200)
                                  .withValues(alpha: 0.1 + urgency * 0.25),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Falling meteor word card
              if (challenge != null && !cardCleared)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: fallController,
                    builder: (BuildContext context, Widget? child) {
                      final t = fallController.value;
                      final topFrac = 0.06 + t * 0.58;
                      final top = screenSize.height * topFrac;

                      // Dramatic diagonal entry
                      final entryX = t < 0.15
                          ? screenSize.width * 0.8 -
                              (t / 0.15) *
                                  (screenSize.width * 0.8 -
                                      screenSize.width / 2 +
                                      70)
                          : screenSize.width / 2 -
                              70 +
                              math.sin(t * math.pi * 3) * 15;
                      final urgency = (t - 0.5).clamp(0.0, 0.5) * 2;

                      // Rotation like tumbling meteor
                      final rotation = t * math.pi * 0.3;

                      return Stack(
                        children: <Widget>[
                          // Fire trail
                          if (t > 0.05)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _MeteorTrailPainter(
                                  t: t,
                                  screenWidth: screenSize.width,
                                  screenHeight: screenSize.height,
                                ),
                              ),
                            ),
                          Positioned(
                            left: entryX,
                            top: top,
                            child: Transform.rotate(
                              angle: rotation,
                              child: _MeteorWordCard(
                                challenge: challenge,
                                urgency: urgency,
                                isListening: isListening,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

              // Impact explosion
              if (rocketExploded &&
                  (explosionController.isAnimating ||
                      explosionController.value > 0))
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: explosionController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          painter: _MeteorImpactPainter(
                            progress: explosionController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Correct burst — fiery vaporize
              if (burstController.isAnimating || burstController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: burstController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          painter: _MeteorVaporizePainter(
                            progress: burstController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Crash flash
              if (crashController.isAnimating || crashController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: crashController,
                      builder: (BuildContext context, Widget? child) {
                        final opacity =
                            (1 - crashController.value).clamp(0.0, 1.0) * 0.5;
                        return IgnorePointer(
                          child: Container(
                            color:
                                const Color(0xFFFF4400).withValues(alpha: opacity),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Back button
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: () => context.pop(),
                ),
              ),

              // HUD
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: <Widget>[
                    _AnimatedTopHud(state: state),
                    const SizedBox(height: 14),
                    _AnimatedProgressPill(
                      completed: state.correctAnswers,
                      total: state.challenges.length,
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          ScaleTransition(
                            scale: a,
                            child: FadeTransition(opacity: a, child: child),
                          ),
                      child: state.combo > 2
                          ? _ComboPill(combo: state.combo)
                          : const SizedBox(height: 44, key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),

              // Mic
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _MicDock(
                  isListening: isListening,
                  enabled: state.canListen,
                  onPressed: state.canListen
                      ? () =>
                            context.read<GameBloc>().add(const ListenPressed())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MeteorWordCard extends StatelessWidget {
  const _MeteorWordCard({
    required this.challenge,
    required this.urgency,
    required this.isListening,
  });
  final WordChallenge challenge;
  final double urgency;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    final glowColor =
        Color.lerp(const Color(0xFFFF8800), const Color(0xFFFF2200), urgency)!;
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: <Color>[
            const Color(0xFF2D0A0A).withValues(alpha: 0.9),
            const Color(0xFF4A1010).withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: glowColor.withValues(alpha: 0.6), width: 2),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: glowColor.withValues(alpha: 0.4 + urgency * 0.3),
            blurRadius: 30 + urgency * 20,
            spreadRadius: 5 + urgency * 10,
          ),
          if (isListening)
            BoxShadow(
              color: const Color(0xFFFFAA00).withValues(alpha: 0.3),
              blurRadius: 40,
              spreadRadius: 10,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(challenge.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text(
            challenge.answer,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFFCC80),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MeteorTrailPainter extends CustomPainter {
  const _MeteorTrailPainter({
    required this.t,
    required this.screenWidth,
    required this.screenHeight,
  });
  final double t, screenWidth, screenHeight;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 10; i++) {
      final age = (i + 1) * 0.025;
      final trailT = (t - age).clamp(0.0, 1.0);
      final trailY = screenHeight * (0.06 + trailT * 0.58);
      final trailX = trailT < 0.15
          ? screenWidth * 0.8 -
              (trailT / 0.15) * (screenWidth * 0.8 - screenWidth / 2 + 70) +
              70
          : screenWidth / 2 + math.sin(trailT * math.pi * 3) * 15;
      final opacity = (0.5 - i * 0.05).clamp(0.0, 0.5);
      final radius = 6.0 - i * 0.5;

      // Fire core
      canvas.drawCircle(
        Offset(trailX, trailY),
        radius,
        Paint()..color = const Color(0xFFFF8800).withValues(alpha: opacity),
      );
      // Outer glow
      canvas.drawCircle(
        Offset(trailX, trailY),
        radius * 3,
        Paint()..color = const Color(0xFFFF4400).withValues(alpha: opacity * 0.3),
      );
      // Ember sparks offset
      canvas.drawCircle(
        Offset(trailX + (i % 3 - 1) * 8.0, trailY + i * 2.0),
        2,
        Paint()..color = const Color(0xFFFFDD00).withValues(alpha: opacity * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_MeteorTrailPainter old) => (old.t - t).abs() > 0.008;
}

class _VolcanicSkyField extends StatefulWidget {
  @override
  State<_VolcanicSkyField> createState() => _VolcanicSkyFieldState();
}

class _VolcanicSkyFieldState extends State<_VolcanicSkyField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(painter: _VolcanicSkyPainter(t: _ctrl.value));
      },
    );
  }
}

class _VolcanicSkyPainter extends CustomPainter {
  const _VolcanicSkyPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(33);
    final paint = Paint();

    // Floating ember particles
    for (int i = 0; i < 35; i++) {
      final baseX = rng.nextDouble();
      final baseY = rng.nextDouble();
      final speed = 0.15 + rng.nextDouble() * 0.4;
      final radius = 1 + rng.nextDouble() * 3;
      final phase = rng.nextDouble() * math.pi * 2;

      final x = baseX * size.width +
          math.sin(t * math.pi * 2 * speed + phase) * 20;
      final y = (1.0 - (baseY + t * speed * 0.2) % 1.0) * size.height;
      final flicker = (math.sin(t * math.pi * 8 + phase) + 1) / 2;
      final opacity = 0.1 + flicker * 0.3;

      final color = i % 3 == 0
          ? const Color(0xFFFF4400)
          : i % 3 == 1
              ? const Color(0xFFFF8800)
              : const Color(0xFFFFCC00);

      paint.color = color.withValues(alpha: opacity.clamp(0.05, 0.4));
      canvas.drawCircle(Offset(x, y), radius, paint);

      // Glow
      paint.color = color.withValues(alpha: opacity * 0.15);
      canvas.drawCircle(Offset(x, y), radius * 4, paint);
    }
  }

  @override
  bool shouldRepaint(_VolcanicSkyPainter old) => (old.t - t).abs() > 0.008;
}

class _MeteorStreaks extends StatefulWidget {
  @override
  State<_MeteorStreaks> createState() => _MeteorStreaksState();
}

class _MeteorStreaksState extends State<_MeteorStreaks>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(painter: _MeteorStreakPainter(t: _ctrl.value));
      },
    );
  }
}

class _MeteorStreakPainter extends CustomPainter {
  const _MeteorStreakPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(88);

    for (int i = 0; i < 6; i++) {
      final trigger = rng.nextDouble();
      final speed = 0.08 + rng.nextDouble() * 0.06;
      final lt = ((t - trigger) % 1.0);
      if (lt > speed * 4) continue;

      final prog = lt / (speed * 4);
      final opacity = (1 - prog).clamp(0.0, 1.0) * 0.5;
      final startX = rng.nextDouble() * size.width;
      final startY = rng.nextDouble() * size.height * 0.3;
      final angle = 0.5 + rng.nextDouble() * 0.8;
      final len = 40 + rng.nextDouble() * 80;

      final x = startX + prog * angle * 300;
      final y = startY + prog * 400;

      canvas.drawLine(
        Offset(x, y),
        Offset(x - len * 0.3, y - len),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, y),
            Offset(x - len * 0.3, y - len),
            <Color>[
              const Color(0xFFFF8800).withValues(alpha: opacity),
              Colors.transparent,
            ],
          )
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_MeteorStreakPainter old) => (old.t - t).abs() > 0.008;
}

class _MeteorImpactPainter extends CustomPainter {
  const _MeteorImpactPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.7;
    final rng = math.Random(44);

    // Shockwave rings
    for (int i = 0; i < 3; i++) {
      final delay = i * 0.1;
      final ringProg = ((progress - delay) / 0.7).clamp(0.0, 1.0);
      final ringRadius = ringProg * (120 + i * 60.0);
      final ringOpacity = (1 - ringProg).clamp(0.0, 1.0) * 0.4;

      canvas.drawCircle(
        Offset(cx, cy),
        ringRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 - ringProg * 3
          ..color = const Color(0xFFFF4400).withValues(alpha: ringOpacity),
      );
    }

    // Central flash
    if (progress < 0.25) {
      final flashT = progress / 0.25;
      final flashR = 20 + flashT * 100;
      canvas.drawCircle(
        Offset(cx, cy),
        flashR,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            flashR,
            <Color>[
              Colors.white.withValues(alpha: (1 - flashT) * 0.8),
              const Color(0xFFFF8800).withValues(alpha: (1 - flashT) * 0.5),
              Colors.transparent,
            ],
            <double>[0, 0.4, 1],
          ),
      );
    }

    // Debris chunks
    for (int i = 0; i < 20; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 50 + rng.nextDouble() * 250;
      final t = Curves.easeOutCubic.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final gravity = t * t * 100;
      final dx = cx + math.cos(angle) * speed * t;
      final dy = cy + math.sin(angle) * speed * t * 0.6 + gravity;
      final r = 2 + rng.nextDouble() * 5;

      final color = <Color>[
        const Color(0xFFFF4400),
        const Color(0xFFFF8800),
        const Color(0xFFFFCC00),
        Colors.white,
      ][rng.nextInt(4)];

      canvas.drawCircle(
        Offset(dx, dy),
        r * (1 - progress * 0.4),
        Paint()..color = color.withValues(alpha: opacity * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_MeteorImpactPainter old) =>
      (old.progress - progress).abs() > 0.008;
}

class _MeteorVaporizePainter extends CustomPainter {
  const _MeteorVaporizePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.4;
    final rng = math.Random(66);

    // Vaporize ring
    final ringR = 30 + progress * 150;
    final ringO = (1 - progress).clamp(0.0, 1.0) * 0.5;
    canvas.drawCircle(
      Offset(cx, cy),
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF80ED99).withValues(alpha: ringO),
    );

    // Green fire particles shooting outward
    for (int i = 0; i < 16; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 80 + rng.nextDouble() * 200;
      final t = Curves.easeOut.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final dx = cx + math.cos(angle) * speed * t;
      final dy = cy + math.sin(angle) * speed * t - t * 50;
      final r = 3 + rng.nextDouble() * 6;

      final color = i % 2 == 0
          ? const Color(0xFF80ED99)
          : const Color(0xFF4CC9F0);

      canvas.drawCircle(
        Offset(dx, dy),
        r * (1 - progress * 0.5),
        Paint()..color = color.withValues(alpha: opacity * 0.7),
      );
      canvas.drawCircle(
        Offset(dx, dy),
        r * 2.5,
        Paint()..color = color.withValues(alpha: opacity * 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(_MeteorVaporizePainter old) =>
      (old.progress - progress).abs() > 0.008;
}

// ════════════════════════════════════════════════════════════════════════════════
// CRYSTAL CAVE GAME VIEW  💎
// Words trapped in crystals — prismatic refractions, gem shattering
// Luxurious cave atmosphere with stalactites and bioluminescence
// ════════════════════════════════════════════════════════════════════════════════

class _CrystalCaveScreen extends StatelessWidget {
  const _CrystalCaveScreen({
    required this.state,
    required this.shakeAnim,
    required this.fallController,
    required this.burstController,
    required this.crashController,
    required this.cardCleared,
  });

  final GameState state;
  final Animation<double> shakeAnim;
  final AnimationController fallController;
  final AnimationController burstController;
  final AnimationController crashController;
  final bool cardCleared;

  @override
  Widget build(BuildContext context) {
    final challenge = state.currentChallenge;
    final isListening = state.phase == GamePhase.listening;
    final screenSize = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: shakeAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(shakeAnim.value, 0),
          child: child,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF050510),
              Color(0xFF0A0A2E),
              Color(0xFF1A1A4E),
              Color(0xFF2A1A5E),
            ],
            stops: <double>[0.0, 0.35, 0.7, 1.0],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              // Cave bioluminescent particles
              Positioned.fill(
                child: RepaintBoundary(child: _CaveBioLumField()),
              ),

              // Stalactite silhouettes at top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(screenSize.width, 100),
                    painter: const _StalactitePainter(),
                  ),
                ),
              ),

              // Crystal with word — floats in center, slowly cracks
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 0,
                  right: 0,
                  top: screenSize.height * 0.28,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: fallController,
                      builder: (BuildContext context, Widget? child) {
                        final t = fallController.value;
                        final urgency = (t - 0.4).clamp(0.0, 0.6) / 0.6;
                        final float = math.sin(t * math.pi * 2) * 10;
                        final rotate = math.sin(t * math.pi * 1.5) * 0.03;

                        return Transform.translate(
                          offset: Offset(0, float),
                          child: Transform.rotate(
                            angle: rotate,
                            child: _CrystalWordCard(
                              challenge: challenge,
                              urgency: urgency,
                              crackProgress: t,
                              isListening: isListening,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Prismatic timer ring
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 0,
                  right: 0,
                  top: screenSize.height * 0.28 - 20,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: fallController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          size: const Size(220, 220),
                          painter: _PrismaticRingPainter(
                            progress: 1.0 - fallController.value,
                            t: fallController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Crystal shatter burst
              if (burstController.isAnimating || burstController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: burstController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          painter: _CrystalShatterPainter(
                            progress: burstController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Crash overlay — purple flash
              if (crashController.isAnimating || crashController.value > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: crashController,
                      builder: (BuildContext context, Widget? child) {
                        final opacity =
                            (1 - crashController.value).clamp(0.0, 1.0) * 0.3;
                        return Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: <Color>[
                                Colors.transparent,
                                const Color(0xFF8338EC)
                                    .withValues(alpha: opacity),
                              ],
                              radius: 1.2,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Gem counter (visual flair)
              Positioned(
                top: 110,
                right: 20,
                child: _GemCounter(count: state.correctAnswers),
              ),

              // Back button
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: () => context.pop(),
                ),
              ),

              // HUD
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: <Widget>[
                    _AnimatedTopHud(state: state),
                    const SizedBox(height: 14),
                    _AnimatedProgressPill(
                      completed: state.correctAnswers,
                      total: state.challenges.length,
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          ScaleTransition(
                            scale: a,
                            child: FadeTransition(opacity: a, child: child),
                          ),
                      child: state.combo > 2
                          ? _ComboPill(combo: state.combo)
                          : const SizedBox(height: 44, key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),

              // Mic
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _MicDock(
                  isListening: isListening,
                  enabled: state.canListen,
                  onPressed: state.canListen
                      ? () =>
                            context.read<GameBloc>().add(const ListenPressed())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrystalWordCard extends StatelessWidget {
  const _CrystalWordCard({
    required this.challenge,
    required this.urgency,
    required this.crackProgress,
    required this.isListening,
  });
  final WordChallenge challenge;
  final double urgency;
  final double crackProgress;
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    // Crystal color shifts as it cracks
    final crystalColor = Color.lerp(
      const Color(0xFF48BFE3),
      const Color(0xFFEF476F),
      urgency,
    )!;

    return CustomPaint(
      painter: _CrystalShapePainter(
        urgency: urgency,
        crackProgress: crackProgress,
        isListening: isListening,
        crystalColor: crystalColor,
      ),
      child: Container(
        width: 170,
        height: 190,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(challenge.emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 10),
            Text(
              challenge.answer,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: crystalColor,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                shadows: <Shadow>[
                  Shadow(
                    color: crystalColor.withValues(alpha: 0.5),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CrystalShapePainter extends CustomPainter {
  const _CrystalShapePainter({
    required this.urgency,
    required this.crackProgress,
    required this.isListening,
    required this.crystalColor,
  });
  final double urgency, crackProgress;
  final bool isListening;
  final Color crystalColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Crystal hexagonal shape
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 - math.pi / 6;
      final r = (i % 2 == 0 ? 78.0 : 85.0);
      final x = cx + math.cos(angle) * r;
      final y = cy + math.sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    // Fill with translucent crystal
    canvas.drawPath(
      path,
      Paint()
        ..color = crystalColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );

    // Border with glow
    canvas.drawPath(
      path,
      Paint()
        ..color = crystalColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Crack lines based on progress
    if (crackProgress > 0.3) {
      final crackIntensity = ((crackProgress - 0.3) / 0.7).clamp(0.0, 1.0);
      final crackPaint = Paint()
        ..color = crystalColor.withValues(alpha: crackIntensity * 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      // Multiple crack paths
      for (int i = 0; i < (crackIntensity * 5).ceil(); i++) {
        final startAngle = i * 1.2 + 0.5;
        final crackLen = crackIntensity * 40;
        canvas.drawLine(
          Offset(cx, cy),
          Offset(
            cx + math.cos(startAngle) * crackLen,
            cy + math.sin(startAngle) * crackLen,
          ),
          crackPaint,
        );
        // Branch
        if (crackIntensity > 0.5) {
          canvas.drawLine(
            Offset(
              cx + math.cos(startAngle) * crackLen * 0.6,
              cy + math.sin(startAngle) * crackLen * 0.6,
            ),
            Offset(
              cx + math.cos(startAngle + 0.5) * crackLen * 0.8,
              cy + math.sin(startAngle + 0.5) * crackLen * 0.8,
            ),
            crackPaint,
          );
        }
      }
    }

    // Listening glow
    if (isListening) {
      canvas.drawPath(
        path,
        Paint()
          ..color = crystalColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
  }

  @override
  bool shouldRepaint(_CrystalShapePainter old) =>
      old.urgency != urgency ||
      old.crackProgress != crackProgress ||
      old.isListening != isListening;
}

class _PrismaticRingPainter extends CustomPainter {
  const _PrismaticRingPainter({required this.progress, required this.t});
  final double progress;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 8;

    // Rainbow prismatic progress ring
    final sweepAngle = progress * math.pi * 2;
    final colors = <Color>[
      const Color(0xFF48BFE3),
      const Color(0xFF80ED99),
      const Color(0xFFFFD166),
      const Color(0xFFF78C6B),
      const Color(0xFFEF476F),
      const Color(0xFFA28AE5),
      const Color(0xFF48BFE3),
    ];

    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2 + t * math.pi,
          colors: colors,
        ).createShader(
          Rect.fromCircle(center: Offset(cx, cy), radius: radius),
        ),
    );

    // Background ring
    canvas.drawCircle(
      Offset(cx, cy),
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white.withValues(alpha: 0.05),
    );
  }

  @override
  bool shouldRepaint(_PrismaticRingPainter old) =>
      old.progress != progress || (old.t - t).abs() > 0.01;
}

class _CrystalShatterPainter extends CustomPainter {
  const _CrystalShatterPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.38;
    final rng = math.Random(99);

    // Prismatic light burst
    if (progress < 0.3) {
      final burstT = progress / 0.3;
      for (int i = 0; i < 12; i++) {
        final angle = i * math.pi / 6;
        final len = burstT * 120;
        final opacity = (1 - burstT).clamp(0.0, 1.0) * 0.6;

        canvas.drawLine(
          Offset(cx, cy),
          Offset(cx + math.cos(angle) * len, cy + math.sin(angle) * len),
          Paint()
            ..color = <Color>[
              const Color(0xFF48BFE3),
              const Color(0xFF80ED99),
              const Color(0xFFFFD166),
              const Color(0xFFA28AE5),
            ][i % 4]
                .withValues(alpha: opacity)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Crystal shard fragments
    for (int i = 0; i < 18; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 60 + rng.nextDouble() * 220;
      final t = Curves.easeOutCubic.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final dx = cx + math.cos(angle) * speed * t;
      final dy = cy + math.sin(angle) * speed * t + t * t * 60;
      final shardSize = 4 + rng.nextDouble() * 8;
      final rotation = rng.nextDouble() * math.pi * 2 + progress * 4;

      final color = <Color>[
        const Color(0xFF48BFE3),
        const Color(0xFF80ED99),
        const Color(0xFFA28AE5),
        const Color(0xFFFFD166),
        Colors.white,
      ][rng.nextInt(5)];

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rotation);

      // Diamond/shard shape
      final shardPath = Path()
        ..moveTo(0, -shardSize)
        ..lineTo(shardSize * 0.4, 0)
        ..lineTo(0, shardSize * 0.6)
        ..lineTo(-shardSize * 0.4, 0)
        ..close();
      canvas.drawPath(
        shardPath,
        Paint()..color = color.withValues(alpha: opacity * 0.7),
      );
      // Highlight edge
      canvas.drawPath(
        shardPath,
        Paint()
          ..color = Colors.white.withValues(alpha: opacity * 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CrystalShatterPainter old) =>
      (old.progress - progress).abs() > 0.008;
}

class _CaveBioLumField extends StatefulWidget {
  @override
  State<_CaveBioLumField> createState() => _CaveBioLumFieldState();
}

class _CaveBioLumFieldState extends State<_CaveBioLumField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(painter: _CaveBioLumPainter(t: _ctrl.value));
      },
    );
  }
}

class _CaveBioLumPainter extends CustomPainter {
  const _CaveBioLumPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(77);
    final paint = Paint();

    for (int i = 0; i < 20; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final phase = rng.nextDouble() * math.pi * 2;
      final radius = 2 + rng.nextDouble() * 4;
      final pulse = (math.sin(t * math.pi * 2 + phase) + 1) / 2;
      final opacity = 0.05 + pulse * 0.15;

      final color = i % 3 == 0
          ? const Color(0xFF48BFE3)
          : i % 3 == 1
              ? const Color(0xFFA28AE5)
              : const Color(0xFF80ED99);

      // Glow orb
      paint.color = color.withValues(alpha: opacity);
      canvas.drawCircle(
        Offset(
          x + math.sin(t * math.pi * 2 + phase) * 8,
          y + math.cos(t * math.pi * 2 + phase) * 6,
        ),
        radius + pulse * 3,
        paint,
      );
      // Outer glow
      paint.color = color.withValues(alpha: opacity * 0.3);
      canvas.drawCircle(
        Offset(
          x + math.sin(t * math.pi * 2 + phase) * 8,
          y + math.cos(t * math.pi * 2 + phase) * 6,
        ),
        radius * 5,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CaveBioLumPainter old) => (old.t - t).abs() > 0.008;
}

class _StalactitePainter extends CustomPainter {
  const _StalactitePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0A0A2E);
    final rng = math.Random(22);

    // Draw stalactite shapes hanging from top
    for (int i = 0; i < 12; i++) {
      final x = (i / 12) * size.width + rng.nextDouble() * 20;
      final w = 15 + rng.nextDouble() * 25;
      final h = 30 + rng.nextDouble() * 60;

      final path = Path()
        ..moveTo(x - w / 2, 0)
        ..lineTo(x + w / 2, 0)
        ..lineTo(x + w * 0.1, h)
        ..lineTo(x - w * 0.1, h * 0.8)
        ..close();

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_StalactitePainter old) => false;
}

class _GemCounter extends StatelessWidget {
  const _GemCounter({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A4E).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF48BFE3).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.diamond_rounded,
              color: Color(0xFF48BFE3), size: 18),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(
              color: Color(0xFF48BFE3),
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════════
// BOSS BATTLE GAME VIEW  🐉
// Epic RPG battle — dragon with health bar, attack animations
// Each correct word is a sword strike, wrong = dragon breathes fire
// ════════════════════════════════════════════════════════════════════════════════

class _BossBattleScreen extends StatelessWidget {
  const _BossBattleScreen({
    required this.state,
    required this.shakeAnim,
    required this.fallController,
    required this.burstController,
    required this.crashController,
    required this.explosionController,
    required this.cardCleared,
  });

  final GameState state;
  final Animation<double> shakeAnim;
  final AnimationController fallController;
  final AnimationController burstController;
  final AnimationController crashController;
  final AnimationController explosionController;
  final bool cardCleared;

  @override
  Widget build(BuildContext context) {
    final challenge = state.currentChallenge;
    final isListening = state.phase == GamePhase.listening;
    final screenSize = MediaQuery.sizeOf(context);
    final bossHpFrac = state.challenges.isEmpty
        ? 1.0
        : 1.0 -
            (state.correctAnswers / state.challenges.length).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: shakeAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(shakeAnim.value, shakeAnim.value * 0.3),
          child: child,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF0A0000),
              Color(0xFF150808),
              Color(0xFF251212),
              Color(0xFF1A0A0A),
            ],
            stops: <double>[0.0, 0.3, 0.7, 1.0],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              // Battle arena background
              Positioned.fill(
                child: RepaintBoundary(child: _BattleArenaField()),
              ),

              // Dragon boss at top
              Positioned(
                top: screenSize.height * 0.12,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedBuilder(
                    animation: fallController,
                    builder: (BuildContext context, Widget? child) {
                      final breathe = math.sin(fallController.value * math.pi * 3);
                      return Transform.translate(
                        offset: Offset(0, breathe * 5),
                        child: _DragonBoss(
                          hpFraction: bossHpFrac,
                          isAttacking: burstController.isAnimating,
                          isHurt: crashController.isAnimating,
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Boss HP bar
              Positioned(
                top: screenSize.height * 0.10,
                left: 40,
                right: 40,
                child: _BossHealthBar(hpFraction: bossHpFrac),
              ),

              // Word card as "attack prompt" in center
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 0,
                  right: 0,
                  top: screenSize.height * 0.45,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: fallController,
                      builder: (BuildContext context, Widget? child) {
                        final t = fallController.value;
                        final urgency = (t - 0.5).clamp(0.0, 0.5) * 2;
                        final pulse = 1.0 + math.sin(t * math.pi * 6) * urgency * 0.03;
                        final glow = math.sin(t * math.pi * 4) * 0.2 + 0.8;

                        return Transform.scale(
                          scale: pulse,
                          child: _BattleWordCard(
                            challenge: challenge,
                            urgency: urgency,
                            isListening: isListening,
                            glowIntensity: glow,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Timer bar below word card
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 60,
                  right: 60,
                  top: screenSize.height * 0.45 + 160,
                  child: AnimatedBuilder(
                    animation: fallController,
                    builder: (BuildContext context, Widget? child) {
                      final remaining = 1.0 - fallController.value;
                      final urgency =
                          (fallController.value - 0.5).clamp(0.0, 0.5) * 2;
                      final color = urgency > 0.3
                          ? Color.lerp(const Color(0xFFFFD166),
                              const Color(0xFFEF476F), urgency)!
                          : const Color(0xFFFFD166);

                      return Column(
                        children: <Widget>[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: remaining,
                              minHeight: 6,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.08),
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isListening ? 'SPEAK TO ATTACK!' : 'PREPARE...',
                            style: TextStyle(
                              color: color.withValues(alpha: 0.7),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

              // Sword slash effect on correct
              if (burstController.isAnimating || burstController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: burstController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          painter: _SwordSlashPainter(
                            progress: burstController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Dragon fire breath on wrong
              if (crashController.isAnimating || crashController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: crashController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          painter: _DragonFirePainter(
                            progress: crashController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Back button
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: () => context.pop(),
                ),
              ),

              // HUD — top right
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: <Widget>[
                    _AnimatedTopHud(state: state),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          ScaleTransition(
                            scale: a,
                            child: FadeTransition(opacity: a, child: child),
                          ),
                      child: state.combo > 2
                          ? _ComboPill(combo: state.combo)
                          : const SizedBox(height: 44, key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),

              // Mic
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _MicDock(
                  isListening: isListening,
                  enabled: state.canListen,
                  onPressed: state.canListen
                      ? () =>
                            context.read<GameBloc>().add(const ListenPressed())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DragonBoss extends StatelessWidget {
  const _DragonBoss({
    required this.hpFraction,
    required this.isAttacking,
    required this.isHurt,
  });
  final double hpFraction;
  final bool isAttacking, isHurt;

  @override
  Widget build(BuildContext context) {
    final eyeColor = hpFraction > 0.5
        ? const Color(0xFFFF4444)
        : const Color(0xFFFFAA00);

    return SizedBox(
      width: 160,
      height: 140,
      child: CustomPaint(
        painter: _DragonPainter(
          hpFraction: hpFraction,
          eyeColor: eyeColor,
          isHurt: isHurt,
        ),
      ),
    );
  }
}

class _DragonPainter extends CustomPainter {
  const _DragonPainter({
    required this.hpFraction,
    required this.eyeColor,
    required this.isHurt,
  });
  final double hpFraction;
  final Color eyeColor;
  final bool isHurt;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final bodyPaint = Paint()
      ..color = isHurt
          ? const Color(0xFFFF6666)
          : Color.lerp(
              const Color(0xFF4A1010),
              const Color(0xFF2D0808),
              1 - hpFraction,
            )!;

    // Body
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 15), width: 100, height: 70),
      bodyPaint,
    );

    // Head
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 25), width: 60, height: 50),
      bodyPaint,
    );

    // Horns
    for (final dir in <double>[-1, 1]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + 20 * dir, cy - 40)
          ..lineTo(cx + 30 * dir, cy - 70)
          ..lineTo(cx + 15 * dir, cy - 35)
          ..close(),
        Paint()..color = const Color(0xFF8B4513),
      );
    }

    // Wings
    for (final dir in <double>[-1, 1]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + 30 * dir, cy)
          ..lineTo(cx + 75 * dir, cy - 30)
          ..lineTo(cx + 70 * dir, cy + 10)
          ..lineTo(cx + 45 * dir, cy + 20)
          ..close(),
        Paint()..color = const Color(0xFF3A0808).withValues(alpha: 0.8),
      );
    }

    // Eyes
    for (final dir in <double>[-1, 1]) {
      canvas.drawCircle(
        Offset(cx + 12 * dir, cy - 28),
        6,
        Paint()..color = eyeColor,
      );
      canvas.drawCircle(
        Offset(cx + 12 * dir, cy - 28),
        3,
        Paint()..color = Colors.black,
      );
      // Eye glow
      canvas.drawCircle(
        Offset(cx + 12 * dir, cy - 28),
        10,
        Paint()..color = eyeColor.withValues(alpha: 0.2),
      );
    }

    // Mouth
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy - 15), width: 20, height: 12),
      0,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFF4444).withValues(alpha: 0.5),
    );

    // Damage glow when hurt
    if (isHurt) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: 140, height: 120),
        Paint()
          ..color = const Color(0xFFFF4444).withValues(alpha: 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
      );
    }
  }

  @override
  bool shouldRepaint(_DragonPainter old) =>
      old.hpFraction != hpFraction || old.isHurt != isHurt;
}

class _BossHealthBar extends StatelessWidget {
  const _BossHealthBar({required this.hpFraction});
  final double hpFraction;

  @override
  Widget build(BuildContext context) {
    final color = hpFraction > 0.5
        ? const Color(0xFFEF476F)
        : hpFraction > 0.25
            ? const Color(0xFFF78C6B)
            : const Color(0xFFFF4444);

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.shield_rounded,
                color: Color(0xFFEF476F), size: 16),
            const SizedBox(width: 6),
            Text(
              'DRAGON',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            const Spacer(),
            Text(
              '${(hpFraction * 100).round()}%',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              widthFactor: hpFraction == 0 ? 0.001 : hpFraction,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[color, color.withValues(alpha: 0.7)],
                  ),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: color.withValues(alpha: 0.5),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BattleWordCard extends StatelessWidget {
  const _BattleWordCard({
    required this.challenge,
    required this.urgency,
    required this.isListening,
    required this.glowIntensity,
  });
  final WordChallenge challenge;
  final double urgency;
  final bool isListening;
  final double glowIntensity;

  @override
  Widget build(BuildContext context) {
    final borderColor = isListening
        ? const Color(0xFFFFD166)
        : urgency > 0.3
            ? Color.lerp(
                const Color(0xFFFF8800), const Color(0xFFFF4444), urgency)!
            : const Color(0xFFFF8800).withValues(alpha: 0.5);

    return Container(
      width: 180,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF150808).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 2.5),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: borderColor.withValues(alpha: 0.3 * glowIntensity),
            blurRadius: 25,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Sword icon
          Icon(
            Icons.sports_kabaddi_rounded,
            color: borderColor.withValues(alpha: 0.4),
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(challenge.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text(
            challenge.answer,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFFCC80),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SwordSlashPainter extends CustomPainter {
  const _SwordSlashPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.3;

    // Diagonal slash line
    if (progress < 0.3) {
      final slashT = progress / 0.3;
      final slashPaint = Paint()
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;

      // Main slash
      final startX = cx - 80;
      final startY = cy - 40;
      final endX = cx + 80 * slashT;
      final endY = cy + 40 * slashT;

      slashPaint.shader = ui.Gradient.linear(
        Offset(startX, startY),
        Offset(endX, endY),
        <Color>[
          Colors.white.withValues(alpha: (1 - slashT) * 0.9),
          const Color(0xFFFFD166).withValues(alpha: (1 - slashT) * 0.7),
        ],
      );
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), slashPaint);

      // Cross slash
      canvas.drawLine(
        Offset(cx + 60, cy - 30),
        Offset(cx - 60 * slashT, cy + 30 * slashT),
        slashPaint,
      );
    }

    // Hit spark burst
    final rng = math.Random(55);
    for (int i = 0; i < 12; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 60 + rng.nextDouble() * 180;
      final t = Curves.easeOut.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final dx = cx + math.cos(angle) * speed * t;
      final dy = cy + math.sin(angle) * speed * t;
      final r = 2 + rng.nextDouble() * 4;

      final color = i % 2 == 0
          ? const Color(0xFFFFD166)
          : Colors.white;

      canvas.drawCircle(
        Offset(dx, dy),
        r * (1 - progress * 0.5),
        Paint()..color = color.withValues(alpha: opacity * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_SwordSlashPainter old) =>
      (old.progress - progress).abs() > 0.008;
}

class _DragonFirePainter extends CustomPainter {
  const _DragonFirePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final startY = size.height * 0.25;
    final endY = size.height * 0.7;

    // Fire breath cone expanding downward
    final t = Curves.easeOut.transform(progress);
    final opacity = (1 - progress).clamp(0.0, 1.0) * 0.6;
    final reachY = startY + (endY - startY) * t;
    final spreadX = 30 + t * 100;

    final firePath = Path()
      ..moveTo(cx - 10, startY)
      ..lineTo(cx + 10, startY)
      ..lineTo(cx + spreadX, reachY)
      ..lineTo(cx - spreadX, reachY)
      ..close();

    canvas.drawPath(
      firePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(cx, startY),
          Offset(cx, reachY),
          <Color>[
            const Color(0xFFFFDD00).withValues(alpha: opacity),
            const Color(0xFFFF8800).withValues(alpha: opacity * 0.8),
            const Color(0xFFFF4400).withValues(alpha: opacity * 0.5),
            Colors.transparent,
          ],
          <double>[0, 0.3, 0.7, 1],
        ),
    );

    // Fire particles within cone
    final rng = math.Random(11);
    for (int i = 0; i < 15; i++) {
      final particleT = rng.nextDouble();
      final py = startY + (reachY - startY) * particleT;
      final maxSpread = spreadX * particleT;
      final px = cx + (rng.nextDouble() - 0.5) * 2 * maxSpread;
      final r = 2 + rng.nextDouble() * 5;
      final flicker = math.sin(progress * 20 + i) * 0.3 + 0.7;

      canvas.drawCircle(
        Offset(px, py),
        r,
        Paint()
          ..color = const Color(0xFFFFDD00)
              .withValues(alpha: opacity * flicker * 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_DragonFirePainter old) =>
      (old.progress - progress).abs() > 0.008;
}

class _BattleArenaField extends StatefulWidget {
  @override
  State<_BattleArenaField> createState() => _BattleArenaFieldState();
}

class _BattleArenaFieldState extends State<_BattleArenaField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(painter: _BattleArenaPainter(t: _ctrl.value));
      },
    );
  }
}

class _BattleArenaPainter extends CustomPainter {
  const _BattleArenaPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(11);

    // Floating embers/ash
    for (int i = 0; i < 20; i++) {
      final x = rng.nextDouble() * size.width;
      final speed = 0.1 + rng.nextDouble() * 0.3;
      final phase = rng.nextDouble() * math.pi * 2;
      final y = (1.0 - (rng.nextDouble() + t * speed) % 1.0) * size.height;
      final radius = 1 + rng.nextDouble() * 2;
      final flicker = (math.sin(t * math.pi * 6 + phase) + 1) / 2;
      final opacity = 0.05 + flicker * 0.1;

      canvas.drawCircle(
        Offset(x + math.sin(t * math.pi + phase) * 10, y),
        radius,
        Paint()..color = const Color(0xFFFF4444).withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_BattleArenaPainter old) => (old.t - t).abs() > 0.01;
}

// ════════════════════════════════════════════════════════════════════════════════
// RHYTHM RUSH GAME VIEW  🎵
// Pulsing beat waves — words arrive on rhythm, audio-reactive rings
// Musical highway with neon lanes and beat-synced scoring
// ════════════════════════════════════════════════════════════════════════════════

class _RhythmRushScreen extends StatelessWidget {
  const _RhythmRushScreen({
    required this.state,
    required this.shakeAnim,
    required this.fallController,
    required this.burstController,
    required this.crashController,
    required this.cardCleared,
  });

  final GameState state;
  final Animation<double> shakeAnim;
  final AnimationController fallController;
  final AnimationController burstController;
  final AnimationController crashController;
  final bool cardCleared;

  @override
  Widget build(BuildContext context) {
    final challenge = state.currentChallenge;
    final isListening = state.phase == GamePhase.listening;
    final screenSize = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: shakeAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.translate(
          offset: Offset(shakeAnim.value, 0),
          child: child,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF0A0A1A),
              Color(0xFF0D0D2B),
              Color(0xFF15153A),
              Color(0xFF1A1A45),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              // Beat highway lanes
              Positioned.fill(
                child: RepaintBoundary(child: _RhythmHighway()),
              ),

              // Pulsing beat rings from center
              Positioned.fill(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: fallController,
                    builder: (BuildContext context, Widget? child) {
                      return CustomPaint(
                        painter: _BeatRingsPainter(t: fallController.value),
                      );
                    },
                  ),
                ),
              ),

              // Central word with beat circle
              if (challenge != null && !cardCleared)
                Positioned(
                  left: 0,
                  right: 0,
                  top: screenSize.height * 0.3,
                  child: Center(
                    child: AnimatedBuilder(
                      animation: fallController,
                      builder: (BuildContext context, Widget? child) {
                        final t = fallController.value;
                        final urgency = (t - 0.5).clamp(0.0, 0.5) * 2;
                        // Beat pulse — 120 BPM feel (2 beats/sec)
                        final beat = math.sin(t * math.pi * 16);
                        final scale = 1.0 + beat * 0.04 * (1 + urgency);

                        return Transform.scale(
                          scale: scale,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              // Beat target ring
                              SizedBox(
                                width: 200,
                                height: 200,
                                child: CustomPaint(
                                  painter: _BeatTargetPainter(
                                    progress: 1.0 - t,
                                    beatPhase: t,
                                    urgency: urgency,
                                  ),
                                  child: Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text(
                                          challenge.emoji,
                                          style: const TextStyle(fontSize: 52),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          challenge.answer,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                            shadows: <Shadow>[
                                              Shadow(
                                                color: const Color(0xFF80ED99)
                                                    .withValues(alpha: 0.5),
                                                blurRadius: 12,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Equalizer bars
                              if (isListening)
                                _RhythmEqualizer(beatPhase: t),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Note burst on correct
              if (burstController.isAnimating || burstController.value > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: burstController,
                      builder: (BuildContext context, Widget? child) {
                        return CustomPaint(
                          painter: _NoteBurstPainter(
                            progress: burstController.value,
                          ),
                        );
                      },
                    ),
                  ),
                ),

              // Miss flash
              if (crashController.isAnimating || crashController.value > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: crashController,
                      builder: (BuildContext context, Widget? child) {
                        final opacity =
                            (1 - crashController.value).clamp(0.0, 1.0) * 0.3;
                        return Container(
                          color: const Color(0xFFEF476F)
                              .withValues(alpha: opacity),
                        );
                      },
                    ),
                  ),
                ),

              // Back button
              Positioned(
                top: 4,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white70, size: 28),
                  onPressed: () => context.pop(),
                ),
              ),

              // HUD
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  children: <Widget>[
                    _AnimatedTopHud(state: state),
                    const SizedBox(height: 14),
                    _AnimatedProgressPill(
                      completed: state.correctAnswers,
                      total: state.challenges.length,
                    ),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> a) =>
                          ScaleTransition(
                            scale: a,
                            child: FadeTransition(opacity: a, child: child),
                          ),
                      child: state.combo > 2
                          ? _ComboPill(combo: state.combo)
                          : const SizedBox(height: 44, key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),

              // Beat streak indicator
              Positioned(
                bottom: 130,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: state.combo > 0
                        ? Container(
                            key: ValueKey('streak-${state.combo}'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFF80ED99)
                                    .withValues(alpha: 0.3),
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.music_note_rounded,
                                    color: Color(0xFF80ED99), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'PERFECT STREAK x${state.combo}',
                                  style: TextStyle(
                                    color: const Color(0xFF80ED99)
                                        .withValues(alpha: 0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('no-streak')),
                  ),
                ),
              ),

              // Mic
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: _MicDock(
                  isListening: isListening,
                  enabled: state.canListen,
                  onPressed: state.canListen
                      ? () =>
                            context.read<GameBloc>().add(const ListenPressed())
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BeatTargetPainter extends CustomPainter {
  const _BeatTargetPainter({
    required this.progress,
    required this.beatPhase,
    required this.urgency,
  });
  final double progress, beatPhase, urgency;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = size.width / 2 - 10;

    // Outer beat ring
    final beat = math.sin(beatPhase * math.pi * 16);
    final outerR = radius + beat * 5;
    canvas.drawCircle(
      Offset(cx, cy),
      outerR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF80ED99).withValues(alpha: 0.15 + beat.abs() * 0.1),
    );

    // Progress arc — rainbow gradient
    final sweepAngle = progress * math.pi * 2;
    final color = urgency > 0.3
        ? Color.lerp(const Color(0xFF80ED99), const Color(0xFFEF476F), urgency)!
        : const Color(0xFF80ED99);

    // Segmented arc (like beat markers)
    const segments = 16;
    final segmentAngle = math.pi * 2 / segments;
    for (int i = 0; i < segments; i++) {
      final startAngle = -math.pi / 2 + i * segmentAngle;
      if (startAngle + segmentAngle > -math.pi / 2 + sweepAngle) break;

      final segBeat = math.sin(beatPhase * math.pi * 16 + i * 0.5);
      final segR = radius + segBeat * 3;
      final segWidth = 4 + segBeat.abs() * 2;

      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: segR),
        startAngle + 0.02,
        segmentAngle - 0.04,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = segWidth
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.6 + segBeat.abs() * 0.3),
      );
    }

    // Center dot pulse
    final dotR = 4 + beat.abs() * 3;
    canvas.drawCircle(
      Offset(cx, cy - radius - 8),
      dotR,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BeatTargetPainter old) =>
      old.progress != progress || (old.beatPhase - beatPhase).abs() > 0.008;
}

class _RhythmEqualizer extends StatelessWidget {
  const _RhythmEqualizer({required this.beatPhase});
  final double beatPhase;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 30,
      child: CustomPaint(
        painter: _EqualizerPainter(beatPhase: beatPhase),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  const _EqualizerPainter({required this.beatPhase});
  final double beatPhase;

  @override
  void paint(Canvas canvas, Size size) {
    const barCount = 9;
    final barWidth = size.width / (barCount * 2);
    final cx = size.width / 2;

    for (int i = 0; i < barCount; i++) {
      final distFromCenter = (i - barCount ~/ 2).abs().toDouble();
      final h = size.height *
          (0.3 +
              0.7 *
                  ((math.sin(beatPhase * math.pi * 16 + i * 0.8) + 1) / 2) *
                  (1 - distFromCenter / barCount));
      final x = cx + (i - barCount ~/ 2) * barWidth * 2 - barWidth / 2;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barWidth, h),
        Radius.circular(barWidth / 2),
      );

      final color = Color.lerp(
        const Color(0xFF80ED99),
        const Color(0xFF4CC9F0),
        distFromCenter / barCount,
      )!;

      canvas.drawRRect(rrect, Paint()..color = color.withValues(alpha: 0.7));
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter old) =>
      (old.beatPhase - beatPhase).abs() > 0.01;
}

class _NoteBurstPainter extends CustomPainter {
  const _NoteBurstPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.4;
    final rng = math.Random(42);

    // Musical note symbols shooting outward
    for (int i = 0; i < 14; i++) {
      final angle = rng.nextDouble() * math.pi * 2;
      final speed = 80 + rng.nextDouble() * 200;
      final t = Curves.easeOut.transform(progress);
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final dx = cx + math.cos(angle) * speed * t;
      final dy = cy + math.sin(angle) * speed * t - t * 60;
      final r = 3 + rng.nextDouble() * 6;

      final color = <Color>[
        const Color(0xFF80ED99),
        const Color(0xFF4CC9F0),
        const Color(0xFFFFD166),
        const Color(0xFFA28AE5),
        Colors.white,
      ][rng.nextInt(5)];

      // Note head (circle)
      canvas.drawCircle(
        Offset(dx, dy),
        r * (1 - progress * 0.4),
        Paint()..color = color.withValues(alpha: opacity * 0.8),
      );

      // Note stem
      if (i % 3 == 0) {
        canvas.drawLine(
          Offset(dx + r * 0.8, dy),
          Offset(dx + r * 0.8, dy - r * 2.5),
          Paint()
            ..color = color.withValues(alpha: opacity * 0.6)
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round,
        );
      }

      // Glow
      canvas.drawCircle(
        Offset(dx, dy),
        r * 3,
        Paint()..color = color.withValues(alpha: opacity * 0.1),
      );
    }

    // Central ring burst
    final ringR = 30 + progress * 120;
    final ringO = (1 - progress).clamp(0.0, 1.0) * 0.4;
    canvas.drawCircle(
      Offset(cx, cy),
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFF80ED99).withValues(alpha: ringO),
    );
  }

  @override
  bool shouldRepaint(_NoteBurstPainter old) =>
      (old.progress - progress).abs() > 0.008;
}

class _BeatRingsPainter extends CustomPainter {
  const _BeatRingsPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.4;

    // Concentric beat-pulsing rings
    for (int i = 0; i < 4; i++) {
      final beat = math.sin(t * math.pi * 16 + i * math.pi / 2);
      final radius = 120.0 + i * 50 + beat * 8;
      final opacity = 0.03 + beat.abs() * 0.03;

      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF80ED99).withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_BeatRingsPainter old) => (old.t - t).abs() > 0.008;
}

class _RhythmHighway extends StatefulWidget {
  @override
  State<_RhythmHighway> createState() => _RhythmHighwayState();
}

class _RhythmHighwayState extends State<_RhythmHighway>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(painter: _RhythmHighwayPainter(t: _ctrl.value));
      },
    );
  }
}

class _RhythmHighwayPainter extends CustomPainter {
  const _RhythmHighwayPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Vertical lane lines
    final lanePaint = Paint()
      ..strokeWidth = 1
      ..color = const Color(0xFF80ED99).withValues(alpha: 0.04);

    for (int i = 0; i < 5; i++) {
      final x = size.width * (0.2 + i * 0.15);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), lanePaint);
    }

    // Moving horizontal beat markers
    const spacing = 60.0;
    final offset = (t * spacing * 4) % spacing;
    final markerPaint = Paint()
      ..color = const Color(0xFF80ED99).withValues(alpha: 0.03);

    for (double y = offset; y < size.height; y += spacing) {
      canvas.drawLine(
        Offset(size.width * 0.2, y),
        Offset(size.width * 0.8, y),
        markerPaint,
      );
    }

    // Floating note particles
    final rng = math.Random(33);
    for (int i = 0; i < 10; i++) {
      final x = rng.nextDouble() * size.width;
      final speed = 0.1 + rng.nextDouble() * 0.2;
      final y = (rng.nextDouble() + t * speed) % 1.0 * size.height;
      final phase = rng.nextDouble() * math.pi * 2;
      final pulse = (math.sin(t * math.pi * 8 + phase) + 1) / 2;
      final opacity = 0.03 + pulse * 0.05;

      canvas.drawCircle(
        Offset(x, y),
        2 + pulse * 2,
        Paint()..color = const Color(0xFF80ED99).withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_RhythmHighwayPainter old) => (old.t - t).abs() > 0.01;
}
