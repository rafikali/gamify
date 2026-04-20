import 'package:supabase_flutter/supabase_flutter.dart';

import '../../session/domain/session_user.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'mock_learning_seed.dart';

class LearningRepositoryImpl implements LearningRepository {
  const LearningRepositoryImpl({required this.supabaseClient});

  final SupabaseClient? supabaseClient;

  @override
  Future<DashboardData> fetchDashboard(SessionUser user) async {
    if (supabaseClient == null || user.isGuest) {
      return const DashboardData(
        categories: MockLearningSeed.categories,
        achievements: MockLearningSeed.achievements,
      );
    }

    try {
      final categoryRows = await supabaseClient!
          .from('categories')
          .select(
            'id, title, description, icon_name, accent_hex, emoji, total_words, mastery_percent, image_url, sort_order',
          )
          .order('sort_order');

      final categories = (categoryRows as List<dynamic>)
          .map(
            (dynamic row) => LearningCategory(
              id: row['id'] as String,
              title: row['title'] as String? ?? 'Lesson',
              subtitle: row['description'] as String? ?? 'Voice challenge',
              iconName: row['icon_name'] as String? ?? 'school',
              accentHex: row['accent_hex'] as String? ?? '#57C84D',
              emoji: row['emoji'] as String? ?? '🚀',
              totalWords: (row['total_words'] as num?)?.toInt() ?? 3,
              masteryPercent:
                  (row['mastery_percent'] as num?)?.toDouble() ?? 0.0,
              imageUrl: row['image_url'] as String?,
            ),
          )
          .toList();

      List<Achievement> achievements = const <Achievement>[];
      try {
        final achievementRows = await supabaseClient!
            .from('achievements')
            .select('id, title, description, progress, unlocked, emoji')
            .eq('user_id', user.id);

        achievements = (achievementRows as List<dynamic>)
            .map(
              (dynamic row) => Achievement(
                id: row['id'] as String,
                title: row['title'] as String? ?? 'Achievement',
                description: row['description'] as String? ?? '',
                progress: (row['progress'] as num?)?.toDouble() ?? 0,
                unlocked: row['unlocked'] as bool? ?? false,
                emoji: row['emoji'] as String? ?? '🏁',
              ),
            )
            .toList();
      } catch (_) {
        achievements = const <Achievement>[];
      }

      return DashboardData(
        categories: categories.isEmpty
            ? MockLearningSeed.categories
            : categories,
        achievements: achievements.isEmpty
            ? MockLearningSeed.achievements
            : achievements,
      );
    } catch (_) {
      return const DashboardData(
        categories: MockLearningSeed.categories,
        achievements: MockLearningSeed.achievements,
      );
    }
  }

  @override
  Future<GameSessionBundle> startGame({
    required SessionUser user,
    required String categoryId,
  }) async {
    final fallbackCategory = MockLearningSeed.categories.firstWhere(
      (LearningCategory category) => category.id == categoryId,
      orElse: () => MockLearningSeed.categories.first,
    );
    final fallbackWords =
        MockLearningSeed.wordsByCategory[fallbackCategory.id] ??
        const <WordChallenge>[];

    if (supabaseClient == null || user.isGuest) {
      return GameSessionBundle(
        category: fallbackCategory,
        challenges: fallbackWords,
      );
    }

    try {
      final wordRows = await supabaseClient!
          .from('words')
          .select(
            'id, category_id, answer, emoji, fun_fact, pronunciation_hint, image_url',
          )
          .eq('category_id', categoryId)
          .limit(12);

      final words = (wordRows as List<dynamic>)
          .map(
            (dynamic row) => WordChallenge(
              id: row['id'] as String,
              categoryId: row['category_id'] as String? ?? categoryId,
              answer: row['answer'] as String? ?? 'word',
              emoji: row['emoji'] as String? ?? '✨',
              funFact: row['fun_fact'] as String? ?? 'Keep going.',
              pronunciationHint:
                  row['pronunciation_hint'] as String? ?? 'Say it clearly',
              imageUrl: row['image_url'] as String?,
            ),
          )
          .toList();

      return GameSessionBundle(
        category: fallbackCategory,
        challenges: words.isEmpty ? fallbackWords : words,
      );
    } catch (_) {
      return GameSessionBundle(
        category: fallbackCategory,
        challenges: fallbackWords,
      );
    }
  }

  @override
  Future<SessionUser> completeGame({
    required SessionUser user,
    required GameSummary summary,
  }) async {
    final gainedXp = summary.score;
    final updatedUser = user.copyWith(
      totalXp: user.totalXp + gainedXp,
      streakDays: summary.clearedAll ? user.streakDays + 1 : user.streakDays,
    );

    if (supabaseClient == null || user.isGuest) {
      return updatedUser;
    }

    try {
      await supabaseClient!.from('profiles').upsert(<String, dynamic>{
        'id': user.id,
        'display_name': user.displayName,
        'streak_days': updatedUser.streakDays,
        'total_xp': updatedUser.totalXp,
      });

      await supabaseClient!.from('game_sessions').insert(<String, dynamic>{
        'user_id': user.id,
        'category_id': summary.categoryId,
        'score': summary.score,
        'correct_answers': summary.correctAnswers,
        'wrong_answers': summary.wrongAnswers,
        'cleared_all': summary.clearedAll,
        'elapsed_seconds': summary.elapsedSeconds,
      });
    } catch (_) {
      return updatedUser;
    }

    return updatedUser;
  }
}
