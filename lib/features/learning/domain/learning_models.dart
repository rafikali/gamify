// ── Experience Level System ─────────────────────────────────────────────────
enum ExperienceLevel {
  beginner('Beginner', '🌱', 'Learning the basics'),
  intermediate('Intermediate', '🔥', 'Building confidence'),
  pro('Pro', '⚡', 'Master of words');

  const ExperienceLevel(this.title, this.emoji, this.subtitle);
  final String title;
  final String emoji;
  final String subtitle;

  /// Round timer in seconds.
  int get roundSeconds => switch (this) {
    beginner => 12,
    intermediate => 8,
    pro => 5,
  };

  /// Starting lives per game session.
  int get startingLives => switch (this) {
    beginner => 5,
    intermediate => 3,
    pro => 2,
  };

  /// XP multiplier applied to base score.
  double get xpMultiplier => switch (this) {
    beginner => 1.0,
    intermediate => 1.5,
    pro => 2.0,
  };

  /// Maximum word difficulty served at this level (1 = easy, 2 = medium, 3 = hard).
  int get maxWordDifficulty => switch (this) {
    beginner => 1,
    intermediate => 2,
    pro => 3,
  };

  /// Whether pronunciation hints are shown automatically.
  bool get showHints => switch (this) {
    beginner => true,
    intermediate => false,
    pro => false,
  };

  /// Whether the word name is displayed during gameplay.
  /// Intermediate and Pro only show the emoji/image.
  bool get showWordName => switch (this) {
    beginner => true,
    intermediate => false,
    pro => false,
  };

  /// Words per game session.
  int get wordsPerSession => switch (this) {
    beginner => 8,
    intermediate => 10,
    pro => 12,
  };

  /// The next level, or null if already at max.
  ExperienceLevel? get next => switch (this) {
    beginner => intermediate,
    intermediate => pro,
    pro => null,
  };

  /// Colors for UI gradient.
  List<int> get gradientHex => switch (this) {
    beginner => const <int>[0xFF80ED99, 0xFF4CC9F0],
    intermediate => const <int>[0xFFFFD166, 0xFFF78C6B],
    pro => const <int>[0xFFEF476F, 0xFF7B6FD4],
  };
}

/// Thresholds for auto-promoting to the next experience level.
class LevelUpRequirements {
  const LevelUpRequirements._();

  /// Returns true if the user qualifies for a level-up from their current level.
  static bool qualifies({
    required ExperienceLevel currentLevel,
    required int gamesPlayed,
    required int wordsLearned,
    required int totalXp,
  }) {
    return switch (currentLevel) {
      ExperienceLevel.beginner =>
        gamesPlayed >= 8 && wordsLearned >= 40 && totalXp >= 400,
      ExperienceLevel.intermediate =>
        gamesPlayed >= 25 && wordsLearned >= 150 && totalXp >= 1800,
      ExperienceLevel.pro => false, // already max
    };
  }

  /// Returns progress (0.0–1.0) toward next level-up.
  static double progress({
    required ExperienceLevel currentLevel,
    required int gamesPlayed,
    required int wordsLearned,
    required int totalXp,
  }) {
    final (int reqGames, int reqWords, int reqXp) = switch (currentLevel) {
      ExperienceLevel.beginner => (8, 40, 400),
      ExperienceLevel.intermediate => (25, 150, 1800),
      ExperienceLevel.pro => (1, 1, 1), // already max
    };
    if (currentLevel == ExperienceLevel.pro) return 1.0;

    final gameProgress = (gamesPlayed / reqGames).clamp(0.0, 1.0);
    final wordProgress = (wordsLearned / reqWords).clamp(0.0, 1.0);
    final xpProgress = (totalXp / reqXp).clamp(0.0, 1.0);
    return (gameProgress + wordProgress + xpProgress) / 3.0;
  }
}

enum GameType {
  rocketRush('Rocket Rush', '🚀', 'Say words before they crash!'),
  bubblePop('Bubble Pop', '🫧', 'Pop rising bubbles with your voice!'),
  spellCast('Spell Cast', '✨', 'Cast spells by speaking the word!'),
  speedBlitz('Speed Blitz', '⚡', 'Rapid-fire voice challenge!'),
  meteorStorm('Meteor Storm', '☄️', 'Survive the fiery meteor barrage!'),
  crystalCave('Crystal Cave', '💎', 'Shatter crystals with your voice!'),
  bossBattle('Boss Battle', '🐉', 'Defeat the dragon with words!'),
  rhythmRush('Rhythm Rush', '🎵', 'Ride the beat and speak on time!');

  const GameType(this.title, this.emoji, this.subtitle);
  final String title;
  final String emoji;
  final String subtitle;
}

class LearningCategory {
  const LearningCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.accentHex,
    required this.emoji,
    required this.totalWords,
    required this.masteryPercent,
    this.imageUrl,
  });

  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final String accentHex;
  final String emoji;
  final int totalWords;
  final double masteryPercent;
  final String? imageUrl;
}

class Achievement {
  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.progress,
    required this.unlocked,
    required this.emoji,
  });

  final String id;
  final String title;
  final String description;
  final double progress;
  final bool unlocked;
  final String emoji;
}

class DashboardData {
  const DashboardData({
    required this.categories,
    required this.achievements,
    required this.weeklyXp,
  });

  final List<LearningCategory> categories;
  final List<Achievement> achievements;
  final List<int> weeklyXp;
}

class WordChallenge {
  const WordChallenge({
    required this.id,
    required this.categoryId,
    required this.answer,
    required this.emoji,
    required this.funFact,
    required this.pronunciationHint,
    this.difficulty = 1,
    this.imageUrl,
  });

  final String id;
  final String categoryId;
  final String answer;
  final String emoji;
  final String funFact;
  final String pronunciationHint;
  /// 1 = easy, 2 = medium, 3 = hard.
  final int difficulty;
  final String? imageUrl;
}

class GameSessionBundle {
  const GameSessionBundle({required this.category, required this.challenges});

  final LearningCategory category;
  final List<WordChallenge> challenges;
}

class GameSummary {
  const GameSummary({
    required this.categoryId,
    required this.score,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.clearedAll,
    required this.elapsedSeconds,
  });

  final String categoryId;
  final int score;
  final int correctAnswers;
  final int wrongAnswers;
  final bool clearedAll;
  final int elapsedSeconds;
}
