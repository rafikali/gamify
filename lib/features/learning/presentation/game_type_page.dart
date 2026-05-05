import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/learning_models.dart';

class GameTypePage extends StatefulWidget {
  const GameTypePage({super.key, required this.categoryId});

  final String categoryId;

  @override
  State<GameTypePage> createState() => _GameTypePageState();
}

class _GameTypePageState extends State<GameTypePage>
    with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final AnimationController _bgController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _bgController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          // Animated gradient background
          AnimatedBuilder(
            animation: _bgController,
            builder: (BuildContext context, Widget? child) {
              final shift = math.sin(_bgController.value * math.pi * 2) * 0.15;
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: const <Color>[
                      Color(0xFF1A1030),
                      Color(0xFF3D2B6B),
                      Color(0xFF7B6FD4),
                      Color(0xFF4CC9F0),
                    ],
                    stops: <double>[0.0, 0.35 + shift, 0.7, 1.0],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              );
            },
          ),

          // Floating particles
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (BuildContext context, Widget? child) {
                  return CustomPaint(
                    painter: _FloatingParticlesPainter(t: _bgController.value),
                  );
                },
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: <Widget>[
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => context.pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, -0.5),
                            end: Offset.zero,
                          ).animate(CurvedAnimation(
                            parent: _staggerController,
                            curve: const Interval(0.0, 0.4,
                                curve: Curves.easeOutCubic),
                          )),
                          child: FadeTransition(
                            opacity: Tween<double>(begin: 0, end: 1).animate(
                              CurvedAnimation(
                                parent: _staggerController,
                                curve: const Interval(0.0, 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Choose Your Game',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Each mode tests your skills differently',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Game type cards
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    itemCount: GameType.values.length,
                    itemBuilder: (BuildContext context, int index) {
                      final gameType = GameType.values[index];
                      final delay = 0.05 + index * 0.08;
                      final end = (delay + 0.2).clamp(0.0, 1.0);

                      return SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.3, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _staggerController,
                          curve: Interval(delay, end,
                              curve: Curves.easeOutCubic),
                        )),
                        child: FadeTransition(
                          opacity: Tween<double>(begin: 0, end: 1).animate(
                            CurvedAnimation(
                              parent: _staggerController,
                              curve: Interval(delay, end),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _GameTypeCard(
                              gameType: gameType,
                              index: index,
                              pulseController: _pulseController,
                              onTap: () {
                                context.push(
                                  '/game/${widget.categoryId}/${gameType.name}',
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Game Type Card
// ────────────────────────────────────────────────────────────────────────────────

class _GameTypeCard extends StatefulWidget {
  const _GameTypeCard({
    required this.gameType,
    required this.index,
    required this.pulseController,
    required this.onTap,
  });

  final GameType gameType;
  final int index;
  final AnimationController pulseController;
  final VoidCallback onTap;

  @override
  State<_GameTypeCard> createState() => _GameTypeCardState();
}

class _GameTypeCardState extends State<_GameTypeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;
  bool _pressed = false;

  static const List<List<Color>> _gradients = <List<Color>>[
    <Color>[Color(0xFF4CC9F0), Color(0xFF7B6FD4)], // Rocket Rush
    <Color>[Color(0xFF80ED99), Color(0xFF4CC9F0)], // Bubble Pop
    <Color>[Color(0xFFA28AE5), Color(0xFFEF476F)], // Spell Cast
    <Color>[Color(0xFFFFD166), Color(0xFFF78C6B)], // Speed Blitz
    <Color>[Color(0xFFEF476F), Color(0xFFFF6B35)], // Meteor Storm
    <Color>[Color(0xFF48BFE3), Color(0xFFA28AE5)], // Crystal Cave
    <Color>[Color(0xFFFF4444), Color(0xFFFF8800)], // Boss Battle
    <Color>[Color(0xFF80ED99), Color(0xFFFFD166)], // Rhythm Rush
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.rocket_launch_rounded,
    Icons.bubble_chart_rounded,
    Icons.auto_awesome_rounded,
    Icons.flash_on_rounded,
    Icons.local_fire_department_rounded,
    Icons.diamond_rounded,
    Icons.shield_rounded,
    Icons.music_note_rounded,
  ];

  static const List<String> _descriptions = <String>[
    'Words fall from the sky — say them before they crash into your rocket!',
    'Bubbles float up with words inside — pop them with your voice!',
    'Magical words appear — cast the spell by speaking the enchantment!',
    'Words flash at lightning speed — how fast can you say them all?',
    'Fiery meteors rain down in waves — survive the barrage with your voice!',
    'Words trapped in crystals — shatter them and collect precious gems!',
    'A fearsome dragon guards the words — defeat it with every correct answer!',
    'Pulsing beats carry the words — ride the rhythm and speak on time!',
  ];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[widget.index];
    final icon = _icons[widget.index];

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedBuilder(
          animation: widget.pulseController,
          builder: (BuildContext context, Widget? child) {
            final glowIntensity =
                0.2 + widget.pulseController.value * 0.15;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors[0].withValues(alpha: glowIntensity),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  colors[0].withValues(alpha: 0.25),
                  colors[1].withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: colors[0].withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: <Widget>[
                // Icon with animated shimmer ring
                AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (BuildContext context, Widget? child) {
                    return Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          startAngle: _shimmerController.value * math.pi * 2,
                          colors: <Color>[
                            colors[0].withValues(alpha: 0.6),
                            colors[1].withValues(alpha: 0.2),
                            colors[0].withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF1A1030).withValues(alpha: 0.8),
                        ),
                        child: Center(
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return ui.Gradient.linear(
                                Offset.zero,
                                Offset(bounds.width, bounds.height),
                                colors,
                              );
                            },
                            child: Icon(icon, color: Colors.white, size: 32),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(width: 16),

                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            widget.gameType.emoji,
                            style: const TextStyle(fontSize: 22),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.gameType.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                          if (widget.index >= 4)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    colors[0],
                                    colors[1],
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'PRO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _descriptions[widget.index],
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Play arrow
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: colors),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Background particles
// ────────────────────────────────────────────────────────────────────────────────

class _FloatingParticlesPainter extends CustomPainter {
  const _FloatingParticlesPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(42);
    final paint = Paint();

    for (int i = 0; i < 25; i++) {
      final baseX = rng.nextDouble();
      final baseY = rng.nextDouble();
      final speed = 0.3 + rng.nextDouble() * 0.7;
      final radius = 1.5 + rng.nextDouble() * 3;
      final phase = rng.nextDouble() * math.pi * 2;

      final x = baseX * size.width +
          math.sin(t * math.pi * 2 * speed + phase) * 30;
      final y = (baseY + t * speed * 0.15) % 1.0 * size.height;
      final opacity = 0.15 + math.sin(t * math.pi * 2 + phase) * 0.1;

      paint.color = const Color(0xFF4CC9F0).withValues(alpha: opacity.clamp(0.05, 0.3));
      canvas.drawCircle(Offset(x, y), radius, paint);
      paint.color = const Color(0xFF4CC9F0).withValues(alpha: opacity * 0.3);
      canvas.drawCircle(Offset(x, y), radius * 3, paint);
    }
  }

  @override
  bool shouldRepaint(_FloatingParticlesPainter old) =>
      (old.t - t).abs() > 0.008;
}
