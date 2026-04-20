import 'package:supabase_flutter/supabase_flutter.dart';

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
    this.supabaseClient,
    this.bootstrapWarning,
  });

  final AppConfig config;
  final SupabaseClient? supabaseClient;
  final SessionRepository sessionRepository;
  final LearningRepository learningRepository;
  final SpeechRecognitionService speechRecognitionService;
  final String? bootstrapWarning;
}

class AppBootstrap {
  static Future<AppBootstrapServices> initialize(AppConfig config) async {
    SupabaseClient? supabaseClient;
    String? bootstrapWarning;

    if (config.isSupabaseConfigured) {
      try {
        await Supabase.initialize(
          url: config.supabaseUrl,
          anonKey: config.supabaseAnonKey,
        );
        supabaseClient = Supabase.instance.client;
      } catch (error) {
        bootstrapWarning =
            'Supabase setup failed. Running in mock mode for now.\n$error';
      }
    } else {
      bootstrapWarning =
          'Add SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define to enable the live backend.';
    }

    final sessionRepository = SessionRepositoryImpl(
      supabaseClient: supabaseClient,
    );
    final learningRepository = LearningRepositoryImpl(
      supabaseClient: supabaseClient,
    );

    return AppBootstrapServices(
      config: config,
      supabaseClient: supabaseClient,
      sessionRepository: sessionRepository,
      learningRepository: learningRepository,
      speechRecognitionService: SpeechRecognitionServiceImpl(),
      bootstrapWarning: bootstrapWarning,
    );
  }
}
