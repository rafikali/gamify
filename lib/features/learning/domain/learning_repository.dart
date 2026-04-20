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
}
