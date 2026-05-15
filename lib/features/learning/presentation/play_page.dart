import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../session/presentation/session_cubit.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'bottom_nav_bar.dart';
import 'dashboard_cubit.dart';

class PlayPage extends StatelessWidget {
  const PlayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.select(
      (SessionCubit cubit) => cubit.state.user!,
    );

    return BlocProvider<DashboardCubit>(
      create: (BuildContext context) =>
          DashboardCubit(repository: context.read<LearningRepository>())
            ..load(user),
      child: const _PlayView(),
    );
  }
}

class _PlayView extends StatefulWidget {
  const _PlayView();

  @override
  State<_PlayView> createState() => _PlayViewState();
}

class _PlayViewState extends State<_PlayView> with TickerProviderStateMixin {
  String? _selectedCategoryId;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFF1A1030),
              Color(0xFF3D2B6B),
              Color(0xFF7B6FD4),
              Color(0xFF4CC9F0),
            ],
            stops: <double>[0.0, 0.35, 0.7, 1.0],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: BlocBuilder<DashboardCubit, DashboardState>(
            builder: (BuildContext context, DashboardState state) {
              if (state.loading) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              if (state.data == null || state.data!.categories.isEmpty) {
                return const Center(
                  child: Text(
                    'No categories available.',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final categories = state.data!.categories;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Text(
                      _selectedCategoryId == null
                          ? 'Pick a Category'
                          : 'Choose Your Game',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _selectedCategoryId == null
                          ? 'What do you want to practice?'
                          : 'Each mode tests your skills differently',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),

                  // Selected category chip (when a category is picked)
                  if (_selectedCategoryId != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _buildSelectedChip(categories),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Content
                  Expanded(
                    child: _selectedCategoryId == null
                        ? _buildCategoryGrid(categories)
                        : _buildGameTypeList(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: const BottomNavBar(activeTab: 'play'),
    );
  }

  Widget _buildSelectedChip(List<LearningCategory> categories) {
    final cat = categories.firstWhere(
      (LearningCategory c) => c.id == _selectedCategoryId,
      orElse: () => categories.first,
    );

    return GestureDetector(
      onTap: () => setState(() => _selectedCategoryId = null),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(cat.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              cat.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.close_rounded,
              color: Colors.white.withValues(alpha: 0.6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid(List<LearningCategory> categories) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 1.1,
      ),
      itemCount: categories.length,
      itemBuilder: (BuildContext context, int index) {
        final category = categories[index];
        return _CategoryCard(
          category: category,
          onTap: () => setState(() => _selectedCategoryId = category.id),
        );
      },
    );
  }

  Widget _buildGameTypeList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      itemCount: GameType.values.length,
      itemBuilder: (BuildContext context, int index) {
        final gameType = GameType.values[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _GameTypeCard(
            gameType: gameType,
            index: index,
            pulseController: _pulseController,
            onTap: () {
              context.push('/game/$_selectedCategoryId/${gameType.name}');
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Card
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final LearningCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _parseHex(category.accentHex);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              color.withValues(alpha: 0.3),
              color.withValues(alpha: 0.12),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(category.emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text(
              category.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${category.totalWords} words',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Game Type Card (reused from game_type_page)
// ─────────────────────────────────────────────────────────────────────────────

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
    <Color>[Color(0xFF4CC9F0), Color(0xFF7B6FD4)],
    <Color>[Color(0xFF80ED99), Color(0xFF4CC9F0)],
    <Color>[Color(0xFFA28AE5), Color(0xFFEF476F)],
    <Color>[Color(0xFFFFD166), Color(0xFFF78C6B)],
    <Color>[Color(0xFFEF476F), Color(0xFFFF6B35)],
    <Color>[Color(0xFF48BFE3), Color(0xFFA28AE5)],
    <Color>[Color(0xFFFF4444), Color(0xFFFF8800)],
    <Color>[Color(0xFF80ED99), Color(0xFFFFD166)],
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
    'Words fall from the sky — say them before they crash!',
    'Bubbles float up — pop them with your voice!',
    'Cast spells by speaking the enchantment!',
    'Rapid-fire voice challenge!',
    'Survive the fiery meteor barrage!',
    'Shatter crystals with your voice!',
    'Defeat the dragon with words!',
    'Ride the beat and speak on time!',
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
            final glowIntensity = 0.15 + widget.pulseController.value * 0.1;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors[0].withValues(alpha: glowIntensity),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  colors[0].withValues(alpha: 0.22),
                  colors[1].withValues(alpha: 0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colors[0].withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: <Widget>[
                // Icon
                AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (BuildContext context, Widget? child) {
                    return Container(
                      width: 56,
                      height: 56,
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
                        margin: const EdgeInsets.all(2.5),
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
                            child: Icon(icon, color: Colors.white, size: 26),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            widget.gameType.emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.gameType.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (widget.index >= 4)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: colors),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'PRO',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _descriptions[widget.index],
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: colors),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 24,
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
