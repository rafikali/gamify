class SessionUser {
  static const String localGuestId = 'guest';

  const SessionUser({
    required this.id,
    required this.displayName,
    required this.streakDays,
    required this.bestStreak,
    required this.totalXp,
    required this.wordsLearned,
    required this.gamesPlayed,
    required this.lastCategoryId,
    required this.isGuest,
  });

  const SessionUser.guest()
    : id = localGuestId,
      displayName = 'Cadet Learner',
      streakDays = 0,
      bestStreak = 0,
      totalXp = 0,
      wordsLearned = 0,
      gamesPlayed = 0,
      lastCategoryId = null,
      isGuest = true;

  final String id;
  final String displayName;
  final int streakDays;
  final int bestStreak;
  final int totalXp;
  final int wordsLearned;
  final int gamesPlayed;
  final String? lastCategoryId;
  final bool isGuest;

  bool get isLocalOnlyGuest => isGuest && id == localGuestId;
  bool get supportsCloudSync => !isLocalOnlyGuest;

  SessionUser copyWith({
    String? id,
    String? displayName,
    int? streakDays,
    int? bestStreak,
    int? totalXp,
    int? wordsLearned,
    int? gamesPlayed,
    String? lastCategoryId,
    bool? isGuest,
  }) {
    return SessionUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      streakDays: streakDays ?? this.streakDays,
      bestStreak: bestStreak ?? this.bestStreak,
      totalXp: totalXp ?? this.totalXp,
      wordsLearned: wordsLearned ?? this.wordsLearned,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      lastCategoryId: lastCategoryId ?? this.lastCategoryId,
      isGuest: isGuest ?? this.isGuest,
    );
  }
}
