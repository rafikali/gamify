import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ResultPage extends StatefulWidget {
  const ResultPage({
    super.key,
    required this.score,
    required this.accuracy,
    required this.correctAnswers,
    required this.mistakes,
    required this.categoryId,
  });

  final int score;
  final int accuracy;
  final int correctAnswers;
  final int mistakes;
  final String categoryId;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final AnimationController _confettiController;
  late final AnimationController _scoreCountController;
  late final AnimationController _shimmerController;

  late final List<_ConfettiParticle> _confetti;

  @override
  void initState() {
    super.initState();

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..forward();

    _scoreCountController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Start counting after header slides in
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _scoreCountController.forward();
    });

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    final rng = math.Random();
    _confetti = List.generate(
      40,
      (_) => _ConfettiParticle(
        x: rng.nextDouble(),
        speed: 0.3 + rng.nextDouble() * 0.7,
        size: 4 + rng.nextDouble() * 6,
        rotation: rng.nextDouble() * math.pi * 2,
        rotationSpeed: (rng.nextDouble() - 0.5) * 8,
        drift: (rng.nextDouble() - 0.5) * 80,
        color: <Color>[
          const Color(0xFFFFD166),
          const Color(0xFF80ED99),
          const Color(0xFF4CC9F0),
          const Color(0xFFEF476F),
          const Color(0xFFA28AE5),
          const Color(0xFFF78C6B),
        ][rng.nextInt(6)],
      ),
    );
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _confettiController.dispose();
    _scoreCountController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Animation<double> _staggeredFade(double start, double end) =>
      Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut),
      ));

  Animation<Offset> _staggeredSlide(double start, double end) =>
      Tween<Offset>(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOutCubic),
      ));

  @override
  Widget build(BuildContext context) {
    final coinsEarned = widget.score ~/ 2;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          // Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Color(0xFFFFD166),
                  Color(0xFF80ED99),
                  Color(0xFF4CC9F0),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          // Confetti
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _confettiController,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: _ConfettiPainter(
                    particles: _confetti,
                    progress: _confettiController.value,
                  ),
                );
              },
            ),
          ),

          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // Header
                    SlideTransition(
                      position: _staggeredSlide(0.0, 0.3),
                      child: FadeTransition(
                        opacity: _staggeredFade(0.0, 0.3),
                        child: Column(
                          children: <Widget>[
                            Text(
                              'Great Job! \u{1F389}',
                              style: Theme.of(context)
                                  .textTheme
                                  .displaySmall
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "You're making awesome progress!",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Score card
                    SlideTransition(
                      position: _staggeredSlide(0.15, 0.45),
                      child: FadeTransition(
                        opacity: _staggeredFade(0.15, 0.45),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x1A000000),
                                blurRadius: 40,
                                offset: Offset(0, 20),
                              ),
                            ],
                          ),
                          child: Column(
                            children: <Widget>[
                              // Animated score counter
                              AnimatedBuilder(
                                animation: _scoreCountController,
                                builder:
                                    (BuildContext context, Widget? child) {
                                  final curve =
                                      Curves.easeOutCubic.transform(
                                    _scoreCountController.value,
                                  );
                                  final displayScore =
                                      (widget.score * curve).round();
                                  return TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.8, end: 1.0),
                                    duration:
                                        const Duration(milliseconds: 600),
                                    curve: Curves.elasticOut,
                                    builder: (BuildContext context,
                                        double scale, Widget? child) {
                                      return Transform.scale(
                                        scale: scale,
                                        child: Text(
                                          '$displayScore',
                                          style: Theme.of(context)
                                              .textTheme
                                              .displaySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 52,
                                              ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total Score',
                                style:
                                    Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 24),

                              // Accuracy with animated ring
                              _AnimatedMetricRow(
                                delay: 0.3,
                                stagger: _staggerController,
                                child: _ResultMetricWithRing(
                                  icon: Icons.track_changes_rounded,
                                  color: const Color(0xFF4CC9F0),
                                  label: 'Accuracy',
                                  value: '${widget.accuracy}%',
                                  ringProgress: widget.accuracy / 100,
                                  stagger: _staggerController,
                                  ringDelay: 0.5,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _AnimatedMetricRow(
                                delay: 0.4,
                                stagger: _staggerController,
                                child: _ResultMetric(
                                  icon: Icons.star_rounded,
                                  color: const Color(0xFF80ED99),
                                  label: 'Words Completed',
                                  value: '${widget.correctAnswers}',
                                ),
                              ),
                              const SizedBox(height: 12),
                              _AnimatedMetricRow(
                                delay: 0.5,
                                stagger: _staggerController,
                                child: _ResultMetric(
                                  icon: Icons.close_rounded,
                                  color: const Color(0xFFEF476F),
                                  label: 'Mistakes',
                                  value: '${widget.mistakes}',
                                ),
                              ),
                              const SizedBox(height: 18),

                              // Coins with shimmer
                              _AnimatedMetricRow(
                                delay: 0.55,
                                stagger: _staggerController,
                                child: _ShimmerCoinsBar(
                                  coinsEarned: coinsEarned,
                                  shimmerController: _shimmerController,
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Badge unlock with scale reveal
                              _AnimatedMetricRow(
                                delay: 0.65,
                                stagger: _staggerController,
                                child: const _BadgeUnlocked(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Buttons
                    SlideTransition(
                      position: _staggeredSlide(0.75, 1.0),
                      child: FadeTransition(
                        opacity: _staggeredFade(0.75, 1.0),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => context.go('/home'),
                                child: const Text('Home'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => context
                                    .go('/game/${widget.categoryId}'),
                                child: const Text('Next Level'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Staggered row animation wrapper
// ────────────────────────────────────────────────────────────────────────────────

class _AnimatedMetricRow extends StatelessWidget {
  const _AnimatedMetricRow({
    required this.delay,
    required this.stagger,
    required this.child,
  });

  final double delay;
  final AnimationController stagger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final end = (delay + 0.2).clamp(0.0, 1.0);
    final fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: stagger,
        curve: Interval(delay, end, curve: Curves.easeOut),
      ),
    );
    final slide = Tween<Offset>(
      begin: const Offset(0.15, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: stagger,
        curve: Interval(delay, end, curve: Curves.easeOutCubic),
      ),
    );

    return SlideTransition(
      position: slide,
      child: FadeTransition(opacity: fade, child: child),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Result metric with animated accuracy ring
// ────────────────────────────────────────────────────────────────────────────────

class _ResultMetricWithRing extends StatelessWidget {
  const _ResultMetricWithRing({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.ringProgress,
    required this.stagger,
    required this.ringDelay,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final double ringProgress;
  final AnimationController stagger;
  final double ringDelay;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                AnimatedBuilder(
                  animation: stagger,
                  builder: (BuildContext context, Widget? child) {
                    final ringEnd = (ringDelay + 0.4).clamp(0.0, 1.0);
                    final ringAnim = Tween<double>(begin: 0, end: ringProgress)
                        .animate(CurvedAnimation(
                      parent: stagger,
                      curve: Interval(ringDelay, ringEnd,
                          curve: Curves.easeOutCubic),
                    ));
                    return CustomPaint(
                      size: const Size(44, 44),
                      painter: _RingPainter(
                        progress: ringAnim.value,
                        color: color,
                      ),
                    );
                  },
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = color.withValues(alpha: 0.15),
    );

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress;
}

// ────────────────────────────────────────────────────────────────────────────────
// Standard metric row
// ────────────────────────────────────────────────────────────────────────────────

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Coins bar with shimmer sweep
// ────────────────────────────────────────────────────────────────────────────────

class _ShimmerCoinsBar extends StatelessWidget {
  const _ShimmerCoinsBar({
    required this.coinsEarned,
    required this.shimmerController,
  });

  final int coinsEarned;
  final AnimationController shimmerController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerController,
      builder: (BuildContext context, Widget? child) {
        final shimmerX = (shimmerController.value * 3) - 1;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: <Color>[
                Color(0xFFFFD166),
                Color(0xFFF78C6B),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33F78C6B),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return ui.Gradient.linear(
                Offset(bounds.width * shimmerX, 0),
                Offset(bounds.width * (shimmerX + 0.4), bounds.height),
                <Color>[
                  Colors.white,
                  Colors.white.withValues(alpha: 0.6),
                  Colors.white,
                ],
                <double>[0.0, 0.5, 1.0],
              );
            },
            blendMode: BlendMode.srcIn,
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.monetization_on_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Coins Earned',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                Text(
                  '+$coinsEarned',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Badge unlocked with scale + glow entrance
// ────────────────────────────────────────────────────────────────────────────────

class _BadgeUnlocked extends StatefulWidget {
  const _BadgeUnlocked();

  @override
  State<_BadgeUnlocked> createState() => _BadgeUnlockedState();
}

class _BadgeUnlockedState extends State<_BadgeUnlocked>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.15), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 0.95), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _glowAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _controller.forward();
    });
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
        return Transform.scale(
          scale: _scaleAnim.value,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9F2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFF4CC9F0).withValues(alpha: 0.3),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF4CC9F0)
                      .withValues(alpha: _glowAnim.value * 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.workspace_premium_rounded,
                  color: const Color(0xFF4CC9F0),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Badge Unlocked!',
                        style: TextStyle(
                          color: const Color(0xFF4CC9F0),
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Word Master - Complete 10 words',
                        style: TextStyle(
                          color: const Color(0xFF6B6B6B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Confetti painter
// ────────────────────────────────────────────────────────────────────────────────

class _ConfettiParticle {
  _ConfettiParticle({
    required this.x,
    required this.speed,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
    required this.drift,
    required this.color,
  });

  final double x, speed, size, rotation, rotationSpeed, drift;
  final Color color;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = -20 + (progress * p.speed * size.height * 1.4);
      if (y > size.height + 20) continue;

      final x = p.x * size.width + math.sin(progress * 4 + p.rotation) * p.drift;
      final opacity = (1 - (progress * 0.6)).clamp(0.0, 1.0);
      final angle = p.rotation + progress * p.rotationSpeed;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);

      final paint = Paint()..color = p.color.withValues(alpha: opacity * 0.85);
      // Draw confetti as small rectangles with rounded corners
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          const Radius.circular(1.5),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}
