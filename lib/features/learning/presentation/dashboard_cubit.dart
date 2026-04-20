import 'package:flutter_bloc/flutter_bloc.dart';

import '../../session/domain/session_user.dart';
import '../domain/learning_models.dart';
import '../domain/learning_repository.dart';

class DashboardState {
  const DashboardState({required this.loading, this.data, this.errorMessage});

  const DashboardState.initial() : this(loading: true);

  final bool loading;
  final DashboardData? data;
  final String? errorMessage;

  DashboardState copyWith({
    bool? loading,
    DashboardData? data,
    String? errorMessage,
  }) {
    return DashboardState(
      loading: loading ?? this.loading,
      data: data ?? this.data,
      errorMessage: errorMessage,
    );
  }
}

class DashboardCubit extends Cubit<DashboardState> {
  DashboardCubit({required LearningRepository repository})
    : _repository = repository,
      super(const DashboardState.initial());

  final LearningRepository _repository;

  Future<void> load(SessionUser user) async {
    emit(state.copyWith(loading: true, errorMessage: null));

    try {
      final data = await _repository.fetchDashboard(user);
      emit(DashboardState(loading: false, data: data));
    } catch (error) {
      emit(
        DashboardState(
          loading: false,
          errorMessage: 'Unable to load the learning map.\n$error',
        ),
      );
    }
  }
}
