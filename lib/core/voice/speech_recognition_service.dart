import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

abstract class SpeechRecognitionService {
  Future<bool> initialize();

  bool get isListening;

  Future<void> listen({
    required void Function(String transcript, bool isFinal) onResult,
    required void Function(String message) onError,
    void Function()? onDone,
  });

  Future<void> stop();

  void dispose();
}

class SpeechRecognitionServiceImpl implements SpeechRecognitionService {
  SpeechRecognitionServiceImpl() : _speechToText = SpeechToText();

  final SpeechToText _speechToText;

  bool _initialized = false;
  bool _available = false;
  void Function()? _onDone;

  @override
  Future<bool> initialize() async {
    if (_initialized) {
      return _available;
    }

    try {
      _available = await _speechToText.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
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
    void Function()? onDone,
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

    _onDone = onDone;

    // If still listening from a previous session, stop first and wait a beat.
    if (_speechToText.isListening) {
      await _speechToText.stop();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    try {
      await _speechToText.listen(
        onResult: (SpeechRecognitionResult result) {
          onResult(result.recognizedWords, result.finalResult);
        },
        pauseFor: const Duration(seconds: 4),
        listenFor: const Duration(seconds: 30),
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
    _onDone = null;
    if (_speechToText.isListening) {
      await _speechToText.stop();
    }
  }

  @override
  void dispose() {
    _onDone = null;
    _speechToText.cancel();
  }

  void _handleStatus(String status) {
    // 'done' or 'notListening' means the mic session ended on its own
    // (e.g. pauseFor / listenFor timeout). Notify the caller so it can restart.
    if (status == 'done' || status == 'notListening') {
      final cb = _onDone;
      _onDone = null;
      cb?.call();
    }
  }

  void _noopLevel(double _) {}

  void _handleError(SpeechRecognitionError error) {
    // Errors are forwarded through the listen() onError callback.
    // The status callback handles the 'done' transition for restarts.
  }
}
