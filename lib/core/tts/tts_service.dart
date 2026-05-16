import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService() : _tts = FlutterTts();

  final FlutterTts _tts;
  bool _initialized = false;
  bool _disposed = false;
  Completer<void>? _speakCompleter;

  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _tts.setCompletionHandler(() {
      _speakCompleter?.complete();
      _speakCompleter = null;
    });
    _tts.setErrorHandler((dynamic message) {
      _speakCompleter?.complete();
      _speakCompleter = null;
    });
    _initialized = true;
  }

  /// Speaks the given [text] and returns a Future that completes when done.
  Future<void> speak(String text) async {
    if (_disposed) return;
    if (!_initialized) await initialize();
    _speakCompleter = Completer<void>();
    await _tts.speak(text);
    await _speakCompleter?.future;
  }

  Future<void> stop() async {
    if (_disposed) return;
    await _tts.stop();
    _speakCompleter?.complete();
    _speakCompleter = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _tts.stop();
  }
}
