import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../session/domain/session_user.dart';
import '../../session/presentation/session_cubit.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'bottom_nav_bar.dart';
import 'dashboard_cubit.dart';

// ── Tier system data ────────────────────────────────────────────────────────
class _Tier {
  const _Tier(this.name, this.emoji, this.minXp, this.colors);
  final String name;
  final String emoji;
  final int minXp;
  final List<Color> colors;
}

const List<_Tier> _tiers = <_Tier>[
  _Tier('Bronze', '🥉', 0, <Color>[Color(0xFFCD7F32), Color(0xFFE8A862)]),
  _Tier('Silver', '🥈', 200, <Color>[Color(0xFFA0A0A0), Color(0xFFD0D0D0)]),
  _Tier('Gold', '🥇', 500, <Color>[Color(0xFFFFD166), Color(0xFFF78C6B)]),
  _Tier('Platinum', '💠', 1200, <Color>[Color(0xFF4CC9F0), Color(0xFF7BE0FF)]),
  _Tier('Diamond', '💎', 2500, <Color>[Color(0xFF7B6FD4), Color(0xFFB8A9FF)]),
  _Tier('Master', '👑', 5000, <Color>[Color(0xFFEF476F), Color(0xFFFFD166)]),
];

_Tier _currentTier(int xp) {
  _Tier tier = _tiers.first;
  for (final t in _tiers) {
    if (xp >= t.minXp) tier = t;
  }
  return tier;
}

_Tier? _nextTier(int xp) {
  for (final t in _tiers) {
    if (xp < t.minXp) return t;
  }
  return null;
}

double _tierProgress(int xp) {
  final current = _currentTier(xp);
  final next = _nextTier(xp);
  if (next == null) return 1.0;
  final range = next.minXp - current.minXp;
  return ((xp - current.minXp) / range).clamp(0.0, 1.0);
}

int _streakMultiplier(int streakDays) {
  if (streakDays >= 14) return 4;
  if (streakDays >= 7) return 3;
  if (streakDays >= 3) return 2;
  return 1;
}

// ── Page ─────────────────────────────────────────────────────────────────────
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select(
      (SessionCubit cubit) => cubit.state.user!,
    );

    return BlocProvider<DashboardCubit>(
      create: (BuildContext context) =>
          DashboardCubit(repository: context.read<LearningRepository>())
            ..load(user),
      child: _ProfileView(user: user),
    );
  }
}

class _ProfileView extends StatefulWidget {
  const _ProfileView({required this.user});
  final SessionUser user;

  @override
  State<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<_ProfileView>
    with TickerProviderStateMixin {
  late final AnimationController _staggerController;
  late final AnimationController _pulseController;
  late final AnimationController _ringController;

  @override
  void initState() {
    super.initState();
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..forward();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..forward();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _pulseController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  Animation<double> _fade(double begin, double end) => CurvedAnimation(
        parent: _staggerController,
        curve: Interval(begin, end, curve: Curves.easeOut),
      );

  Animation<Offset> _slide(double begin, double end) =>
      Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(begin, end, curve: Curves.easeOutCubic),
        ),
      );

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
            final weeklyXp = state.data?.weeklyXp;
            final todayXp =
                (weeklyXp != null && weeklyXp.isNotEmpty) ? weeklyXp.last : 0;
            final user = widget.user;

