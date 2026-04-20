import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/bootstrap/app_bootstrap.dart';
import '../features/learning/presentation/game_page.dart';
import '../features/learning/presentation/home_page.dart';
import '../features/learning/presentation/profile_page.dart';
import '../features/learning/presentation/progress_page.dart';
import '../features/learning/presentation/result_page.dart';
import '../features/session/presentation/auth_gate_page.dart';
import '../features/session/presentation/onboarding_page.dart';
import '../features/session/presentation/splash_page.dart';
import '../features/session/presentation/session_cubit.dart';

GoRouter createLearnifyRouter(
  SessionCubit sessionCubit,
  AppBootstrapServices services,
) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(sessionCubit.stream),
    redirect: (BuildContext context, GoRouterState state) {
      final sessionState = sessionCubit.state;
      final isReady = sessionState.status != SessionStatus.checking;
      final isSignedIn = sessionState.user != null;
      final path = state.uri.path;

      if (!isReady) {
        return path == '/' ? null : '/';
      }

      final protectedPaths = <String>[
        '/home',
        '/progress',
        '/profile',
        '/result',
      ];

      final requiresSession =
          protectedPaths.contains(path) || path.startsWith('/game');

      if (!isSignedIn && requiresSession) {
        return '/auth';
      }

      if (isSignedIn && (path == '/onboarding' || path == '/auth')) {
        return '/home';
      }

      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) {
          return const SplashPage();
        },
      ),
      GoRoute(
        path: '/onboarding',
        builder: (BuildContext context, GoRouterState state) {
          return const OnboardingPage();
        },
      ),
      GoRoute(
        path: '/auth',
        builder: (BuildContext context, GoRouterState state) {
          return AuthGatePage(
            backendConfigured: services.config.isSupabaseConfigured,
            bootstrapWarning: services.bootstrapWarning,
          );
        },
      ),
      GoRoute(
        path: '/home',
        builder: (BuildContext context, GoRouterState state) {
          return HomePage(bootstrapWarning: services.bootstrapWarning);
        },
      ),
      GoRoute(
        path: '/game/:categoryId',
        builder: (BuildContext context, GoRouterState state) {
          return GamePage(
            categoryId: state.pathParameters['categoryId'] ?? '',
            speechRecognitionService: services.speechRecognitionService,
          );
        },
      ),
      GoRoute(
        path: '/progress',
        builder: (BuildContext context, GoRouterState state) {
          return const ProgressPage();
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (BuildContext context, GoRouterState state) {
          return const ProfilePage();
        },
      ),
      GoRoute(
        path: '/result',
        builder: (BuildContext context, GoRouterState state) {
          final score =
              int.tryParse(state.uri.queryParameters['score'] ?? '') ?? 0;
          final accuracy =
              int.tryParse(state.uri.queryParameters['accuracy'] ?? '') ?? 0;
          final correctAnswers =
              int.tryParse(state.uri.queryParameters['correct'] ?? '') ?? 0;
          final mistakes =
              int.tryParse(state.uri.queryParameters['mistakes'] ?? '') ?? 0;
          final categoryId = state.uri.queryParameters['category'] ?? 'fruits';
          return ResultPage(
            score: score,
            accuracy: accuracy,
            correctAnswers: correctAnswers,
            mistakes: mistakes,
            categoryId: categoryId,
          );
        },
      ),
    ],
  );
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((dynamic _) {
      notifyListeners();
    });
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
