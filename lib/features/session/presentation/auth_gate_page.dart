import 'dart:math' as math;
import 'dart:ui' as ui;

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

class _AuthGatePageState extends State<AuthGatePage>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _showEmailForm = false;

  late final AnimationController _floatController;
  late final AnimationController _pulseController;
  late final AnimationController _starsController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _starsController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _floatController.dispose();
    _pulseController.dispose();
    _starsController.dispose();
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: <Widget>[
                    const Icon(Icons.warning_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Expanded(child: Text(state.errorMessage!)),
                  ],
                ),
                backgroundColor: const Color(0xFFEF476F),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            );
          },
        ),
        BlocListener<SessionCubit, SessionState>(
          listenWhen: (SessionState previous, SessionState current) =>
              previous.noticeMessage != current.noticeMessage &&
              current.noticeMessage != null,
          listener: (BuildContext context, SessionState state) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.noticeMessage!),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            );
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
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Color(0xFF4CC9F0),
                Color(0xFF7B6FD4),
                Color(0xFF3D2B6B),
                Color(0xFF1A1030),
              ],
              stops: <double>[0.0, 0.3, 0.65, 1.0],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: <Widget>[
              // Animated starfield
              Positioned.fill(
                child: _LoginStarField(controller: _starsController),
              ),

              // Nebula orbs
              Positioned(
                top: -40,
                right: -60,
                child: _FloatingOrb(
                  controller: _floatController,
                  color: const Color(0xFF4CC9F0),
                  size: 200,
                  phase: 0,
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).size.height * 0.35,
                left: -80,
                child: _FloatingOrb(
                  controller: _floatController,
                  color: const Color(0xFFA28AE5),
                  size: 160,
                  phase: 1.5,
                ),
              ),
              Positioned(
                bottom: 60,
                right: -40,
                child: _FloatingOrb(
                  controller: _floatController,
                  color: const Color(0xFFFFD166),
                  size: 120,
                  phase: 3.0,
                ),
              ),

              // Main content
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 24,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        // Animated rocket mascot
                        _FloatingRocket(controller: _floatController),
                        const SizedBox(height: 24),

                        // Title with glow
                        _GlowingTitle(pulseController: _pulseController),
                        const SizedBox(height: 8),
                        Text(
                          'Speak. Learn. Level up.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // XP teaser stats
                        const _XpTeaser(),
                        const SizedBox(height: 28),

                        // Auth card
                        _buildAuthCard(context),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthCard(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      builder: (BuildContext context, SessionState state) {
        final busy =
            state.status == SessionStatus.authenticating ||
            state.status == SessionStatus.checking;

        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF7B6FD4).withValues(alpha: 0.3),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.bootstrapWarning != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD166).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFFD166).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.bolt_rounded,
                        size: 18,
                        color: Color(0xFFFFD166),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.bootstrapWarning!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Google sign-in — game-styled
              _GameButton(
                onPressed: busy || !widget.backendConfigured
                    ? null
                    : () => context.read<SessionCubit>().signInWithGoogle(),
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFF4CC9F0), Color(0xFF7B6FD4)],
                ),
                icon: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'G',
                    style: TextStyle(
                      color: Color(0xFF4285F4),
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                label: busy ? 'Connecting...' : 'Continue with Google',
                busy: busy,
              ),
              const SizedBox(height: 14),

              // Guest mode — secondary game button
              _GameButton(
                onPressed: busy
                    ? null
                    : () => context.read<SessionCubit>().continueAsGuest(),
                gradient: LinearGradient(
                  colors: <Color>[
                    const Color(0xFF80ED99).withValues(alpha: 0.8),
                    const Color(0xFF4CC9F0).withValues(alpha: 0.8),
                  ],
                ),
                icon: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.white,
                  size: 22,
                ),
                label: 'Quick Play as Guest',
                busy: false,
              ),
              const SizedBox(height: 20),

              // Email toggle
              _EmailToggle(
                expanded: _showEmailForm,
                onToggle: () => setState(() => _showEmailForm = !_showEmailForm),
              ),

              // Email form (collapsible)
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _buildEmailForm(context, busy),
                crossFadeState: _showEmailForm
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 300),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmailForm(BuildContext context, bool busy) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AutofillGroup(
        child: Column(
          children: <Widget>[
            _GlassTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'pilot@learnify.app',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.email],
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _GlassTextField(
              controller: _passwordController,
              label: 'Password',
              hint: 'At least 6 characters',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              autofillHints: const <String>[AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _signInWithEmail(context, busy: busy),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: Colors.white38,
                  size: 20,
                ),
                onPressed: () => setState(
                  () => _obscurePassword = !_obscurePassword,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: _GameButton(
                    onPressed: busy || !widget.backendConfigured
                        ? null
                        : () => _signInWithEmail(context, busy: busy),
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFFA28AE5), Color(0xFF7B6FD4)],
                    ),
                    icon: const Icon(
                      Icons.login_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    label: busy ? 'Signing in...' : 'Sign in',
                    busy: busy,
                    height: 48,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _GameButton(
                    onPressed: busy || !widget.backendConfigured
                        ? null
                        : () => _createAccount(context, busy: busy),
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0.12),
                        Colors.white.withValues(alpha: 0.06),
                      ],
                    ),
                    icon: const Icon(
                      Icons.person_add_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    label: 'Sign up',
                    busy: false,
                    height: 48,
                  ),
                ),
              ],
            ),
          ],
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
        SnackBar(
          content: const Text('Enter both email and password.'),
          backgroundColor: const Color(0xFFEF476F),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return false;
    }
    if (!email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Enter a valid email address.'),
          backgroundColor: const Color(0xFFEF476F),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return false;
    }
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Password must be at least 6 characters long.'),
          backgroundColor: const Color(0xFFEF476F),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );
      return false;
    }
    return true;
  }

  void _signInWithEmail(BuildContext context, {required bool busy}) {
    if (busy || !widget.backendConfigured) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (!_validateCredentials(context, email, password)) return;
    context.read<SessionCubit>().signInWithEmail(
      email: email,
      password: password,
    );
  }

  void _createAccount(BuildContext context, {required bool busy}) {
    if (busy || !widget.backendConfigured) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (!_validateCredentials(context, email, password)) return;
    context.read<SessionCubit>().signUpWithEmail(
      email: email,
      password: password,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Floating rocket mascot
// ────────────────────────────────────────────────────────────────────────────────

class _FloatingRocket extends StatelessWidget {
  const _FloatingRocket({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final t = controller.value;
        final bounce = math.sin(t * math.pi) * 12;
        final tilt = math.sin(t * math.pi * 2) * 0.05;
        return Transform.translate(
          offset: Offset(0, bounce),
          child: Transform.rotate(
            angle: tilt,
            child: child,
          ),
        );
      },
      child: SizedBox(
        width: 100,
        height: 140,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            // Glow behind rocket
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: const Color(0xFF4CC9F0).withValues(alpha: 0.3),
                    blurRadius: 40,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
            // Flame
            Positioned(
              bottom: 0,
              child: _AnimatedFlame(controller: controller),
            ),
            // Rocket body
            Positioned(
              bottom: 30,
              child: CustomPaint(
                size: const Size(56, 88),
                painter: _RocketBodyPainter(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedFlame extends StatelessWidget {
  const _AnimatedFlame({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final flicker = 0.85 + math.sin(controller.value * math.pi * 8) * 0.15;
        return Transform.scale(
          scaleY: flicker,
          alignment: Alignment.topCenter,
          child: child,
        );
      },
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            Container(
              width: 22,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    Color(0xFFFFD166),
                    Color(0xFFF78C6B),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Container(
              width: 12,
              height: 24,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[
                    Colors.white,
                    Color(0xFFFFD166),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RocketBodyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final s = size.width / 56;

    // Nose cone
    canvas.drawPath(
      Path()
        ..moveTo(cx, 0)
        ..lineTo(cx - 12 * s, 18 * s)
        ..lineTo(cx + 12 * s, 18 * s)
        ..close(),
      Paint()..color = const Color(0xFFEF476F),
    );

    // Body
    final body = RRect.fromLTRBR(
      cx - 12 * s, 16 * s, cx + 12 * s, 52 * s, Radius.circular(10 * s),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFF4CC9F0), Color(0xFFA28AE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(body.outerRect),
    );

    // Window
    canvas.drawCircle(
      Offset(cx, 30 * s),
      6 * s,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(cx, 30 * s),
      6 * s,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x442D2D2D),
    );

    // Fins
    for (final dir in <double>[-1, 1]) {
      canvas.drawPath(
        Path()
          ..moveTo(cx + 12 * s * dir, 44 * s)
          ..lineTo(cx + 20 * s * dir, 56 * s)
          ..lineTo(cx + 12 * s * dir, 56 * s)
          ..close(),
        Paint()..color = const Color(0xFFEF476F),
      );
    }

    // Nozzle
    final nozzle = RRect.fromLTRBR(
      cx - 10 * s, 52 * s, cx + 10 * s, 58 * s, Radius.circular(2 * s),
    );
    canvas.drawRRect(
      nozzle,
      Paint()
        ..shader = const LinearGradient(
          colors: <Color>[Color(0xFF6B6B6B), Color(0xFF2D2D2D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(nozzle.outerRect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ────────────────────────────────────────────────────────────────────────────────
// Glowing title
// ────────────────────────────────────────────────────────────────────────────────

class _GlowingTitle extends StatelessWidget {
  const _GlowingTitle({required this.pulseController});
  final AnimationController pulseController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseController,
      builder: (BuildContext context, Widget? child) {
        final glow = 0.4 + pulseController.value * 0.4;
        return ShaderMask(
          shaderCallback: (Rect bounds) => ui.Gradient.linear(
            Offset.zero,
            Offset(bounds.width, 0),
            const <Color>[
              Color(0xFF80ED99),
              Color(0xFF4CC9F0),
              Color(0xFFFFD166),
            ],
            const <double>[0.0, 0.5, 1.0],
          ),
          child: Text(
            'LEARNIFY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              shadows: <Shadow>[
                Shadow(
                  color: const Color(0xFF4CC9F0).withValues(alpha: glow),
                  blurRadius: 24,
                ),
                Shadow(
                  color: const Color(0xFF80ED99).withValues(alpha: glow * 0.5),
                  blurRadius: 40,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// XP teaser stats row
// ────────────────────────────────────────────────────────────────────────────────

class _XpTeaser extends StatelessWidget {
  const _XpTeaser();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _StatChip(
          icon: Icons.local_fire_department_rounded,
          iconColor: const Color(0xFFF78C6B),
          label: 'Streaks',
        ),
        const SizedBox(width: 12),
        _StatChip(
          icon: Icons.star_rounded,
          iconColor: const Color(0xFFFFD166),
          label: 'XP Points',
        ),
        const SizedBox(width: 12),
        _StatChip(
          icon: Icons.mic_rounded,
          iconColor: const Color(0xFF4CC9F0),
          label: 'Voice',
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Game-styled button with gradient + glow
// ────────────────────────────────────────────────────────────────────────────────

class _GameButton extends StatefulWidget {
  const _GameButton({
    required this.onPressed,
    required this.gradient,
    required this.icon,
    required this.label,
    required this.busy,
    this.height = 56,
  });

  final VoidCallback? onPressed;
  final Gradient gradient;
  final Widget icon;
  final String label;
  final bool busy;
  final double height;

  @override
  State<_GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<_GameButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed?.call();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          opacity: enabled ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: <BoxShadow>[
                if (enabled)
                  BoxShadow(
                    color: const Color(0xFF4CC9F0).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (widget.busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                else
                  widget.icon,
                const SizedBox(width: 10),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Email toggle divider
// ────────────────────────────────────────────────────────────────────────────────

class _EmailToggle extends StatelessWidget {
  const _EmailToggle({required this.expanded, required this.onToggle});
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.email_outlined,
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  expanded ? 'Hide email login' : 'Use email instead',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Glass-styled text field
// ────────────────────────────────────────────────────────────────────────────────

class _GlassTextField extends StatelessWidget {
  const _GlassTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.onSubmitted,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: const Color(0xFF4CC9F0),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 14,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withValues(alpha: 0.25),
          fontSize: 14,
        ),
        prefixIcon: Icon(icon, size: 20, color: Colors.white38),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.06),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFF4CC9F0),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────────
// Starfield background
// ────────────────────────────────────────────────────────────────────────────────

class _LoginStarField extends StatefulWidget {
  const _LoginStarField({required this.controller});
  final AnimationController controller;

  @override
  State<_LoginStarField> createState() => _LoginStarFieldState();
}

class _LoginStarFieldState extends State<_LoginStarField> {
  final math.Random _rng = math.Random(77);
  late final List<_StarData> _stars;

  @override
  void initState() {
    super.initState();
    _stars = List.generate(
      40,
      (_) => _StarData(
        _rng.nextDouble(),
        _rng.nextDouble(),
        1 + _rng.nextDouble() * 2.5,
        _rng.nextDouble() * math.pi * 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, Widget? child) {
        return CustomPaint(
          painter: _LoginStarPainter(_stars, widget.controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _StarData {
  _StarData(this.x, this.y, this.size, this.phase);
  final double x, y, size, phase;
}

class _LoginStarPainter extends CustomPainter {
  _LoginStarPainter(this.stars, this.t);
  final List<_StarData> stars;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in stars) {
      final twinkle = (math.sin(t * math.pi * 2 + s.phase) + 1) / 2;
      final dy = (s.y + t * 0.03) % 1.0;
      final opacity = 0.2 + twinkle * 0.6;
      final r = s.size * (0.8 + twinkle * 0.3);

      canvas.drawCircle(
        Offset(s.x * size.width, dy * size.height),
        r,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
      // Soft glow
      canvas.drawCircle(
        Offset(s.x * size.width, dy * size.height),
        r * 3,
        Paint()..color = Colors.white.withValues(alpha: opacity * 0.08),
      );
    }
  }

  @override
  bool shouldRepaint(_LoginStarPainter old) => old.t != t;
}

// ────────────────────────────────────────────────────────────────────────────────
// Floating nebula orb
// ────────────────────────────────────────────────────────────────────────────────

class _FloatingOrb extends StatelessWidget {
  const _FloatingOrb({
    required this.controller,
    required this.color,
    required this.size,
    required this.phase,
  });

  final AnimationController controller;
  final Color color;
  final double size;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        final d = math.sin(controller.value * math.pi * 2 + phase) * 20;
        return Transform.translate(
          offset: Offset(d, d * 0.6),
          child: child,
        );
      },
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: <Color>[
                color.withValues(alpha: 0.15),
                color.withValues(alpha: 0.05),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
