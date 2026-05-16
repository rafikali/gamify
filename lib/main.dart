import 'package:flutter/widgets.dart';

import 'app/learnify_app.dart';
import 'core/bootstrap/app_bootstrap.dart';
import 'core/config/app_config.dart';
import 'core/notifications/firebase_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseNotificationService.registerBackgroundHandler();

  final services = await AppBootstrap.initialize(AppConfig.fromEnvironment());
  runApp(LearnifyApp(services: services));
}
