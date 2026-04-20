class SessionUser {
  const SessionUser({
    required this.id,
    required this.displayName,
    required this.streakDays,
    required this.totalXp,
    required this.isGuest,
  });

  const SessionUser.guest()
    : id = 'guest',
      displayName = 'Cadet Learner',
      streakDays = 1,
      totalXp = 0,
      isGuest = true;

  final String id;
  final String displayName;
  final int streakDays;
  final int totalXp;
  final bool isGuest;

  SessionUser copyWith({
    String? id,
    String? displayName,
    int? streakDays,
    int? totalXp,
    bool? isGuest,
  }) {
    return SessionUser(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      streakDays: streakDays ?? this.streakDays,
      totalXp: totalXp ?? this.totalXp,
      isGuest: isGuest ?? this.isGuest,
    );
  }
}
