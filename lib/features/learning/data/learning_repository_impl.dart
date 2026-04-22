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
    if (_shouldUseFallback(user)) {
      return _fallbackDashboard();
    }

    try {
      final profileRef = firestore!.collection('profiles').doc(user.id);
      final now = DateTime.now();
      final weekStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6));

      final results = await Future.wait<Object>(<Future<Object>>[
        firestore!.collection('categories').orderBy('sort_order').get(),
        profileRef.collection('category_progress').get(),
        profileRef
            .collection('game_sessions')
            .where(
              'created_at',
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart),
            )
            .get(),
      ]);

      final categoryRows = results[0] as QuerySnapshot<Map<String, dynamic>>;
      final progressRows = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final sessionRows = results[2] as QuerySnapshot<Map<String, dynamic>>;

      final progressByCategory = <String, Map<String, dynamic>>{
        for (final doc in progressRows.docs) doc.id: doc.data(),
      };

      final fallbackCategories = MockLearningSeed.categories;
      final categories = (categoryRows.docs.isEmpty
              ? fallbackCategories
              : categoryRows.docs.map(
                  (QueryDocumentSnapshot<Map<String, dynamic>> row) =>
                      _mapCategoryRow(row, progressByCategory[row.id]),
                ))
          .toList();

      if (categoryRows.docs.isEmpty) {
        for (var i = 0; i < categories.length; i++) {
          final category = categories[i];
          final progress = progressByCategory[category.id];
          if (progress == null) {
            continue;
          }

          categories[i] = LearningCategory(
            id: category.id,
            title: category.title,
            subtitle: category.subtitle,
            iconName: category.iconName,
            accentHex: category.accentHex,
            emoji: category.emoji,
            totalWords: category.totalWords,
            masteryPercent:
                (progress['mastery_percent'] as num?)?.toDouble() ??
                category.masteryPercent,
            imageUrl: category.imageUrl,
          );
        }
      }

      return DashboardData(
        categories: categories,
        achievements: _buildAchievements(user),
        weeklyXp: _buildWeeklyXp(sessionRows.docs, weekStart),
      );
    } catch (_) {
      return _fallbackDashboard();
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

    if (_shouldUseFallback(user)) {
      return GameSessionBundle(
        category: fallbackCategory,
        challenges: fallbackWords,
      );
    }

    try {
      final results = await Future.wait<Object>(<Future<Object>>[
        firestore!.collection('categories').doc(categoryId).get(),
        firestore!
            .collection('words')
            .where('category_id', isEqualTo: categoryId)
            .limit(12)
            .get(),
      ]);

      final categoryRow = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final wordRows = results[1] as QuerySnapshot<Map<String, dynamic>>;
      final category = categoryRow.exists
          ? _mapCategoryDocument(categoryRow)
          : fallbackCategory;

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
        category: category,
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
    final currentStreak = summary.clearedAll ? user.streakDays + 1 : user.streakDays;
    final updatedUser = user.copyWith(
      totalXp: user.totalXp + gainedXp,
      streakDays: currentStreak,
      bestStreak: _maxInt(user.bestStreak, currentStreak),
      wordsLearned: user.wordsLearned + summary.correctAnswers,
      gamesPlayed: user.gamesPlayed + 1,
      lastCategoryId: summary.categoryId,
    );

    if (_shouldUseFallback(user)) {
      return updatedUser;
    }

    try {
      final profileReference = firestore!.collection('profiles').doc(user.id);
      final categoryProgressReference = profileReference
          .collection('category_progress')
          .doc(summary.categoryId);
      final categoryProgressSnapshot = await categoryProgressReference.get();
      final existingProgress = categoryProgressSnapshot.data();
      final totalCorrect =
          _intValue(existingProgress?['correct_answers'], fallback: 0) +
          summary.correctAnswers;
      final totalWrong =
          _intValue(existingProgress?['wrong_answers'], fallback: 0) +
          summary.wrongAnswers;
      final totalAttempts = totalCorrect + totalWrong;

      final batch = firestore!.batch();
      batch.set(profileReference, <String, dynamic>{
        'display_name': user.displayName,
        'streak_days': updatedUser.streakDays,
        'best_streak': updatedUser.bestStreak,
        'total_xp': updatedUser.totalXp,
        'words_learned': updatedUser.wordsLearned,
        'games_played': updatedUser.gamesPlayed,
        'last_category_id': summary.categoryId,
        'last_played_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(categoryProgressReference, <String, dynamic>{
        'category_id': summary.categoryId,
        'times_played':
            _intValue(existingProgress?['times_played'], fallback: 0) + 1,
        'correct_answers': totalCorrect,
        'wrong_answers': totalWrong,
        'cleared_count':
            _intValue(existingProgress?['cleared_count'], fallback: 0) +
            (summary.clearedAll ? 1 : 0),
        'best_score': _maxInt(
          _intValue(existingProgress?['best_score'], fallback: 0),
          summary.score,
        ),
        'last_score': summary.score,
        'mastery_percent': totalAttempts == 0 ? 0.0 : totalCorrect / totalAttempts,
        'last_played_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(profileReference.collection('game_sessions').doc(), <String, dynamic>{
        'category_id': summary.categoryId,
        'score': summary.score,
        'correct_answers': summary.correctAnswers,
        'wrong_answers': summary.wrongAnswers,
        'cleared_all': summary.clearedAll,
        'elapsed_seconds': summary.elapsedSeconds,
        'created_at': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (error) {
      // Log so we can diagnose silent save failures.
      // ignore: avoid_print
      print('[completeGame] Firebase write failed: $error');
      return updatedUser;
    }

    return updatedUser;
  }

  bool _shouldUseFallback(SessionUser user) {
    return firestore == null || user.isLocalOnlyGuest;
  }

  DashboardData _fallbackDashboard() {
    return const DashboardData(
      categories: MockLearningSeed.categories,
      achievements: MockLearningSeed.achievements,
      weeklyXp: MockLearningSeed.weeklyXp,
    );
  }

  LearningCategory _mapCategoryRow(
    QueryDocumentSnapshot<Map<String, dynamic>> row,
    Map<String, dynamic>? progress,
  ) {
    final data = row.data();
    return LearningCategory(
      id: row.id,
      title: data['title'] as String? ?? 'Lesson',
      subtitle: data['description'] as String? ?? 'Voice challenge',
      iconName: data['icon_name'] as String? ?? 'school',
      accentHex: data['accent_hex'] as String? ?? '#57C84D',
      emoji: data['emoji'] as String? ?? '🚀',
      totalWords: _intValue(data['total_words'], fallback: 3),
      masteryPercent:
          (progress?['mastery_percent'] as num?)?.toDouble() ??
          (data['mastery_percent'] as num?)?.toDouble() ??
          0.0,
      imageUrl: data['image_url'] as String?,
    );
  }

  LearningCategory _mapCategoryDocument(
    DocumentSnapshot<Map<String, dynamic>> row,
  ) {
    final data = row.data() ?? const <String, dynamic>{};
    return LearningCategory(
      id: row.id,
      title: data['title'] as String? ?? 'Lesson',
      subtitle: data['description'] as String? ?? 'Voice challenge',
      iconName: data['icon_name'] as String? ?? 'school',
      accentHex: data['accent_hex'] as String? ?? '#57C84D',
      emoji: data['emoji'] as String? ?? '🚀',
      totalWords: _intValue(data['total_words'], fallback: 3),
      masteryPercent: (data['mastery_percent'] as num?)?.toDouble() ?? 0.0,
      imageUrl: data['image_url'] as String?,
    );
  }

  List<Achievement> _buildAchievements(SessionUser user) {
    return <Achievement>[
      Achievement(
        id: 'first-launch',
        title: 'First Launch',
        description: 'Finish one category mission.',
        progress: user.gamesPlayed > 0 ? 1.0 : 0.0,
        unlocked: user.gamesPlayed > 0,
        emoji: '🚀',
      ),
      Achievement(
        id: 'sharp-ears',
        title: 'Sharp Ears',
        description: 'Clear 10 objects without missing.',
        progress: (user.wordsLearned / 10).clamp(0.0, 1.0),
        unlocked: user.wordsLearned >= 10,
        emoji: '🎧',
      ),
      Achievement(
        id: 'streak-pilot',
        title: 'Streak Pilot',
        description: 'Keep a 7 day learning streak.',
        progress: (user.bestStreak / 7).clamp(0.0, 1.0),
        unlocked: user.bestStreak >= 7,
        emoji: '🔥',
      ),
    ];
  }

  List<int> _buildWeeklyXp(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sessions,
    DateTime weekStart,
  ) {
    final buckets = List<int>.filled(7, 0);
    for (final session in sessions) {
      final timestamp = session.data()['created_at'];
      if (timestamp is! Timestamp) {
        continue;
      }

      final playedAt = timestamp.toDate();
      final index = playedAt
          .difference(DateTime(weekStart.year, weekStart.month, weekStart.day))
          .inDays;
      if (index < 0 || index >= buckets.length) {
        continue;
      }

      buckets[index] += _intValue(session.data()['score'], fallback: 0);
    }
    return buckets;
  }

  int _intValue(Object? value, {required int fallback}) {
    return (value as num?)?.toInt() ?? fallback;
  }

  int _maxInt(int a, int b) => a > b ? a : b;
}