            return SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                children: <Widget>[
                  // ── Header
                  _animated(0.0, 0.25, child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Profile',
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CC9F0)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: IconButton(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.settings_rounded,
                            color: Color(0xFF4CC9F0),
                          ),
                        ),
                      ),
                    ],
                  )),
                  const SizedBox(height: 24),

                  // ── XP Rank Card (THE HERO)
                  _animated(0.05, 0.35,
                      child: _XpRankCard(
                        user: user,
                        pulseController: _pulseController,
                      )),
                  const SizedBox(height: 16),

                  // ── Daily Quest + Streak Multiplier row
                  _animated(0.12, 0.42, child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _DailyQuestCard(
                          todayXp: todayXp,
                          ringAnimation: CurvedAnimation(
                            parent: _ringController,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _StreakMultiplierCard(
                          user: user,
                          pulseController: _pulseController,
                        ),
                      ),
                    ],
                  )),
                  const SizedBox(height: 16),

                  // ── Experience Level
                  _animated(0.2, 0.5,
                      child: _ExperienceLevelCard(user: user)),
                  const SizedBox(height: 16),

                  // ── Next Unlock Teaser
                  _animated(0.28, 0.58,
                      child: _NextUnlockCard(user: user)),
                  const SizedBox(height: 24),

                  // ── Settings
                  _animated(0.45, 0.75, child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x0A000000),
                          blurRadius: 20,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: <Widget>[
                        _SettingsTile(
                          icon: Icons.person_rounded,
                          iconColor: const Color(0xFF4CC9F0),
                          label: 'Edit Profile',
                          onTap: () {},
                        ),
                        _SettingsTile(
                          icon: Icons.notifications_rounded,
                          iconColor: const Color(0xFFFFD166),
                          label: 'Notifications',
                          onTap: () {},
                        ),
                        _SettingsTile(
                          icon: Icons.help_outline_rounded,
                          iconColor: const Color(0xFF80ED99),
                          label: 'Help & Support',
                          onTap: () {},
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 4,
                          ),
                          child: Divider(
                            height: 1,
                            color: Colors.grey.shade200,
                          ),
                        ),
                        _SettingsTile(
                          icon: Icons.logout_rounded,
                          iconColor: const Color(0xFFEF476F),
                          label: 'Log Out',
                          onTap: () => _showLogoutDialog(context),
                        ),
                      ],
                    ),
                  )),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: const BottomNavBar(activeTab: 'profile'),
    );
  }

  Widget _animated(double begin, double end, {required Widget child}) {
    return FadeTransition(
      opacity: _fade(begin, end),
      child: SlideTransition(
        position: _slide(begin, end),
        child: child,
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Log Out',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF6B6B6B)),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.read<SessionCubit>().signOut();
              },
              child: const Text(
                'Log Out',
                style: TextStyle(
                  color: Color(0xFFEF476F),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. XP RANK CARD — the absolute hero
// ─────────────────────────────────────────────────────────────────────────────
class _XpRankCard extends StatelessWidget {
  const _XpRankCard({
    required this.user,
    required this.pulseController,
  });

  final SessionUser user;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    final tier = _currentTier(user.totalXp);
    final next = _nextTier(user.totalXp);
    final progress = _tierProgress(user.totalXp);
    final xpToGo = next != null ? next.minXp - user.totalXp : 0;
    final multiplier = _streakMultiplier(user.streakDays);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1B2432), Color(0xFF33415C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFF1B2432).withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          // Background orbs
          Positioned(
            top: -40,
            right: -30,
            child: AnimatedBuilder(
              animation: pulseController,
              builder: (BuildContext context, Widget? child) {
                return Transform.scale(
                  scale: 1.0 + 0.1 * pulseController.value,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: <Color>[
                          tier.colors[0].withValues(alpha: 0.12),
                          tier.colors[0].withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: -25,
            left: -20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tier.colors[1].withValues(alpha: 0.06),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                // ── Name + avatar row
                Row(
                  children: <Widget>[
                    // Avatar with tier-colored ring
                    AnimatedBuilder(
                      animation: pulseController,
                      builder: (BuildContext context, Widget? child) {
                        final glow = 0.2 + 0.15 * pulseController.value;
                        return Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: tier.colors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: tier.colors[0].withValues(alpha: glow),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: child,
                        );
                      },
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2A3750),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          tier.emoji,
                          style: const TextStyle(fontSize: 30),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            user.displayName,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 20,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              // Tier badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: tier.colors,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  tier.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              if (multiplier > 1) ...<Widget>[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF476F)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${multiplier}x 🔥',
                                    style: const TextStyle(
                                      color: Color(0xFFFF8FA3),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Big XP display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: tier.colors[0].withValues(alpha: 0.15),
                    ),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'TOTAL XP',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ShaderMask(
                        shaderCallback: (Rect bounds) => LinearGradient(
                          colors: tier.colors,
                        ).createShader(bounds),
                        child: Text(
                          '${user.totalXp}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Tier progress bar
                if (next != null) ...<Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            tier.emoji,
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tier.name,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: <Widget>[
                          Text(
                            next.name,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            next.emoji,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: SizedBox(
                      height: 10,
                      child: Stack(
                        children: <Widget>[
                          Container(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          FractionallySizedBox(
                            widthFactor: progress,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: tier.colors,
                                ),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color:
                                        tier.colors[0].withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$xpToGo XP to ${next.name}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text('👑', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 6),
                        Text(
                          'MAX RANK ACHIEVED',
                          style: TextStyle(
                            color: tier.colors[0],
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
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
// 2. DAILY QUEST — animated ring for today's XP goal
// ─────────────────────────────────────────────────────────────────────────────
class _DailyQuestCard extends StatelessWidget {
  const _DailyQuestCard({
    required this.todayXp,
    required this.ringAnimation,
  });

  final int todayXp;
  final Animation<double> ringAnimation;

  static const int _dailyGoal = 50;

  @override
  Widget build(BuildContext context) {
    final progress = (todayXp / _dailyGoal).clamp(0.0, 1.0);
    final completed = todayXp >= _dailyGoal;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Text(
            'Daily Quest',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 80,
            height: 80,
            child: AnimatedBuilder(
              animation: ringAnimation,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: _DailyRingPainter(
                    progress: progress * ringAnimation.value,
                    completed: completed,
                  ),
                  child: child,
                );
              },
              child: Center(
                child: completed
                    ? const Text('✅', style: TextStyle(fontSize: 24))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            '$todayXp',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2D2D2D),
                            ),
                          ),
                          Text(
                            '/ $_dailyGoal',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            completed ? 'Quest Done!' : '${_dailyGoal - todayXp} XP left',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: completed
                  ? const Color(0xFF2D8A4E)
                  : const Color(0xFF6B6B6B),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyRingPainter extends CustomPainter {
  const _DailyRingPainter({required this.progress, required this.completed});
  final double progress;
  final bool completed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const strokeWidth = 8.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = const Color(0xFFF0F0F0),
    );

    if (progress > 0) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        progress * math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..shader = const SweepGradient(
            colors: <Color>[Color(0xFF80ED99), Color(0xFF4CC9F0)],
            transform: GradientRotation(-math.pi / 2),
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_DailyRingPainter old) => old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. STREAK MULTIPLIER — fire that grows with streak
// ─────────────────────────────────────────────────────────────────────────────
class _StreakMultiplierCard extends StatelessWidget {
  const _StreakMultiplierCard({
    required this.user,
    required this.pulseController,
  });

  final SessionUser user;
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    final multiplier = _streakMultiplier(user.streakDays);
    final nextMultiplierAt = user.streakDays < 3
        ? 3
        : user.streakDays < 7
            ? 7
            : user.streakDays < 14
                ? 14
                : 0;

    return AnimatedBuilder(
      animation: pulseController,
      builder: (BuildContext context, Widget? child) {
        final fireGlow = user.streakDays > 0
            ? 0.06 + pulseController.value * 0.08
            : 0.0;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                const Color(0xFFEF476F).withValues(alpha: 0.06 + fireGlow),
                const Color(0xFFF78C6B).withValues(alpha: 0.03),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFFEF476F)
                  .withValues(alpha: user.streakDays > 0 ? 0.15 : 0.06),
            ),
            boxShadow: <BoxShadow>[
              if (user.streakDays > 0)
                BoxShadow(
                  color: const Color(0xFFEF476F).withValues(alpha: fireGlow),
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        children: <Widget>[
          Text(
            'Streak Bonus',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          // Fire size based on streak
          Text(
            user.streakDays >= 14
                ? '🔥🔥🔥'
                : user.streakDays >= 7
                    ? '🔥🔥'
                    : user.streakDays >= 3
                        ? '🔥'
                        : '💤',
            style: const TextStyle(fontSize: 28),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: multiplier > 1
                  ? const Color(0xFFEF476F).withValues(alpha: 0.12)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${multiplier}x XP',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: multiplier > 1
                    ? const Color(0xFFEF476F)
                    : Colors.grey.shade400,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${user.streakDays}d streak',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFFEF476F),
            ),
          ),
          if (nextMultiplierAt > 0) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '${nextMultiplierAt - user.streakDays}d to next bonus',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. EXPERIENCE LEVEL — shows current level + progress to next
// ─────────────────────────────────────────────────────────────────────────────
class _ExperienceLevelCard extends StatelessWidget {
  const _ExperienceLevelCard({required this.user});

  final SessionUser user;

  @override
  Widget build(BuildContext context) {
    final level = user.experienceLevel;
    final nextLevel = level.next;
    final progress = LevelUpRequirements.progress(
      currentLevel: level,
      gamesPlayed: user.gamesPlayed,
      wordsLearned: user.wordsLearned,
      totalXp: user.totalXp,
    );
    final gradColors = level.gradientHex
        .map((int hex) => Color(hex))
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            gradColors[0].withValues(alpha: 0.08),
            gradColors[1].withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: gradColors[0].withValues(alpha: 0.2),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              // Level emoji with gradient background
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradColors),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: gradColors[0].withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  level.emoji,
                  style: const TextStyle(fontSize: 24),
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
                          level.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            color: Color(0xFF2D2D2D),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: gradColors),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${level.xpMultiplier}x XP',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      level.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Level perks row
          Row(
            children: <Widget>[
              _LevelPerk(
                icon: Icons.timer_rounded,
                label: '${level.roundSeconds}s',
                color: gradColors[0],
              ),
              const SizedBox(width: 10),
              _LevelPerk(
                icon: Icons.favorite_rounded,
                label: '${level.startingLives}',
                color: gradColors[0],
              ),
              const SizedBox(width: 10),
              _LevelPerk(
                icon: Icons.auto_awesome_rounded,
                label: '${level.wordsPerSession}w',
                color: gradColors[0],
              ),
            ],
          ),

          if (nextLevel != null) ...<Widget>[
            const SizedBox(height: 16),
            // Progress to next level
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Progress to ${nextLevel.title}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: gradColors[0],
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: <Widget>[
                    Container(color: gradColors[0].withValues(alpha: 0.12)),
                    FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: gradColors),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Text('⚡', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  ShaderMask(
                    shaderCallback: (Rect bounds) =>
                        LinearGradient(colors: gradColors).createShader(bounds),
                    child: const Text(
                      'MAX LEVEL ACHIEVED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
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

class _LevelPerk extends StatelessWidget {
  const _LevelPerk({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. NEXT UNLOCK TEASER — shows what's coming to create FOMO
// ─────────────────────────────────────────────────────────────────────────────
class _NextUnlockCard extends StatelessWidget {
  const _NextUnlockCard({required this.user});

  final SessionUser user;

  @override
  Widget build(BuildContext context) {
    final nextTier = _nextTier(user.totalXp);
    if (nextTier == null) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFFF8E8), Color(0xFFFFF1D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFFFD166).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('🎯', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                'Coming Up Next',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF2D2D2D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _UnlockRow(
            emoji: nextTier.emoji,
            title: '${nextTier.name} Tier',
            subtitle: '${nextTier.minXp - user.totalXp} XP away',
            progress: _tierProgress(user.totalXp),
            colors: nextTier.colors,
          ),
        ],
      ),
    );
  }
}

class _UnlockRow extends StatelessWidget {
  const _UnlockRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.colors,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final double progress;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors[0].withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF2D2D2D),
                      ),
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: colors[0],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 6,
                  child: Stack(
                    children: <Widget>[
                      Container(color: colors[0].withValues(alpha: 0.12)),
                      FractionallySizedBox(
                        widthFactor: progress.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: colors),
                          ),
                        ),
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
// Settings Tile
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: label == 'Log Out' ? const Color(0xFFEF476F) : null,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: label == 'Log Out'
            ? const Color(0xFFEF476F).withValues(alpha: 0.5)
            : const Color(0xFFCCCCCC),
      ),
    );
  }
}
