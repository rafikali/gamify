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
    this.lastPlayedAt,
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
      isGuest = true,
      lastPlayedAt = null;

  final String id;
  final String displayName;
  final int streakDays;
  final int bestStreak;
  final int totalXp;
  final int wordsLearned;
  final int gamesPlayed;
  final String? lastCategoryId;
  final bool isGuest;
  final DateTime? lastPlayedAt;

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
    DateTime? lastPlayedAt,
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
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SessionUser &&
        other.id == id &&
        other.displayName == displayName &&
        other.streakDays == streakDays &&
        other.bestStreak == bestStreak &&
        other.totalXp == totalXp &&
        other.wordsLearned == wordsLearned &&
        other.gamesPlayed == gamesPlayed &&
        other.lastCategoryId == lastCategoryId &&
        other.isGuest == isGuest &&
        other.lastPlayedAt == lastPlayedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    streakDays,
    bestStreak,
    totalXp,
    wordsLearned,
    gamesPlayed,
    lastCategoryId,
    isGuest,
    lastPlayedAt,
  );
}
