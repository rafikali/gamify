import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/icon_mapper.dart';
import '../../session/domain/session_user.dart';
import '../../session/presentation/session_cubit.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'dashboard_cubit.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.bootstrapWarning});

  final String? bootstrapWarning;

  @override
  Widget build(BuildContext context) {
    final user = context.select(
      (SessionCubit cubit) => cubit.state.user!,
    );

    return BlocProvider<DashboardCubit>(
      create: (BuildContext context) =>
          DashboardCubit(repository: context.read<LearningRepository>())
            ..load(user),
      child: _DashboardView(
        user: user,
        bootstrapWarning: bootstrapWarning,
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.user, required this.bootstrapWarning});

  final SessionUser user;
  final String? bootstrapWarning;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Learnify'),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.read<SessionCubit>().signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: BlocBuilder<DashboardCubit, DashboardState>(
        builder: (BuildContext context, DashboardState state) {
          if (state.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state.errorMessage != null) {
            return Center(child: Text(state.errorMessage!));
          }

          final data = state.data!;
          return RefreshIndicator(
            onRefresh: () => context.read<DashboardCubit>().load(
              context.read<SessionCubit>().state.user!,
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: <Widget>[
                _ProfilePanel(
                  user: user,
                ),
                if (bootstrapWarning != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4DA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(bootstrapWarning!),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Choose a mission',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap a category, speak the English word, and keep the rocket in the sky.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 18),
                ...data.categories.map(
                  (LearningCategory category) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _CategoryCard(category: category),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Achievements',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (BuildContext context, int index) {
                      return _AchievementCard(
                        achievement: data.achievements[index],
                      );
                    },
                    separatorBuilder:
                        (BuildContext context, int index) =>
                            const SizedBox(width: 12),
                    itemCount: data.achievements.length,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.user});

  final SessionUser user;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1B2432), Color(0xFF33415C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: const Text('🧠', style: TextStyle(fontSize: 30)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Welcome back, ${user.displayName}',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      user.isGuest
                          ? user.supportsCloudSync
                                ? 'Guest pilot mode • synced'
                                : 'Guest pilot mode • local only'
                          : 'Synced profile mode',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              _StatBadge(label: 'XP', value: '${user.totalXp}'),
              const SizedBox(width: 10),
              _StatBadge(label: 'Streak', value: '${user.streakDays} days'),
              const SizedBox(width: 10),
              const _StatBadge(label: 'Lives', value: '3 hearts'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category});

  final LearningCategory category;

  @override
  Widget build(BuildContext context) {
    final accent = parseHexColor(category.accentHex);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () => context.push('/game/${category.id}'),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 20,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: <Widget>[
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    category.emoji,
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(categoryIcon(category.iconName), color: accent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              category.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        category.subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: category.masteryPercent,
                          minHeight: 10,
                          color: accent,
                          backgroundColor: const Color(0xFFF1ECE2),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(category.masteryPercent * 100).round()}% mastery • ${category.totalWords} challenge words',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: achievement.unlocked ? const Color(0xFFE8F9E7) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF0E7D7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(achievement.emoji, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 10),
          Text(
            achievement.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            achievement.description,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: achievement.progress.clamp(0, 1),
              minHeight: 8,
              color: achievement.unlocked
                  ? const Color(0xFF57C84D)
                  : const Color(0xFFFFB703),
              backgroundColor: const Color(0xFFF0E7D7),
            ),
          ),
        ],
      ),
    );
  }
}
