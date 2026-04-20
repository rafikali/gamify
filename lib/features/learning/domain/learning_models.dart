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
  const DashboardData({required this.categories, required this.achievements});

  final List<LearningCategory> categories;
  final List<Achievement> achievements;
}

class WordChallenge {
  const WordChallenge({
    required this.id,
    required this.categoryId,
    required this.answer,
    required this.emoji,
    required this.funFact,
    required this.pronunciationHint,
    this.imageUrl,
  });

  final String id;
  final String categoryId;
  final String answer;
  final String emoji;
  final String funFact;
  final String pronunciationHint;
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
