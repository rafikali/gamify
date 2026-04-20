import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract class SpeechRecognitionService {
  Future<bool> initialize();

  bool get isListening;

  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
    required void Function(String message) onError,
  });

  Future<void> stop();

  void dispose();
}

class SpeechRecognitionServiceImpl implements SpeechRecognitionService {
  SpeechRecognitionServiceImpl() : _speechToText = SpeechToText();

  final SpeechToText _speechToText;

  bool _initialized = false;
  bool _available = false;

  @override
  Future<bool> initialize() async {
    if (_initialized) {
      return _available;
    }

    try {
      _available = await _speechToText.initialize(
        onError: _noopError,
        onStatus: _noopStatus,
      );
    } catch (_) {
      _available = false;
    }

    _initialized = true;
    return _available;
  }

  @override
  bool get isListening => _speechToText.isListening;

  @override
  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
    required void Function(String message) onError,
  }) async {
    if (!_initialized) {
      final available = await initialize();
      if (!available) {
        onError('Speech recognition is unavailable on this device.');
        return;
      }
    }

    if (!_available) {
      onError('Speech recognition is unavailable on this device.');
      return;
    }

    try {
      await _speechToText.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 6),
        listenOptions: SpeechListenOptions(partialResults: true),
        localeId: 'en_US',
        onSoundLevelChange: _noopLevel,
      );
    } on Exception {
      onError('Microphone access failed. Check the app permissions.');
    }
  }

  @override
  Future<void> stop() async {
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
  }

  @override
  void dispose() {
    _speechToText.cancel();
  }

  void _noopStatus(String _) {}

  void _noopLevel(double _) {}

  void _noopError(SpeechRecognitionError _) {}
}
