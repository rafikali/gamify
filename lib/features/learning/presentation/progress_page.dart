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

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.user});

  final SessionUser user;

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
          final weeklyData = state.data?.weeklyXp ?? List<int>.filled(7, 0);
          final weeklyTotal = weeklyData.fold(
            0,
            (int sum, int value) => sum + value,
          );
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
              children: <Widget>[
                Text(
                  'Your Progress',
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF4CC9F0), Color(0xFFA28AE5)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'Words Cleared',
                              style: TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${user.wordsLearned}',
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: <Widget>[
                                const Icon(
                                  Icons.trending_up_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  weeklyTotal > 0
                                      ? '+$weeklyTotal XP this week'
                                      : 'Start your streak today',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _ProgressCard(
                  title: 'Weekly Progress',
                  child: SizedBox(
                    height: 200,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List<Widget>.generate(weeklyData.length, (
                        int index,
                      ) {
                        final value = weeklyData[index];
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            Container(
                              width: 28,
                              height: value * 4.0,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CC9F0),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              const <String>[
                                'Mon',
                                'Tue',
                                'Wed',
                                'Thu',
                                'Fri',
                                'Sat',
                                'Sun',
                              ][index],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _ProgressCard(
                  title: 'Streak History',
                  subtitle: 'Keep it going!',
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      _MetricColumn(
                        value: '${user.streakDays} Days',
                        label: 'Current Streak 🔥',
                      ),
                      _MetricColumn(
                        value: '${user.bestStreak} Days',
                        label: 'Best Streak 🏆',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _ProgressCard(
                  title: 'Category Completion',
                  child: Column(
                    children: categories.map((LearningCategory category) {
                      final progress = (category.masteryPercent * 100).round();
                      final color = parseHexColor(category.accentHex);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(category.emoji),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    category.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                Text(
                                  '$progress%',
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: category.masteryPercent,
                                minHeight: 8,
                                backgroundColor: const Color(0xFFF0F0F0),
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
      bottomNavigationBar: const BottomNavBar(activeTab: 'progress'),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
