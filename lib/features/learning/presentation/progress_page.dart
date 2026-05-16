import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/widgets/icon_mapper.dart';
import '../../session/domain/session_user.dart';
import '../../session/presentation/session_cubit.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'bottom_nav_bar.dart';
import 'dashboard_cubit.dart';

class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select(
      (SessionCubit cubit) => cubit.state.user!,
    );

    return BlocProvider<DashboardCubit>(
      create: (BuildContext context) =>
          DashboardCubit(repository: context.read<LearningRepository>())
            ..load(user),
      child: _ProgressView(user: user),
    );
  }
}

class _ProgressView extends StatefulWidget {
  const _ProgressView({required this.user});

  final SessionUser user;

  @override
  State<_ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<_ProgressView>
    with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Animation<double> _staggerFade(double start) {
    final end = (start + 0.15).clamp(0.0, 1.0);
    return Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, end, curve: Curves.easeOut),
    ));
  }

  Animation<Offset> _staggerSlide(double start) {
    final end = (start + 0.15).clamp(0.0, 1.0);
    return Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _staggerController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<SessionCubit, SessionState>(
        listenWhen: (SessionState prev, SessionState curr) =>
            prev.user != curr.user && curr.user != null,
        listener: (BuildContext context, SessionState state) {
          context.read<DashboardCubit>().load(state.user!);
        },
        child: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (BuildContext context, DashboardState state) {
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            final categories =
                state.data?.categories ?? const <LearningCategory>[];
            final achievements =
                state.data?.achievements ?? const <Achievement>[];
            final weeklyData =
                state.data?.weeklyXp ?? List<int>.filled(7, 0);
            final weeklyTotal =
                weeklyData.fold(0, (int sum, int value) => sum + value);
            final user = widget.user;

            final totalAccuracy = user.gamesPlayed > 0
                ? ((user.wordsLearned /
                            (user.wordsLearned +
                                (user.gamesPlayed * 3 - user.wordsLearned)
                                    .clamp(0, 999))) *
                        100)
                    .round()
                    .clamp(0, 100)
                : 0;
            final avgXpPerGame = user.gamesPlayed > 0
                ? (user.totalXp / user.gamesPlayed).round()
                : 0;
            final masteredCategories = categories
                .where(
                    (LearningCategory c) => c.masteryPercent >= 0.8)
                .length;
            final overallMastery = categories.isEmpty
                ? 0.0
                : categories.fold(0.0,
                        (double sum, LearningCategory c) =>
                            sum + c.masteryPercent) /
                    categories.length;

            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Color(0xFFF8F9FE),
                    Color(0xFFEEF0FA),
                    Color(0xFFF8F9FE),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                  children: <Widget>[
                    // ── Header ──
                    SlideTransition(
                      position: _staggerSlide(0.0),
                      child: FadeTransition(
                        opacity: _staggerFade(0.0),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    'Progress Overview',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: -0.5,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Your learning journey at a glance',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _AnimatedLevelBadge(
                              level: _calculateLevel(user.totalXp),
                              pulseController: _pulseController,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── XP Overview Hero Card ──
                    SlideTransition(
                      position: _staggerSlide(0.05),
                      child: FadeTransition(
                        opacity: _staggerFade(0.05),
                        child: _XpHeroCard(
                          user: user,
                          weeklyTotal: weeklyTotal,
                          shimmerController: _shimmerController,
                          staggerController: _staggerController,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Quick Stats Grid ──
                    SlideTransition(
                      position: _staggerSlide(0.12),
                      child: FadeTransition(
                        opacity: _staggerFade(0.12),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: _QuickStatCard(
                                icon: Icons.games_rounded,
                                iconColor: const Color(0xFF7B6FD4),
                                label: 'Games Played',
                                value: '${user.gamesPlayed}',
                                bgColor: const Color(0xFFF0EDFA),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickStatCard(
                                icon: Icons.track_changes_rounded,
                                iconColor: const Color(0xFF4CC9F0),
                                label: 'Accuracy',
                                value: '$totalAccuracy%',
                                bgColor: const Color(0xFFE8F7FD),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SlideTransition(
                      position: _staggerSlide(0.16),
                      child: FadeTransition(
                        opacity: _staggerFade(0.16),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: _QuickStatCard(
                                icon: Icons.speed_rounded,
                                iconColor: const Color(0xFFF78C6B),
                                label: 'Avg XP / Game',
                                value: '$avgXpPerGame',
                                bgColor: const Color(0xFFFFF0EB),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _QuickStatCard(
                                icon: Icons.emoji_events_rounded,
                                iconColor: const Color(0xFFFFD166),
                                label: 'Mastered',
                                value:
                                    '$masteredCategories/${categories.length}',
                                bgColor: const Color(0xFFFFF8E8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Weekly Activity Chart ──
                    SlideTransition(
                      position: _staggerSlide(0.22),
                      child: FadeTransition(
                        opacity: _staggerFade(0.22),
                        child: _WeeklyActivityCard(
                          weeklyData: weeklyData,
                          staggerController: _staggerController,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Streak & Consistency ──
                    SlideTransition(
                      position: _staggerSlide(0.30),
                      child: FadeTransition(
                        opacity: _staggerFade(0.30),
                        child: _StreakCard(
                          user: user,
                          weeklyData: weeklyData,
                          pulseController: _pulseController,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Overall Mastery Ring ──
                    SlideTransition(
                      position: _staggerSlide(0.38),
                      child: FadeTransition(
                        opacity: _staggerFade(0.38),
                        child: _OverallMasteryCard(
                          mastery: overallMastery,
                          staggerController: _staggerController,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Category Breakdown ──
                    SlideTransition(
                      position: _staggerSlide(0.45),
                      child: FadeTransition(
                        opacity: _staggerFade(0.45),
                        child: _CategoryBreakdownCard(
                          categories: categories,
                          staggerController: _staggerController,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Achievements ──
                    SlideTransition(
                      position: _staggerSlide(0.55),
                      child: FadeTransition(
                        opacity: _staggerFade(0.55),
                        child: _AchievementsCard(
                          achievements: achievements,
                          pulseController: _pulseController,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Learning Insights ──
                    SlideTransition(
                      position: _staggerSlide(0.62),
                      child: FadeTransition(
                        opacity: _staggerFade(0.62),
                        child: _InsightsCard(
                          user: user,
                          weeklyData: weeklyData,
                          categories: categories,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: const BottomNavBar(activeTab: 'progress'),
    );
  }

  int _calculateLevel(int totalXp) {
    if (totalXp < 50) return 1;
    if (totalXp < 150) return 2;
    if (totalXp < 300) return 3;
    if (totalXp < 500) return 4;
    if (totalXp < 800) return 5;
    if (totalXp < 1200) return 6;
    if (totalXp < 1800) return 7;
    if (totalXp < 2500) return 8;
    if (totalXp < 3500) return 9;
    return 10;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Level Badge with pulse glow
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedLevelBadge extends StatelessWidget {
  const _AnimatedLevelBadge({
    required this.level,
    required this.pulseController,
  });

  final int level;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (BuildContext context, Widget? child) {
        final glow = 0.15 + pulseController.value * 0.2;
        return Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFFFFD166), Color(0xFFF78C6B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFFFFD166).withValues(alpha: glow),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'LV',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '$level',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// XP Hero Card
// ─────────────────────────────────────────────────────────────────────────────

class _XpHeroCard extends StatelessWidget {
  const _XpHeroCard({
    required this.user,
    required this.weeklyTotal,
    required this.shimmerController,
    required this.staggerController,
  });

  final SessionUser user;
  final int weeklyTotal;
  final AnimationController shimmerController;
  final AnimationController staggerController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFF3D2B6B),
            Color(0xFF7B6FD4),
            Color(0xFF4CC9F0),
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF7B6FD4).withValues(alpha: 0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Total XP',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Animated counter
                    _AnimatedCounter(
                      value: user.totalXp,
                      staggerController: staggerController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
              ),
              // Shimmer XP icon
              AnimatedBuilder(
                animation: shimmerController,
                builder: (BuildContext context, Widget? child) {
                  return Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    child: ShaderMask(
                      shaderCallback: (Rect bounds) {
                        final x = (shimmerController.value * 3) - 1;
                        return ui.Gradient.linear(
                          Offset(bounds.width * x, 0),
                          Offset(bounds.width * (x + 0.4), bounds.height),
                          <Color>[
                            Colors.white,
                            const Color(0xFFFFD166),
                            Colors.white,
                          ],
                          <double>[0.0, 0.5, 1.0],
                        );
                      },
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          // XP bar to next level
          _XpProgressBar(totalXp: user.totalXp),
          const SizedBox(height: 16),
          // Bottom stats row
          Row(
            children: <Widget>[
              _HeroStat(
                icon: Icons.menu_book_rounded,
                label: 'Words',
                value: '${user.wordsLearned}',
              ),
              _heroDivider(),
              _HeroStat(
                icon: Icons.trending_up_rounded,
                label: 'This Week',
                value: weeklyTotal > 0 ? '+$weeklyTotal' : '0',
              ),
              _heroDivider(),
              _HeroStat(
                icon: Icons.local_fire_department_rounded,
                label: 'Streak',
                value: '${user.streakDays}d',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroDivider() {
    return Container(
      width: 1,
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white.withValues(alpha: 0.15),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 18),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _XpProgressBar extends StatelessWidget {
  const _XpProgressBar({required this.totalXp});

  final int totalXp;

  static const List<int> _levelThresholds = <int>[
    0, 50, 150, 300, 500, 800, 1200, 1800, 2500, 3500, 5000,
  ];

  @override
  Widget build(BuildContext context) {
    int currentLevel = 1;
    int currentThreshold = 0;
    int nextThreshold = 50;
    for (int i = 0; i < _levelThresholds.length - 1; i++) {
      if (totalXp >= _levelThresholds[i]) {
        currentLevel = i + 1;
        currentThreshold = _levelThresholds[i];
        nextThreshold = _levelThresholds[i + 1];
      }
    }

    final xpInLevel = totalXp - currentThreshold;
    final xpNeeded = nextThreshold - currentThreshold;
    final progress = xpNeeded > 0 ? (xpInLevel / xpNeeded).clamp(0.0, 1.0) : 1.0;

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Level $currentLevel',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$xpInLevel / $xpNeeded XP',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
            Text(
              'Level ${currentLevel + 1}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: <Widget>[
              Container(
                height: 10,
                color: Colors.white.withValues(alpha: 0.12),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFFFD166), Color(0xFF80ED99)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFF80ED99).withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated Counter
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedCounter extends StatelessWidget {
  const _AnimatedCounter({
    required this.value,
    required this.staggerController,
    required this.style,
  });

  final int value;
  final AnimationController staggerController;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: staggerController,
      builder: (BuildContext context, Widget? child) {
        final curve = Curves.easeOutCubic.transform(
          Tween<double>(begin: 0, end: 1)
              .animate(CurvedAnimation(
                parent: staggerController,
                curve: const Interval(0.1, 0.5),
              ))
              .value,
        );
        final displayValue = (value * curve).round();
        return Text('$displayValue', style: style);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Stat Card
// ─────────────────────────────────────────────────────────────────────────────

class _QuickStatCard extends StatelessWidget {
  const _QuickStatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.bgColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: iconColor,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
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

// ─────────────────────────────────────────────────────────────────────────────
// Weekly Activity Chart with animated bars
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyActivityCard extends StatelessWidget {
  const _WeeklyActivityCard({
    required this.weeklyData,
    required this.staggerController,
  });

  final List<int> weeklyData;
  final AnimationController staggerController;

  static const List<String> _weekdayLabels = <String>[
    'M', 'T', 'W', 'T', 'F', 'S', 'S',
  ];

  @override
  Widget build(BuildContext context) {
    final maxXp = weeklyData.reduce(math.max).clamp(1, 9999);
    // weeklyData is indexed 0..6 where index 6 = today, index 0 = 6 days ago
    const todayIndex = 6;
    final now = DateTime.now();
    final activeDays = weeklyData.where((int v) => v > 0).length;
    // Build correct day labels for each index
    final dayLabels = List<String>.generate(7, (int i) {
      final day = now.subtract(Duration(days: 6 - i));
      return _weekdayLabels[day.weekday - 1];
    });

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.bar_chart_rounded, size: 20,
                  color: Color(0xFF7B6FD4)),
              const SizedBox(width: 8),
              Text(
                'Weekly Activity',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF80ED99).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$activeDays/7 days',
                  style: const TextStyle(
                    color: Color(0xFF2D8A4E),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: AnimatedBuilder(
              animation: staggerController,
              builder: (BuildContext context, Widget? child) {
                final barAnim = Tween<double>(begin: 0, end: 1)
                    .animate(CurvedAnimation(
                  parent: staggerController,
                  curve: const Interval(0.25, 0.65, curve: Curves.easeOutCubic),
                ))
                    .value;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List<Widget>.generate(7, (int i) {
                    final value = weeklyData[i];
                    final barHeight =
                        value > 0 ? (value / maxXp * 110).clamp(12.0, 110.0) : 4.0;
                    final isToday = i == todayIndex;
                    final hasActivity = value > 0;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            if (hasActivity)
                              Text(
                                '$value',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isToday
                                      ? const Color(0xFF4CC9F0)
                                      : Colors.grey.shade500,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Container(
                              height: barHeight * barAnim,
                              decoration: BoxDecoration(
                                gradient: hasActivity
                                    ? LinearGradient(
                                        colors: isToday
                                            ? const <Color>[
                                                Color(0xFF4CC9F0),
                                                Color(0xFF7B6FD4),
                                              ]
                                            : <Color>[
                                                const Color(0xFF7B6FD4)
                                                    .withValues(alpha: 0.4),
                                                const Color(0xFF4CC9F0)
                                                    .withValues(alpha: 0.4),
                                              ],
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                      )
                                    : null,
                                color: hasActivity
                                    ? null
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: isToday
                                    ? const Color(0xFF4CC9F0)
                                        .withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                dayLabels[i],
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isToday
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: isToday
                                      ? const Color(0xFF4CC9F0)
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Streak & Consistency Card
// ─────────────────────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.user,
    required this.weeklyData,
    required this.pulseController,
  });

  final SessionUser user;
  final List<int> weeklyData;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    final activeDays = weeklyData.where((int v) => v > 0).length;
    final consistency = (activeDays / 7 * 100).round();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.local_fire_department_rounded, size: 20,
                  color: Color(0xFFEF476F)),
              const SizedBox(width: 8),
              Text(
                'Streaks & Consistency',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              // Current streak with fire animation
              Expanded(
                child: AnimatedBuilder(
                  animation: pulseController,
                  builder: (BuildContext context, Widget? child) {
                    final fireGlow = 0.1 + pulseController.value * 0.15;
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            const Color(0xFFEF476F).withValues(alpha: 0.08),
                            const Color(0xFFF78C6B).withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFEF476F).withValues(alpha: 0.15),
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: const Color(0xFFEF476F)
                                .withValues(alpha: fireGlow),
                            blurRadius: 20,
                            spreadRadius: -5,
                          ),
                        ],
                      ),
                      child: Column(
                        children: <Widget>[
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${user.streakDays}',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFEF476F),
                              ),
                            ),
                          ),
                          const Text(
                            'Day Streak',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFEF476F),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Best streak
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E8),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFFFFD166).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${user.bestStreak}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFE8A800),
                          ),
                        ),
                      ),
                      const Text(
                        'Best Streak',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE8A800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Consistency
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8FFF0),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF80ED99).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$consistency',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2D8A4E),
                          ),
                        ),
                      ),
                      const Text(
                        '%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2D8A4E),
                        ),
                      ),
                      const Text(
                        'This Week',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2D8A4E),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Heat map row — 7 day activity dots
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List<Widget>.generate(7, (int i) {
              final hasActivity = weeklyData[i] > 0;
              return Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: hasActivity
                      ? const Color(0xFF80ED99).withValues(alpha: 0.2)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasActivity
                          ? const Color(0xFF2D8A4E)
                          : Colors.grey.shade300,
                    ),
                    child: hasActivity
                        ? const Icon(Icons.check, size: 10, color: Colors.white)
                        : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overall Mastery Ring
// ─────────────────────────────────────────────────────────────────────────────

class _OverallMasteryCard extends StatelessWidget {
  const _OverallMasteryCard({
    required this.mastery,
    required this.staggerController,
  });

  final double mastery;
  final AnimationController staggerController;

  @override
  Widget build(BuildContext context) {
    final percent = (mastery * 100).round();
    final label = percent >= 80
        ? 'Expert'
        : percent >= 50
            ? 'Intermediate'
            : percent >= 20
                ? 'Beginner'
                : 'Getting Started';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.donut_large_rounded, size: 20,
                  color: Color(0xFF4CC9F0)),
              const SizedBox(width: 8),
              Text(
                'Overall Mastery',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF4CC9F0),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 160,
            height: 160,
            child: AnimatedBuilder(
              animation: staggerController,
              builder: (BuildContext context, Widget? child) {
                final ringAnim = Tween<double>(begin: 0, end: mastery)
                    .animate(CurvedAnimation(
                  parent: staggerController,
                  curve: const Interval(0.4, 0.8, curve: Curves.easeOutCubic),
                ))
                    .value;
                return CustomPaint(
                  painter: _MasteryRingPainter(
                    progress: ringAnim,
                    percent: (ringAnim * 100).round(),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          '${(ringAnim * 100).round()}%',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                        Text(
                          'mastered',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MasteryRingPainter extends CustomPainter {
  const _MasteryRingPainter({required this.progress, required this.percent});

  final double progress;
  final int percent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const strokeWidth = 14.0;

    // Background ring
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = const Color(0xFFF0F0F0),
    );

    // Progress arc
    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      colors: const <Color>[
        Color(0xFF4CC9F0),
        Color(0xFF7B6FD4),
        Color(0xFFEF476F),
      ],
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = gradient.createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );

    // Dot at the end of the arc
    if (progress > 0.01) {
      final angle = -math.pi / 2 + progress * math.pi * 2;
      final dotCenter = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawCircle(
        dotCenter,
        6,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        dotCenter,
        4,
        Paint()..color = const Color(0xFFEF476F),
      );
    }
  }

  @override
  bool shouldRepaint(_MasteryRingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Breakdown
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryBreakdownCard extends StatelessWidget {
  const _CategoryBreakdownCard({
    required this.categories,
    required this.staggerController,
  });

  final List<LearningCategory> categories;
  final AnimationController staggerController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.category_rounded, size: 20,
                  color: Color(0xFFF78C6B)),
              const SizedBox(width: 8),
              Text(
                'Category Breakdown',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...categories.map((LearningCategory category) {
            final color = parseHexColor(category.accentHex);
            final percent = (category.masteryPercent * 100).round();
            final isMastered = percent >= 80;

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: <Widget>[
                  // Emoji avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        category.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title + bar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                category.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (isMastered)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF80ED99)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'MASTERED',
                                  style: TextStyle(
                                    color: Color(0xFF2D8A4E),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Text(
                              '$percent%',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: color,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        AnimatedBuilder(
                          animation: staggerController,
                          builder: (BuildContext context, Widget? child) {
                            final barAnim = Tween<double>(begin: 0, end: 1)
                                .animate(CurvedAnimation(
                              parent: staggerController,
                              curve: const Interval(0.5, 0.85,
                                  curve: Curves.easeOutCubic),
                            ))
                                .value;
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: Stack(
                                children: <Widget>[
                                  Container(
                                    height: 8,
                                    color: color.withValues(alpha: 0.1),
                                  ),
                                  FractionallySizedBox(
                                    widthFactor:
                                        category.masteryPercent * barAnim,
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: <Color>[
                                            color,
                                            color.withValues(alpha: 0.7),
                                          ],
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Achievements
// ─────────────────────────────────────────────────────────────────────────────

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({
    required this.achievements,
    required this.pulseController,
  });

  final List<Achievement> achievements;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.emoji_events_rounded, size: 20,
                  color: Color(0xFFFFD166)),
              const SizedBox(width: 8),
              Text(
                'Achievements',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Text(
                '${achievements.where((Achievement a) => a.unlocked).length}/${achievements.length}',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...achievements.map((Achievement achievement) {
            final progressPercent = (achievement.progress * 100).round();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: AnimatedBuilder(
                animation: pulseController,
                builder: (BuildContext context, Widget? child) {
                  final glow = achievement.unlocked
                      ? 0.08 + pulseController.value * 0.08
                      : 0.0;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: achievement.unlocked
                          ? const Color(0xFFFFF8E8)
                          : const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: achievement.unlocked
                            ? const Color(0xFFFFD166).withValues(alpha: 0.4)
                            : Colors.grey.shade200,
                      ),
                      boxShadow: <BoxShadow>[
                        if (achievement.unlocked)
                          BoxShadow(
                            color:
                                const Color(0xFFFFD166).withValues(alpha: glow),
                            blurRadius: 16,
                            spreadRadius: -2,
                          ),
                      ],
                    ),
                    child: Row(
                      children: <Widget>[
                        Text(
                          achievement.emoji,
                          style: TextStyle(
                            fontSize: 28,
                            color: achievement.unlocked
                                ? null
                                : const Color(0x55000000),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Text(
                                    achievement.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: achievement.unlocked
                                          ? const Color(0xFF2D2D2D)
                                          : Colors.grey.shade500,
                                    ),
                                  ),
                                  if (achievement.unlocked) ...<Widget>[
                                    const SizedBox(width: 6),
                                    const Icon(
                                      Icons.verified_rounded,
                                      size: 16,
                                      color: Color(0xFFFFD166),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                achievement.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: Stack(
                                  children: <Widget>[
                                    Container(
                                      height: 6,
                                      color: achievement.unlocked
                                          ? const Color(0xFFFFD166)
                                              .withValues(alpha: 0.2)
                                          : Colors.grey.shade200,
                                    ),
                                    FractionallySizedBox(
                                      widthFactor: achievement.progress,
                                      child: Container(
                                        height: 6,
                                        decoration: BoxDecoration(
                                          gradient: achievement.unlocked
                                              ? const LinearGradient(
                                                  colors: <Color>[
                                                    Color(0xFFFFD166),
                                                    Color(0xFFF78C6B),
                                                  ],
                                                )
                                              : LinearGradient(
                                                  colors: <Color>[
                                                    Colors.grey.shade400,
                                                    Colors.grey.shade300,
                                                  ],
                                                ),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$progressPercent%',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: achievement.unlocked
                                ? const Color(0xFFE8A800)
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Learning Insights
// ─────────────────────────────────────────────────────────────────────────────

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({
    required this.user,
    required this.weeklyData,
    required this.categories,
  });

  final SessionUser user;
  final List<int> weeklyData;
  final List<LearningCategory> categories;

  @override
  Widget build(BuildContext context) {
    final bestDay = _bestDayOfWeek();
    final strongestCategory = _strongestCategory();
    final weakestCategory = _weakestCategory();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[
            Color(0xFF1A1030),
            Color(0xFF3D2B6B),
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF3D2B6B).withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.insights_rounded, size: 20,
                  color: Color(0xFF4CC9F0)),
              const SizedBox(width: 8),
              Text(
                'Learning Insights',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CC9F0).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                    color: Color(0xFF4CC9F0),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _InsightRow(
            icon: Icons.calendar_today_rounded,
            color: const Color(0xFF80ED99),
            title: 'Most Productive Day',
            value: bestDay,
          ),
          const SizedBox(height: 14),
          _InsightRow(
            icon: Icons.star_rounded,
            color: const Color(0xFFFFD166),
            title: 'Strongest Category',
            value: strongestCategory,
          ),
          const SizedBox(height: 14),
          _InsightRow(
            icon: Icons.trending_up_rounded,
            color: const Color(0xFFEF476F),
            title: 'Needs Practice',
            value: weakestCategory,
          ),
          const SizedBox(height: 14),
          _InsightRow(
            icon: Icons.speed_rounded,
            color: const Color(0xFF4CC9F0),
            title: 'Learning Pace',
            value: _learningPace(),
          ),
          if (user.gamesPlayed > 0) ...<Widget>[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Text(
                _personalizedTip(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _bestDayOfWeek() {
    if (weeklyData.every((int v) => v == 0)) return 'No data yet';
    const dayNames = <String>[
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    int bestIndex = 0;
    for (int i = 1; i < weeklyData.length; i++) {
      if (weeklyData[i] > weeklyData[bestIndex]) bestIndex = i;
    }
    // weeklyData is indexed 0..6 where index 6 = today, index 0 = 6 days ago
    final now = DateTime.now();
    final bestDay = now.subtract(Duration(days: 6 - bestIndex));
    final bestDayName = dayNames[bestDay.weekday - 1];
    return '$bestDayName (${weeklyData[bestIndex]} XP)';
  }

  String _strongestCategory() {
    if (categories.isEmpty) return 'Play to find out';
    final sorted = List<LearningCategory>.from(categories)
      ..sort((LearningCategory a, LearningCategory b) =>
          b.masteryPercent.compareTo(a.masteryPercent));
    final best = sorted.first;
    return best.masteryPercent > 0
        ? '${best.emoji} ${best.title}'
        : 'Play to find out';
  }

  String _weakestCategory() {
    if (categories.isEmpty) return 'Play to find out';
    final withProgress = categories
        .where((LearningCategory c) => c.masteryPercent > 0)
        .toList();
    if (withProgress.isEmpty) return 'Play to find out';
    final sorted = List<LearningCategory>.from(withProgress)
      ..sort((LearningCategory a, LearningCategory b) =>
          a.masteryPercent.compareTo(b.masteryPercent));
    return '${sorted.first.emoji} ${sorted.first.title}';
  }

  String _learningPace() {
    if (user.gamesPlayed == 0) return 'Not started';
    final wordsPerGame =
        (user.wordsLearned / user.gamesPlayed).toStringAsFixed(1);
    return '$wordsPerGame words/game';
  }

  String _personalizedTip() {
    if (user.streakDays >= 7) {
      return 'Incredible streak! You\'re in the top tier of learners. '
          'Keep pushing for mastery across all categories.';
    }
    if (user.streakDays >= 3) {
      return 'Great momentum! Try to practice at the same time each day '
          'to build a lasting habit.';
    }
    if (user.gamesPlayed >= 5) {
      return 'You\'re building a solid foundation. Focus on your weakest '
          'category to level up faster.';
    }
    return 'Play daily to build streaks and unlock achievements. '
        'Even 5 minutes a day makes a difference!';
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
