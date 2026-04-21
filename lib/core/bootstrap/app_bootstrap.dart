import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../features/learning/data/learning_repository_impl.dart';
import '../../features/learning/domain/learning_repository.dart';
import '../../features/session/data/session_repository_impl.dart';
import '../../features/session/domain/session_repository.dart';
import '../config/app_config.dart';
import '../voice/speech_recognition_service.dart';

class AppBootstrapServices {
  const AppBootstrapServices({
    required this.config,
    required this.sessionRepository,
    required this.learningRepository,
    required this.speechRecognitionService,
    this.firebaseApp,
    this.firebaseAuth,
    this.firestore,
    this.bootstrapWarning,
  });

  final AppConfig config;
  final FirebaseApp? firebaseApp;
  final FirebaseAuth? firebaseAuth;
  final FirebaseFirestore? firestore;
  final SessionRepository sessionRepository;
  final LearningRepository learningRepository;
  final SpeechRecognitionService speechRecognitionService;
  final String? bootstrapWarning;
}

class AppBootstrap {
  static Future<AppBootstrapServices> initialize(AppConfig config) async {
    FirebaseApp? firebaseApp;
    FirebaseAuth? firebaseAuth;
    FirebaseFirestore? firestore;
    String? bootstrapWarning;

    if (!config.supportsFirebasePlatform) {
      bootstrapWarning =
          'Firebase is not enabled for ${config.firebasePlatformLabel} in this app build. Running in mock mode for now.';
    } else if (config.isFirebaseConfigured) {
      try {
        final initializedApp = await Firebase.initializeApp(
          options: config.firebaseOptions!,
        );
        firebaseApp = initializedApp;
        firebaseAuth = FirebaseAuth.instanceFor(app: initializedApp);
        firestore = FirebaseFirestore.instanceFor(app: initializedApp);
      } catch (error) {
        bootstrapWarning =
            'Firebase setup failed. Running in mock mode for now.\n$error';
      }
    } else {
      bootstrapWarning =
          'Add the FIREBASE_* dart-defines for ${config.firebasePlatformLabel} to enable the live backend.';
    }

    final sessionRepository = SessionRepositoryImpl(
      firebaseAuth: firebaseAuth,
      firestore: firestore,
      googleWebClientId: config.googleWebClientId,
      googleIosClientId: config.googleIosClientId,
    );
    final learningRepository = LearningRepositoryImpl(firestore: firestore);

    return AppBootstrapServices(
      config: config,
      firebaseApp: firebaseApp,
      firebaseAuth: firebaseAuth,
      firestore: firestore,
      sessionRepository: sessionRepository,
      learningRepository: learningRepository,
      speechRecognitionService: SpeechRecognitionServiceImpl(),
      bootstrapWarning: bootstrapWarning,
    );
  }
}
