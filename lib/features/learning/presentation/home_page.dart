import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/icon_mapper.dart';
import '../../session/domain/session_user.dart';
import '../../session/presentation/session_cubit.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'bottom_nav_bar.dart';
import 'dashboard_cubit.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.bootstrapWarning});

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
      child: _HomeView(
        user: user,
        bootstrapWarning: bootstrapWarning,
      ),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({required this.user, required this.bootstrapWarning});

  final SessionUser user;
  final String? bootstrapWarning;

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
          if (state.errorMessage != null) {
            return Center(child: Text(state.errorMessage!));
          }

          final data = state.data!;
          final continueCategory = data.categories.firstWhere(
            (LearningCategory category) => category.id == user.lastCategoryId,
            orElse: () => data.categories.first,
          );

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Hey 👋',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ready to learn, ${user.displayName}?',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    _ScorePill(
                      icon: Icons.local_fire_department_rounded,
                      color: const Color(0xFFEF476F),
                      value: '${user.streakDays}',
                    ),
                    const SizedBox(width: 12),
                    _ScorePill(
                      icon: Icons.monetization_on_rounded,
                      color: const Color(0xFFFFD166),
                      value: '${user.totalXp}',
                    ),
                  ],
                ),
                if (bootstrapWarning != null) ...<Widget>[
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0x14FFD166),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(bootstrapWarning!),
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF4CC9F0), Color(0xFF80ED99)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              "Today's Challenge 🎯",
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Complete 10 words without mistake',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(
                          Icons.monetization_on_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => context.push('/game/${continueCategory.id}'),
                  child: Ink(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFFFFD166), Color(0xFFF78C6B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(
                                  Icons.local_fire_department_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${user.streakDays}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Text(
                          'Continue Learning',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Last practiced: ${continueCategory.title} ${continueCategory.emoji}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            const Text(
                              "Today's goal",
                              style: TextStyle(color: Colors.white),
                            ),
                            Text(
                              '${(continueCategory.totalWords * 0.7).round()}/${continueCategory.totalWords} words',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: continueCategory.masteryPercent,
                            minHeight: 10,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.28,
                            ),
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'Continue',
                            style: TextStyle(
                              color: Color(0xFF2D2D2D),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Choose a category',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.categories.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.9,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final category = data.categories[index];
                    return _CategoryTile(category: category);
                  },
                ),
              ],
            ),
          );
        },
      ),
      ),
      bottomNavigationBar: const BottomNavBar(activeTab: 'home'),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({
    required this.icon,
    required this.color,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category});

  final LearningCategory category;

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(category.accentHex);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => context.push('/game/${category.id}'),
      child: Ink(
        padding: const EdgeInsets.all(20),
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
          border: Border(top: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(categoryIcon(category.iconName), color: color),
            ),
            const SizedBox(height: 14),
            Text(
              category.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${category.totalWords} words',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text('Progress', style: Theme.of(context).textTheme.bodySmall),
                Text(
                  '${(category.masteryPercent * 100).round()}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: category.masteryPercent,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
