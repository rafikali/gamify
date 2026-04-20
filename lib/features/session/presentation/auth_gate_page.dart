import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'session_cubit.dart';

class AuthGatePage extends StatefulWidget {
  const AuthGatePage({
    super.key,
    required this.backendConfigured,
    required this.bootstrapWarning,
  });

  final bool backendConfigured;
  final String? bootstrapWarning;

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: <BlocListener<SessionCubit, SessionState>>[
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState previous, SessionState current) =>
              previous.errorMessage != current.errorMessage &&
              current.errorMessage != null,
          listener: (BuildContext context, SessionState state) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          },
        ),
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState previous, SessionState current) =>
              previous.noticeMessage != current.noticeMessage &&
              current.noticeMessage != null,
          listener: (BuildContext context, SessionState state) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.noticeMessage!)));
          },
        ),
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState previous, SessionState current) =>
              previous.user != current.user && current.user != null,
          listener: (BuildContext context, SessionState state) {
            context.go('/home');
          },
        ),
      ],
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: <Color>[
                                Color(0xFF5B4BDB),
                                Color(0xFF7C68F6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.16,
                                      ),
                                      borderRadius: BorderRadius.circular(22),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Text(
                                      '🚀',
                                      style: TextStyle(fontSize: 32),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Text(
                                      'Speech missions',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              Text(
                                'Learnify',
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Sign in to sync categories, save game sessions, and keep your streak across devices.',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: const <Widget>[
                                  _HeroChip(label: 'Live auth'),
                                  _HeroChip(label: 'Saved streaks'),
                                  _HeroChip(label: 'Game history'),
                                  _HeroChip(label: 'Guest fallback'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (widget.bootstrapWarning != null) ...<Widget>[
                          _InfoCard(
                            tone: const Color(0xFFFFF3D6),
                            border: const Color(0xFFF5D48E),
                            title: widget.backendConfigured
                                ? 'Backend fallback'
                                : 'Mock mode enabled',
                            body: widget.bootstrapWarning!,
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          'Pilot access',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.backendConfigured
                              ? 'Use your Supabase account to save progress. New players can create an account here and guest mode still stays available.'
                              : 'The app is ready with mock lessons right now. Add Supabase dart-defines later to switch on live auth and synced progress.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'pilot@learnify.app',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            hintText: 'Enter your password',
                          ),
                        ),
                        const SizedBox(height: 18),
                        BlocBuilder<SessionCubit, SessionState>(
                          builder: (BuildContext context, SessionState state) {
                            final busy =
                                state.status == SessionStatus.authenticating ||
                                state.status == SessionStatus.checking;
                            return Column(
                              children: <Widget>[
                                ElevatedButton(
                                  onPressed: busy || !widget.backendConfigured
                                      ? null
                                      : () {
                                          final email =
                                              _emailController.text.trim();
                                          final password =
                                              _passwordController.text.trim();
                                          if (!_validateCredentials(
                                            context,
                                            email,
                                            password,
                                          )) {
                                            return;
                                          }
                                          context
                                              .read<SessionCubit>()
                                              .signInWithEmail(
                                                email: email,
                                                password: password,
                                              );
                                        },
                                  child: Text(
                                    busy
                                        ? 'Preparing...'
                                        : 'Sign in with Supabase',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: busy || !widget.backendConfigured
                                      ? null
                                      : () {
                                          final email =
                                              _emailController.text.trim();
                                          final password =
                                              _passwordController.text.trim();
                                          if (!_validateCredentials(
                                            context,
                                            email,
                                            password,
                                          )) {
                                            return;
                                          }
                                          context
                                              .read<SessionCubit>()
                                              .signUpWithEmail(
                                                email: email,
                                                password: password,
                                              );
                                        },
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(56),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: const Text('Create account'),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => context
                                            .read<SessionCubit>()
                                            .continueAsGuest(),
                                  child: const Text('Continue as guest'),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const _InfoCard(
                          tone: Color(0xFFE7F7E6),
                          border: Color(0xFFBEE2BB),
                          title: 'Live write path',
                          body:
                              'Authenticated players now use Supabase auth, read synced content, and persist profile plus game session updates after each completed round.',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  bool _validateCredentials(
    BuildContext context,
    String email,
    String password,
  ) {
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter both email and password.')),
      );
      return false;
    }
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return false;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password must be at least 6 characters long.'),
        ),
      );
      return false;
    }
    return true;
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.tone,
    required this.border,
    required this.title,
    required this.body,
  });

  final Color tone;
  final Color border;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
