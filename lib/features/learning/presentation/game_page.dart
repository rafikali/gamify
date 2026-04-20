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
// Main View (with screen-shake support)
// ────────────────────────────────────────────────────────────────────────────────

class _GameView extends StatefulWidget {
  const _GameView();

  @override
  State<_GameView> createState() => _GameViewState();
}

class _GameViewState extends State<_GameView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  int _prevLives = 3;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _shakeAnimation = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 0, end: 12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 12, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 8, end: -5), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -5, end: 3), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 3, end: 0), weight: 1),
    ]).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  bool _isCorrectFeedback(String? feedback) =>
      feedback != null && feedback.startsWith('Boost!');

  bool _isWrongFeedback(String? feedback) =>
      feedback != null &&
      (feedback.startsWith('Crash!') || feedback.startsWith('Out of time.'));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<GameBloc, GameState>(
        listenWhen: (GameState prev, GameState curr) =>
            prev.remainingLives != curr.remainingLives,
        listener: (BuildContext context, GameState state) {
          if (state.remainingLives < _prevLives) {
            _shakeController.forward(from: 0);
          }
          _prevLives = state.remainingLives;
        },
        builder: (BuildContext context, GameState state) {
          if (state.phase == GamePhase.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.phase == GamePhase.failure) {
            return Center(child: Text(state.errorMessage ?? 'Game failed.'));
          }

          final currentChallenge = state.currentChallenge;
          final isWrong = _isWrongFeedback(state.feedback);
          final isCorrect = _isCorrectFeedback(state.feedback);

          return AnimatedBuilder(
            animation: _shakeAnimation,
            builder: (BuildContext context, Widget? child) {
              return Transform.translate(
                offset: Offset(_shakeAnimation.value, 0),
                child: child,
              );
            },
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Color(0xFF4CC9F0),
                    Color(0xFFA28AE5),
                    Color(0xFF2D2D2D),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: <Widget>[
                    const Positioned.fill(child: _ParallaxStarField()),
                    // Nebula glow
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.25,
                      left: -60,
                      child: _NebulaOrb(
                        color: const Color(0xFF4CC9F0),
                        size: 220,
                        offsetPhase: 0,
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).size.height * 0.55,
                      right: -40,
                      child: _NebulaOrb(
                        color: const Color(0xFFA28AE5),
                        size: 180,
                        offsetPhase: 1.5,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Column(
                        children: <Widget>[
                          _AnimatedTopHud(state: state),
                          const SizedBox(height: 14),
                          _AnimatedProgressPill(
                            completed: state.correctAnswers,
                            total: state.challenges.length,
                          ),
                          const SizedBox(height: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (Widget child, Animation<double> a) =>
                                ScaleTransition(
                                  scale: a,
                                  child: FadeTransition(opacity: a, child: child),
                                ),
                            child: state.combo > 2
                                ? _ComboPill(combo: state.combo)
                                : const SizedBox(height: 48, key: ValueKey('empty')),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Stack(
                              children: <Widget>[
                                // Sparkle burst on correct
                                if (isCorrect)
                                  const Positioned.fill(
                                    child: _SparkleOverlay(),
                                  ),
                                // Word card with entrance animation
                                if (currentChallenge != null)
                                  Positioned(
                                    left: 24,
                                    top: 40,
                                    child: _AnimatedWordCard(
                                      key: ValueKey(currentChallenge.id),
                                      challenge: currentChallenge,
                                      feedback: state.feedback,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _RocketDock(
                            isDamaged: isWrong,
                            isBoosted: isCorrect,
                            isListening: state.phase == GamePhase.listening,
                          ),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24,
                      child: _MicDock(
                        isListening: state.phase == GamePhase.listening,
                        enabled: state.canListen,
                        onPressed: state.canListen
                            ? () => context.read<GameBloc>().add(
                                  const ListenPressed(),
                                )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Top HUD with animated score counter & heart pulse
// ────────────────────────────────────────────────────────────────────────────────

class _AnimatedTopHud extends StatelessWidget {
  const _AnimatedTopHud({required this.state});

  final GameState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Animated hearts row
        Row(
          children: List<Widget>.generate(3, (int index) {
            final isActive = index < state.remainingLives;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _AnimatedHeart(isActive: isActive, index: index),
            );
          }),
        ),
        const Spacer(),
        Column(
          children: <Widget>[
            Text(
              'Score',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
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
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  bool _wasActive = true;

  @override
  void initState() {
    super.initState();
    _wasActive = widget.isActive;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 0.0), weight: 2),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_AnimatedHeart old) {
    super.didUpdateWidget(old);
    if (_wasActive && !widget.isActive) {
      _controller.forward(from: 0);
    }
    _wasActive = widget.isActive;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (BuildContext context, Widget? child) {
        return Transform.scale(
          scale: widget.isActive ? 1.0 : _scaleAnim.value,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: widget.isActive ? 1.0 : (_controller.isAnimating ? 1.0 : 0.3),
            child: Icon(
              widget.isActive ? Icons.favorite_rounded : Icons.favorite_border_rounded,
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
  late AnimationController _controller;
  late Animation<double> _bounceAnim;
  int _prevScore = 0;

  @override
  void initState() {
    super.initState();
    _prevScore = widget.score;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _bounceAnim = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.9), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(_AnimatedScoreCounter old) {
    super.didUpdateWidget(old);
    if (old.score != widget.score) {
      _prevScore = old.score;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (BuildContext context, Widget? child) {
        final t = _controller.value;
        final displayScore = (_prevScore + (widget.score - _prevScore) * t).round();
        return Transform.scale(
          scale: _bounceAnim.value,
          child: Text(
            '$displayScore',
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
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final shimmerX = (_controller.value * 3) - 1;
        return Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return ui.Gradient.linear(
                Offset(bounds.width * shimmerX, 0),
                Offset(bounds.width * (shimmerX + 0.5), bounds.height),
                <Color>[
                  Colors.white,
                  Colors.white.withValues(alpha: 0.5),
                  Colors.white,
                ],
                <double>[0.0, 0.5, 1.0],
              );
            },
            child: Icon(widget.icon, color: Colors.white, size: 24),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Animated progress pill with fill bar
// ────────────────────────────────────────────────────────────────────────────────

class _AnimatedProgressPill extends StatelessWidget {
  const _AnimatedProgressPill({
    required this.completed,
    required this.total,
  });

  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
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
              widthFactor: fraction == 0 ? 0.001 : fraction,
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
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final glow = 0.3 + (_controller.value * 0.4);
        return Container(
          key: ValueKey<int>(widget.combo),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
// Animated word card (spring entrance + shake on wrong)
// ────────────────────────────────────────────────────────────────────────────────

class _AnimatedWordCard extends StatefulWidget {
  const _AnimatedWordCard({
    super.key,
    required this.challenge,
    required this.feedback,
  });

  final WordChallenge challenge;
  final String? feedback;

  @override
  State<_AnimatedWordCard> createState() => _AnimatedWordCardState();
}

class _AnimatedWordCardState extends State<_AnimatedWordCard>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  late final AnimationController _wrongShakeController;
  late final Animation<double> _wrongShakeAnim;

  late final AnimationController _correctController;
  late final Animation<double> _correctGlowAnim;

  bool _prevFeedbackWasNull = true;

  @override
  void initState() {
    super.initState();

    // Entrance: slide from left + fade + scale up
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(-1.2, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.elasticOut,
    ));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: Curves.elasticOut,
      ),
    );
    _entranceController.forward();

    // Wrong answer shake
    _wrongShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _wrongShakeAnim = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 0, end: 16), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 16, end: -14), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -14, end: 10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10, end: -6), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _wrongShakeController,
      curve: Curves.easeOut,
    ));

    // Correct glow
    _correctController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _correctGlowAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _correctController, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(_AnimatedWordCard old) {
    super.didUpdateWidget(old);
    final fb = widget.feedback;
    if (_prevFeedbackWasNull && fb != null) {
      if (fb.startsWith('Crash!') || fb.startsWith('Out of time.')) {
        _wrongShakeController.forward(from: 0);
      } else if (fb.startsWith('Boost!')) {
        _correctController.forward(from: 0);
      }
    }
    _prevFeedbackWasNull = fb == null;
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _wrongShakeController.dispose();
    _correctController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCorrect =
        widget.feedback != null && widget.feedback!.startsWith('Boost!');
    final isWrong = widget.feedback != null &&
        (widget.feedback!.startsWith('Crash!') ||
            widget.feedback!.startsWith('Out of time.'));

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _entranceController,
        _wrongShakeController,
        _correctController,
      ]),
      builder: (BuildContext context, Widget? child) {
        return FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Transform.translate(
                offset: Offset(_wrongShakeAnim.value, 0),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: <BoxShadow>[
            const BoxShadow(
              color: Color(0x26000000),
              blurRadius: 28,
              offset: Offset(0, 16),
            ),
            if (isCorrect)
              BoxShadow(
                color: const Color(0xFF80ED99).withValues(
                  alpha: _correctGlowAnim.value * 0.6,
                ),
                blurRadius: 32,
                spreadRadius: 8,
              ),
            if (isWrong)
              const BoxShadow(
                color: Color(0x55EF476F),
                blurRadius: 24,
                spreadRadius: 4,
              ),
          ],
          border: Border.all(
            color: isCorrect
                ? const Color(0xFF80ED99)
                : isWrong
                    ? const Color(0xFFEF476F)
                    : Colors.transparent,
            width: 4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(widget.challenge.emoji,
                style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 10),
            Text(
              widget.challenge.answer,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF2D2D2D),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Sparkle burst overlay (correct answer celebration)
// ────────────────────────────────────────────────────────────────────────────────

class _SparkleOverlay extends StatefulWidget {
  const _SparkleOverlay();

  @override
  State<_SparkleOverlay> createState() => _SparkleOverlayState();
}

class _SparkleOverlayState extends State<_SparkleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Sparkle> _sparkles;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _sparkles = List.generate(
      18,
      (_) => _Sparkle(
        x: _rng.nextDouble(),
        y: _rng.nextDouble() * 0.6,
        size: 3 + _rng.nextDouble() * 5,
        speed: 0.5 + _rng.nextDouble() * 1.5,
        phase: _rng.nextDouble() * math.pi * 2,
      ),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _SparklePainter(
            sparkles: _sparkles,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _Sparkle {
  _Sparkle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
  });

  final double x, y, size, speed, phase;
}

class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.sparkles, required this.progress});

  final List<_Sparkle> sparkles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final dy = s.y * size.height - (progress * s.speed * 80);
      final dx = s.x * size.width + math.sin(s.phase + progress * 6) * 20;

      final paint = Paint()
        ..color = Color.lerp(
          const Color(0xFFFFD166),
          const Color(0xFF80ED99),
          s.phase / (math.pi * 2),
        )!
            .withValues(alpha: opacity * 0.9);

      // Draw star shape
      final path = _starPath(dx, dy, s.size * (1 - progress * 0.5), 4);
      canvas.drawPath(path, paint);
    }
  }

  Path _starPath(double cx, double cy, double r, int points) {
    final path = Path();
    for (int i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final radius = i.isEven ? r : r * 0.4;
      final x = cx + math.cos(angle) * radius;
      final y = cy + math.sin(angle) * radius;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.progress != progress;
}

// ────────────────────────────────────────────────────────────────────────────────
// Rocket dock with boost/damage vertical shift & listening glow
// ────────────────────────────────────────────────────────────────────────────────

class _RocketDock extends StatefulWidget {
  const _RocketDock({
    required this.isDamaged,
    required this.isBoosted,
    this.isListening = false,
  });

  final bool isDamaged;
  final bool isBoosted;
  final bool isListening;

  @override
  State<_RocketDock> createState() => _RocketDockState();
}

class _RocketDockState extends State<_RocketDock>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _boostController;
  late final Animation<double> _boostAnim;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _boostController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _boostAnim = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 0, end: -40), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -40, end: 0), weight: 2),
    ]).animate(CurvedAnimation(
      parent: _boostController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void didUpdateWidget(_RocketDock old) {
    super.didUpdateWidget(old);
    if (widget.isBoosted && !old.isBoosted) {
      _boostController.forward(from: 0);
    }
    if (widget.isDamaged && !old.isDamaged) {
      _boostController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _boostController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_idleController, _boostController]),
      builder: (BuildContext context, Widget? child) {
        final idleBounce = math.sin(_idleController.value * math.pi * 2) * 7;
        final flameScale =
            0.95 + (math.sin(_idleController.value * math.pi * 8) * 0.1);
        final rotation = widget.isDamaged ? -0.12 : 0.0;
        final boostY = widget.isBoosted
            ? _boostAnim.value
            : (widget.isDamaged ? -_boostAnim.value * 0.4 : 0.0);
        final glowPulse =
            0.3 + (math.sin(_idleController.value * math.pi * 4) * 0.15);

        return Transform.translate(
          offset: Offset(0, idleBounce + boostY),
          child: Transform.rotate(
            angle: rotation,
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
                          color: const Color(0xFFEF476F)
                              .withValues(alpha: glowPulse),
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
                          color: const Color(0xFF80ED99).withValues(
                            alpha: (1 - _boostController.value) * 0.5,
                          ),
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
                      scaleY: flameScale * (widget.isBoosted ? 1.5 : 1.0),
                      child: const _RocketFlame(),
                    ),
                    const SizedBox(height: 2),
                    CustomPaint(
                      size: const Size(86, 132),
                      painter: _RocketPainter(
                        bodyTop: const Color(0xFF4CC9F0),
                        bodyBottom: const Color(0xFFA28AE5),
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
      width: 70,
      height: 70,
      child: Stack(
        alignment: Alignment.topCenter,
        children: <Widget>[
          Container(
            width: 34,
            height: 52,
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
            width: 22,
            height: 42,
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
            width: 12,
            height: 28,
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
  const _RocketPainter({
    required this.bodyTop,
    required this.bodyBottom,
    required this.finColor,
  });

  final Color bodyTop;
  final Color bodyBottom;
  final Color finColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    final nosePaint = Paint()..color = finColor;
    final nosePath = Path()
      ..moveTo(centerX, 0)
      ..lineTo(centerX - 20, 30)
      ..lineTo(centerX + 20, 30)
      ..close();
    canvas.drawPath(nosePath, nosePaint);

    final bodyRect = RRect.fromLTRBR(
      centerX - 20, 28, centerX + 20, 82, const Radius.circular(18),
    );
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[Color(0xFF4CC9F0), Color(0xFFA28AE5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bodyRect.outerRect);
    canvas.drawRRect(bodyRect, bodyPaint);

    final shadowPaint = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawRRect(bodyRect.shift(const Offset(0, 4)), shadowPaint);
    canvas.drawRRect(bodyRect, bodyPaint);

    final windowPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(centerX, 46), 10, windowPaint);
    canvas.drawCircle(
      Offset(centerX, 46),
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x332D2D2D),
    );
    canvas.drawCircle(
      Offset(centerX, 66),
      5,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );

    final leftFin = Path()
      ..moveTo(centerX - 20, 72)
      ..lineTo(centerX - 34, 90)
      ..lineTo(centerX - 20, 90)
      ..close();
    final rightFin = Path()
      ..moveTo(centerX + 20, 72)
      ..lineTo(centerX + 34, 90)
      ..lineTo(centerX + 20, 90)
      ..close();
    final finPaint = Paint()..color = finColor;
    canvas.drawPath(leftFin, finPaint);
    canvas.drawPath(rightFin, finPaint);

    final nozzleRect = RRect.fromLTRBR(
      centerX - 18, 82, centerX + 18, 92, const Radius.circular(3),
    );
    canvas.drawRRect(
      nozzleRect,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFF6B6B6B), Color(0xFF2D2D2D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(nozzleRect.outerRect),
    );
  }

  @override
  bool shouldRepaint(covariant _RocketPainter oldDelegate) =>
      oldDelegate.finColor != finColor ||
      oldDelegate.bodyTop != bodyTop ||
      oldDelegate.bodyBottom != bodyBottom;
}

// ────────────────────────────────────────────────────────────────────────────────
// Mic dock with pulse ripple rings
// ────────────────────────────────────────────────────────────────────────────────

class _MicDock extends StatelessWidget {
  const _MicDock({
    required this.isListening,
    required this.enabled,
    required this.onPressed,
  });

  final bool isListening;
  final bool enabled;
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
                  padding: EdgeInsets.only(top: 14),
                  child: _ListeningBars(),
                )
              : const SizedBox(height: 30),
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
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: List<Widget>.generate(3, (int i) {
              final phase = ((_controller.value + i * 0.33) % 1.0);
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
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(5, (int index) {
                final height = 18 +
                    ((math.sin((_controller.value * math.pi * 2) +
                                    (index * 0.5)) +
                                1) *
                            10);
                return Container(
                  width: 4,
                  height: height,
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
// Multi-layer parallax starfield with shooting stars
// ────────────────────────────────────────────────────────────────────────────────

class _ParallaxStarField extends StatefulWidget {
  const _ParallaxStarField();

  @override
  State<_ParallaxStarField> createState() => _ParallaxStarFieldState();
}

class _ParallaxStarFieldState extends State<_ParallaxStarField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final math.Random _rng = math.Random(42);
  late final List<_StarData> _starsNear;
  late final List<_StarData> _starsFar;
  late final List<_ShootingStar> _shootingStars;

  @override
  void initState() {
    super.initState();
    _starsNear = List.generate(
      20,
      (_) => _StarData(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 2.5 + _rng.nextDouble() * 2,
        phase: _rng.nextDouble() * math.pi * 2,
      ),
    );
    _starsFar = List.generate(
      30,
      (_) => _StarData(
        x: _rng.nextDouble(),
        y: _rng.nextDouble(),
        size: 1.0 + _rng.nextDouble() * 1.5,
        phase: _rng.nextDouble() * math.pi * 2,
      ),
    );
    _shootingStars = List.generate(
      3,
      (i) => _ShootingStar(
        startX: 0.2 + _rng.nextDouble() * 0.6,
        startY: 0.05 + _rng.nextDouble() * 0.3,
        angle: 0.5 + _rng.nextDouble() * 0.5,
        triggerAt: i * 0.33,
        speed: 0.08 + _rng.nextDouble() * 0.04,
      ),
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _ParallaxStarPainter(
            starsNear: _starsNear,
            starsFar: _starsFar,
            shootingStars: _shootingStars,
            t: _controller.value,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _StarData {
  _StarData({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
  });
  final double x, y, size, phase;
}

class _ShootingStar {
  _ShootingStar({
    required this.startX,
    required this.startY,
    required this.angle,
    required this.triggerAt,
    required this.speed,
  });
  final double startX, startY, angle, triggerAt, speed;
}

class _ParallaxStarPainter extends CustomPainter {
  _ParallaxStarPainter({
    required this.starsNear,
    required this.starsFar,
    required this.shootingStars,
    required this.t,
  });

  final List<_StarData> starsNear;
  final List<_StarData> starsFar;
  final List<_ShootingStar> shootingStars;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    // Far stars (slower drift)
    for (final s in starsFar) {
      final pulse = (math.sin(t * math.pi * 2 + s.phase) + 1) / 2;
      final opacity = 0.15 + pulse * 0.35;
      final dy = (s.y + t * 0.02) % 1.0;
      canvas.drawCircle(
        Offset(s.x * size.width, dy * size.height),
        s.size * (0.8 + pulse * 0.3),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }

    // Near stars (faster drift, bigger)
    for (final s in starsNear) {
      final pulse = (math.sin(t * math.pi * 2 * 1.4 + s.phase) + 1) / 2;
      final opacity = 0.3 + pulse * 0.5;
      final dy = (s.y + t * 0.05) % 1.0;
      canvas.drawCircle(
        Offset(s.x * size.width, dy * size.height),
        s.size * (0.9 + pulse * 0.4),
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    }

    // Shooting stars
    for (final ss in shootingStars) {
      final localT = ((t - ss.triggerAt) % 1.0);
      if (localT > ss.speed * 3) continue; // only visible briefly
      final progress = localT / (ss.speed * 3);
      final opacity = (1 - progress).clamp(0.0, 1.0) * 0.8;
      final length = 60.0 * (1 - progress);

      final x = ss.startX * size.width + progress * ss.angle * 200;
      final y = ss.startY * size.height + progress * 120;

      final paint = Paint()
        ..shader = ui.Gradient.linear(
          Offset(x, y),
          Offset(x - length * ss.angle, y - length * 0.5),
          <Color>[
            Colors.white.withValues(alpha: opacity),
            Colors.transparent,
          ],
        )
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(x, y),
        Offset(x - length * ss.angle, y - length * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParallaxStarPainter old) => old.t != t;
}

// ────────────────────────────────────────────────────────────────────────────────
// Nebula orbs (floating ambient glow)
// ────────────────────────────────────────────────────────────────────────────────

class _NebulaOrb extends StatefulWidget {
  const _NebulaOrb({
    required this.color,
    required this.size,
    required this.offsetPhase,
  });

  final Color color;
  final double size;
  final double offsetPhase;

  @override
  State<_NebulaOrb> createState() => _NebulaOrbState();
}

class _NebulaOrbState extends State<_NebulaOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final drift = math.sin(
              _controller.value * math.pi * 2 + widget.offsetPhase,
            ) *
            20;
        return Transform.translate(
          offset: Offset(drift, drift * 0.5),
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
