import '../../session/domain/session_user.dart';
import 'learning_models.dart';

abstract class LearningRepository {
  Future<DashboardData> fetchDashboard(SessionUser user);

  Future<GameSessionBundle> startGame({
    required SessionUser user,
    required String categoryId,
  });

  Future<SessionUser> completeGame({
    required SessionUser user,
    required GameSummary summary,
  });

  /// Promotes user to the next experience level if they qualify.
  /// Returns updated user with new level, or same user if already max.
  Future<SessionUser> levelUp({required SessionUser user});
}
