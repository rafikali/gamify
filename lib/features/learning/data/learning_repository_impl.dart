import 'package:cloud_firestore/cloud_firestore.dart';

import '../../session/domain/session_user.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';
import 'mock_learning_seed.dart';

class LearningRepositoryImpl implements LearningRepository {
  const LearningRepositoryImpl({required this.firestore});

  final FirebaseFirestore? firestore;

  @override
  Future<DashboardData> fetchDashboard(SessionUser user) async {
    if (firestore == null || user.isGuest) {
      return const DashboardData(
        categories: MockLearningSeed.categories,
        achievements: MockLearningSeed.achievements,
      );
    }

    try {
      final categoryRows = await firestore!
          .collection('categories')
          .orderBy('sort_order')
          .get();

      final categories = categoryRows.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> row) =>
                LearningCategory(
                  id: row.id,
                  title: row.data()['title'] as String? ?? 'Lesson',
                  subtitle:
                      row.data()['description'] as String? ?? 'Voice challenge',
                  iconName: row.data()['icon_name'] as String? ?? 'school',
                  accentHex: row.data()['accent_hex'] as String? ?? '#57C84D',
                  emoji: row.data()['emoji'] as String? ?? '🚀',
                  totalWords: _intValue(row.data()['total_words'], fallback: 3),
                  masteryPercent:
                      (row.data()['mastery_percent'] as num?)?.toDouble() ??
                      0.0,
                  imageUrl: row.data()['image_url'] as String?,
                ),
          )
          .toList();

      List<Achievement> achievements = const <Achievement>[];
      try {
        final achievementRows = await firestore!
            .collection('profiles')
            .doc(user.id)
            .collection('achievements')
            .get();

        achievements = achievementRows.docs
            .map(
              (QueryDocumentSnapshot<Map<String, dynamic>> row) => Achievement(
                id: row.id,
                title: row.data()['title'] as String? ?? 'Achievement',
                description: row.data()['description'] as String? ?? '',
                progress: (row.data()['progress'] as num?)?.toDouble() ?? 0,
                unlocked: row.data()['unlocked'] as bool? ?? false,
                emoji: row.data()['emoji'] as String? ?? '🏁',
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

    if (firestore == null || user.isGuest) {
      return GameSessionBundle(
        category: fallbackCategory,
        challenges: fallbackWords,
      );
    }

    try {
      final wordRows = await firestore!
          .collection('words')
          .where('category_id', isEqualTo: categoryId)
          .limit(12)
          .get();

      final words = wordRows.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> row) => WordChallenge(
              id: row.id,
              categoryId: row.data()['category_id'] as String? ?? categoryId,
              answer: row.data()['answer'] as String? ?? 'word',
              emoji: row.data()['emoji'] as String? ?? '✨',
              funFact: row.data()['fun_fact'] as String? ?? 'Keep going.',
              pronunciationHint:
                  row.data()['pronunciation_hint'] as String? ??
                  'Say it clearly',
              imageUrl: row.data()['image_url'] as String?,
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

    if (firestore == null || user.isGuest) {
      return updatedUser;
    }

    try {
      final profileReference = firestore!.collection('profiles').doc(user.id);

      await profileReference.set(<String, dynamic>{
        'id': user.id,
        'display_name': user.displayName,
        'streak_days': updatedUser.streakDays,
        'total_xp': updatedUser.totalXp,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await profileReference.collection('game_sessions').add(<String, dynamic>{
        'category_id': summary.categoryId,
        'score': summary.score,
        'correct_answers': summary.correctAnswers,
        'wrong_answers': summary.wrongAnswers,
        'cleared_all': summary.clearedAll,
        'elapsed_seconds': summary.elapsedSeconds,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      return updatedUser;
    }

    return updatedUser;
  }

  int _intValue(Object? value, {required int fallback}) {
    return (value as num?)?.toInt() ?? fallback;
  }
}
