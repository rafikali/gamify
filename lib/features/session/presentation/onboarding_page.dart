import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (mounted) {
      context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    const slides = <_OnboardingSlide>[
      _OnboardingSlide(
        title: 'Learn English by Playing 🚀',
        subtitle: 'Speak, play, and improve daily',
        icon: Icons.rocket_launch_rounded,
        iconColor: Color(0xFF4CC9F0),
      ),
      _OnboardingSlide(
        title: 'Features you will love',
        subtitle: 'Speak words, hit daily goals, and build streaks.',
        icon: Icons.mic_rounded,
        iconColor: Color(0xFF4CC9F0),
        features: <_OnboardingFeature>[
          _OnboardingFeature(
            icon: Icons.mic_rounded,
            text: 'Speak words',
            color: Color(0xFF4CC9F0),
          ),
          _OnboardingFeature(
            icon: Icons.track_changes_rounded,
            text: 'Daily goals',
            color: Color(0xFFFFD166),
          ),
          _OnboardingFeature(
            icon: Icons.local_fire_department_rounded,
            text: 'Track streaks',
            color: Color(0xFFEF476F),
          ),
        ],
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned(
              top: 12,
              right: 16,
              child: TextButton(onPressed: _finish, child: const Text('Skip')),
            ),
            Column(
              children: <Widget>[
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: slides.length,
                    onPageChanged: (int value) {
                      setState(() {
                        _index = value;
                      });
                    },
                    itemBuilder: (BuildContext context, int index) {
                      final slide = slides[index];
                      if (slide.features.isEmpty) {
                        return _IntroSlide(slide: slide);
                      }
                      return _FeatureSlide(slide: slide);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List<Widget>.generate(
                          slides.length,
                          (int idx) => AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: idx == _index ? 32 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: idx == _index
                                  ? const Color(0xFF4CC9F0)
                                  : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () async {
                          if (_index < slides.length - 1) {
                            await _controller.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                            return;
                          }
                          await _finish();
                        },
                        child: Text(
                          _index == slides.length - 1 ? 'Continue' : 'Next',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    this.features = const <_OnboardingFeature>[],
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final List<_OnboardingFeature> features;
}

class _OnboardingFeature {
  const _OnboardingFeature({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;
}

class _IntroSlide extends StatelessWidget {
  const _IntroSlide({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          TweenAnimationBuilder<double>(
            duration: const Duration(seconds: 2),
            tween: Tween<double>(begin: 0, end: 1),
            builder: (BuildContext context, double value, Widget? child) {
              final offset = (value * 14) % 14;
              return Transform.translate(
                offset: Offset(0, -offset),
                child: child,
              );
            },
            child: Icon(slide.icon, size: 112, color: slide.iconColor),
          ),
          const SizedBox(height: 28),
          Text(
            slide.title,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            slide.subtitle,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: const Color(0xFF6B6B6B)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeatureSlide extends StatelessWidget {
  const _FeatureSlide({required this.slide});

  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            slide.title,
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 36),
          ...slide.features.map(
            (_OnboardingFeature feature) => Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: feature.color.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(feature.icon, size: 34, color: feature.color),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Text(
                        feature.text,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
