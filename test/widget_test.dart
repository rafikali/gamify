import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learnify/app/learnify_app.dart';
import 'package:learnify/core/bootstrap/app_bootstrap.dart';
import 'package:learnify/core/config/app_config.dart';

void main() {
  testWidgets('Learnify starts on the splash screen', (
    WidgetTester tester,
  ) async {
    final services = await AppBootstrap.initialize(AppConfig.fromEnvironment());

    await tester.pumpWidget(LearnifyApp(services: services));
    await tester.pump();

    expect(find.text('Word Rocket'), findsOneWidget);
    expect(find.byIcon(Icons.rocket_launch_rounded), findsOneWidget);
  });
}
