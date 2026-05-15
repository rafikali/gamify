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
    // Dart-defines override the hardcoded values if provided.
    const envWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    const envIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

    return AppConfig(
      firebaseOptions: DefaultFirebaseOptions.currentPlatform,
      googleWebClientId: envWebClientId.isNotEmpty
          ? envWebClientId
          : '862542697682-i5himgsf52db9mudnci2uibbg3732h5k.apps.googleusercontent.com',
      googleIosClientId: envIosClientId.isNotEmpty
          ? envIosClientId
          : '862542697682-bede4d6ob40fr6a8gblee5bbansinagj.apps.googleusercontent.com',
    );
  }
}
