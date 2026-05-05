import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'session_cubit.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final StreamSubscription<SessionState> _sessionSub;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();

    // Wait for session restore to finish (status leaves `checking`),
    // but show the splash for at least 1.5s so the animation plays.
    final minDelay = Future<void>.delayed(const Duration(milliseconds: 1500));
    final cubit = context.read<SessionCubit>();

    _sessionSub = cubit.stream.listen((SessionState state) {
      if (state.status != SessionStatus.checking) {
        _sessionSub.cancel();
        minDelay.then((_) => _navigate());
      }
    });

    // If the session was already restored synchronously (e.g. no Firebase),
    // the stream won't emit — use a fallback.
    if (cubit.state.status != SessionStatus.checking) {
      _sessionSub.cancel();
      minDelay.then((_) => _navigate());
    }
  }

  void _navigate() {
    if (!mounted || _navigated) return;
    _navigated = true;
    final hasSession = context.read<SessionCubit>().state.user != null;
    context.go(hasSession ? '/home' : '/onboarding');
  }

  @override
  void dispose() {
    _sessionSub.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFFFFD166),
              Color(0xFFFFF9F2),
              Color(0xFF4CC9F0),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ScaleTransition(
                scale: CurvedAnimation(
                  parent: _controller,
                  curve: Curves.elasticOut,
                ),
                child: RotationTransition(
                  turns: Tween<double>(begin: -0.15, end: 0).animate(
                    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
                  ),
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 28,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.rocket_launch_rounded,
                      size: 64,
                      color: Color(0xFF4CC9F0),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Word Rocket',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 16),
              Container(
                width: 96,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: <Color>[
                      Color(0xFFFFD166),
                      Color(0xFF80ED99),
                      Color(0xFF4CC9F0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
