import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';

class AppConfig {
  const AppConfig({
    required this.firebaseOptions,
    required this.googleWebClientId,
    required this.googleIosClientId,
  });

  final FirebaseOptions? firebaseOptions;
  final String googleWebClientId;
  final String googleIosClientId;

  bool get isFirebaseConfigured => firebaseOptions != null;

  bool get supportsFirebasePlatform =>
      DefaultFirebaseOptions.supportsCurrentPlatform;

  String get firebasePlatformLabel =>
      DefaultFirebaseOptions.currentPlatformLabel;

  static AppConfig fromEnvironment() {
    return AppConfig(
      firebaseOptions: DefaultFirebaseOptions.currentPlatform,
      googleWebClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
      googleIosClientId: const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    );
  }
}
