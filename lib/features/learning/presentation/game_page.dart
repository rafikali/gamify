import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/voice/speech_recognition_service.dart';
import '../../session/presentation/session_cubit.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'game_bloc.dart';

// ────────────────────────────────────────────────────────────────────────────────
// Entry
// ────────────────────────────────────────────────────────────────────────────────

class GamePage extends StatelessWidget {
  const GamePage({
    super.key,
    required this.categoryId,
    required this.speechRecognitionService,
  });

  final String categoryId;
  final SpeechRecognitionService speechRecognitionService;

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
        child: const _GameView(),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Main View
// ────────────────────────────────────────────────────────────────────────────────

class _GameView extends StatefulWidget {
  const _GameView();

  @override
  State<_GameView> createState() => _GameViewState();
}

class _GameViewState extends State<_GameView> with TickerProviderStateMixin {
  // Screen shake
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnim;
  int _prevLives = 3;
  String? _prevFeedback;

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

  @override
  void initState() {
    super.initState();

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
    );

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
    _fallController.dispose();
    _burstController.dispose();
    _crashController.dispose();
    _explosionController.dispose();
    super.dispose();
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

      // Auto-open mic when card starts falling
      if (curr.phase == GamePhase.ready && curr.speechReady) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) {
            final bloc = context.read<GameBloc>();
            if (bloc.state.canListen &&
                bloc.state.phase == GamePhase.ready) {
              bloc.add(const ListenPressed());
            }
          }
        });
      }
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
      _burstController.forward(from: 0);
    }

    // Feedback: wrong or timeout → rocket explodes
    if (_prevFeedback != curr.feedback &&
        curr.feedback != null &&
        (curr.feedback!.startsWith('Crash!') ||
            curr.feedback!.startsWith('Out of time.'))) {
      _cardCleared = true;
      _fallController.stop();
      _crashController.forward(from: 0);
      _rocketExploded = true;
      _explosionController.forward(from: 0);
    }

    _prevFeedback = curr.feedback;
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
        builder: (BuildContext context, GameState state) {
          if (state.phase == GamePhase.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.phase == GamePhase.failure) {
            return Center(child: Text(state.errorMessage ?? 'Game failed.'));
          }
          return _buildGameScreen(context, state);
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
              // Stars + nebula background
              const Positioned.fill(child: _ParallaxStarField()),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.2,
                left: -60,
                child: _NebulaOrb(
                  color: const Color(0xFF4CC9F0),
                  size: 200,
                  offsetPhase: 0,
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.5,
                right: -50,
                child: _NebulaOrb(
                  color: const Color(0xFFA28AE5),
                  size: 160,
                  offsetPhase: 1.5,
                ),
              ),

              // Danger zone at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _DangerZone(fallProgress: _fallController),
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
                  child: _CorrectBurstOverlay(controller: _burstController),
                ),

              // Crash flash overlay
              if (_crashController.isAnimating || _crashController.value > 0)
                Positioned.fill(
                  child: _CrashFlashOverlay(controller: _crashController),
                ),

              // Upcoming word previews (top-right)
              Positioned(
                top: 110,
                right: 20,
                child: _UpcomingWordsColumn(challenges: upcomingChallenges),
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
                  child: _RocketExplosionOverlay(
                    controller: _explosionController,
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
    return AnimatedBuilder(
      animation: fallController,
      builder: (BuildContext context, Widget? child) {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final t = fallController.value;
            // Card falls from top (y=0.08) to danger zone (y=0.65)
            final topFraction = 0.08 + t * 0.57;
            final top = constraints.maxHeight * topFraction;

            // Gentle horizontal sway
            final sway = math.sin(t * math.pi * 4) * 20 * (1 - t * 0.5);
            final centerX = (constraints.maxWidth / 2) - 70 + sway;

            // Slight rotation
            final rotation = math.sin(t * math.pi * 3) * 0.04;

            // Urgency: card glows red as it approaches bottom
            final urgency = (t - 0.5).clamp(0.0, 0.5) * 2;

            // Scale pulse when near bottom
            final pulse = 1.0 + math.sin(t * math.pi * 8) * urgency * 0.04;

            return Stack(
              children: <Widget>[
                // Trail particles behind card
                if (t > 0.05)
                  ..._buildTrailParticles(constraints, top, centerX + 70, t),

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
      },
    );
  }

  List<Widget> _buildTrailParticles(
    BoxConstraints constraints,
    double cardTop,
    double cardCenterX,
    double t,
  ) {
    return List<Widget>.generate(6, (int i) {
      final age = (i + 1) * 0.04;
      final trailT = (t - age).clamp(0.0, 1.0);
      final trailY = constraints.maxHeight * (0.08 + trailT * 0.57);
      final trailSway =
          math.sin(trailT * math.pi * 4) * 20 * (1 - trailT * 0.5);
      final trailX = (constraints.maxWidth / 2) + trailSway;
      final opacity = (0.3 - i * 0.05).clamp(0.0, 0.3);

      return Positioned(
        left: trailX - 4,
        top: trailY - 8,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4CC9F0).withValues(alpha: opacity),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF4CC9F0).withValues(alpha: opacity * 0.5),
                blurRadius: 12,
              ),
            ],
          ),
        ),
      );
    });
  }
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
      24,
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
      32,
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
  bool shouldRepaint(_ExplosionPainter old) => old.progress != progress;
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(5, (int i) {
                final h =
                    18 +
                    ((math.sin((_ctrl.value * math.pi * 2) + i * 0.5) + 1) *
                        10);
                return Container(
                  width: 4,
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            const Text(
              'Listening...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      },
    );
  }
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
      30,
      (_) => _Star(
        _rng.nextDouble(),
        _rng.nextDouble(),
        1 + _rng.nextDouble() * 1.5,
        _rng.nextDouble() * math.pi * 2,
      ),
    );
    _near = List.generate(
      20,
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
  bool shouldRepaint(_StarPainter old) => old.t != t;
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
