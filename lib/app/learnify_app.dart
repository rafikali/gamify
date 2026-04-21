import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/bootstrap/app_bootstrap.dart';
import '../features/learning/domain/learning_repository.dart';
import '../features/session/domain/session_repository.dart';
import '../features/session/presentation/session_cubit.dart';
import 'learnify_router.dart';
import 'learnify_theme.dart';

class LearnifyApp extends StatefulWidget {
  const LearnifyApp({super.key, required this.services});

  final AppBootstrapServices services;

  @override
  State<LearnifyApp> createState() => _LearnifyAppState();
}

class _LearnifyAppState extends State<LearnifyApp> {
  late final SessionCubit _sessionCubit;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _sessionCubit = SessionCubit(
      sessionRepository: widget.services.sessionRepository,
      backendConfigured: widget.services.config.isFirebaseConfigured,
      bootstrapWarning: widget.services.bootstrapWarning,
    )..restoreSession();
    _router = createLearnifyRouter(_sessionCubit, widget.services);
  }

  @override
  void dispose() {
    _router.dispose();
    _sessionCubit.close();
    widget.services.speechRecognitionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: <RepositoryProvider<Object>>[
        RepositoryProvider<SessionRepository>.value(
          value: widget.services.sessionRepository,
        ),
        RepositoryProvider<LearningRepository>.value(
          value: widget.services.learningRepository,
        ),
      ],
      child: BlocProvider<SessionCubit>.value(
        value: _sessionCubit,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          title: 'Learnify',
          theme: LearnifyTheme.build(),
          routerConfig: _router,
        ),
      ),
    );
  }
}
