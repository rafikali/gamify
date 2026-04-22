import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

class GameAudioController {
  GameAudioController()
    : _enginePlayer = AudioPlayer(playerId: 'game-engine'),
      _warningPlayer = AudioPlayer(playerId: 'game-warning'),
      _sfxPlayer = AudioPlayer(playerId: 'game-sfx');

  static const String _engineAsset = 'audio/rocket_engine_loop.wav';
  static const String _warningAsset = 'audio/danger_warning_loop.wav';
  static const String _boostAsset = 'audio/boost.wav';
  static const String _listenAsset = 'audio/listen_ping.wav';
  static const String _crashAsset = 'audio/crash.wav';

  final AudioPlayer _enginePlayer;
  final AudioPlayer _warningPlayer;
  final AudioPlayer _sfxPlayer;

  Future<void>? _warmUpFuture;
  bool _enginePlaying = false;
  bool _warningPlaying = false;
  double _lastWarningVolume = -1;
  bool _disposed = false;

  Future<void> warmUp() {
    return _warmUpFuture ??= _runSafely(() async {
      await _enginePlayer.setReleaseMode(ReleaseMode.loop);
      await _warningPlayer.setReleaseMode(ReleaseMode.loop);
      await _enginePlayer.setVolume(0.16);
      await _warningPlayer.setVolume(0);
      await _sfxPlayer.setVolume(0.8);
      await Future.wait<void>(<Future<void>>[
        _enginePlayer.setSource(AssetSource(_engineAsset)),
        _warningPlayer.setSource(AssetSource(_warningAsset)),
      ]);
    });
  }

  Future<void> startFlightLoop() async {
    await warmUp();
    if (_disposed || _enginePlaying) {
      return;
    }

    await _runSafely(() async {
      await _enginePlayer.resume();
      _enginePlaying = true;
    });
  }

  Future<void> stopFlightLoop() async {
    if (_disposed || !_enginePlaying) {
      return;
    }

    await _runSafely(() async {
      await _enginePlayer.stop();
      _enginePlaying = false;
    });
  }

  Future<void> clearDanger() => setDangerLevel(0);

  Future<void> setDangerLevel(double level) async {
    await warmUp();
    if (_disposed) {
      return;
    }

    final normalizedLevel = level.clamp(0.0, 1.0).toDouble();
    if (normalizedLevel < 0.08) {
      if (!_warningPlaying) {
        return;
      }

      await _runSafely(() async {
        await _warningPlayer.stop();
        _warningPlaying = false;
        _lastWarningVolume = -1;
      });
      return;
    }

    final targetVolume = (0.06 + (normalizedLevel * 0.22))
        .clamp(0.06, 0.28)
        .toDouble();

    await _runSafely(() async {
      if (!_warningPlaying) {
        await _warningPlayer.setVolume(targetVolume);
        await _warningPlayer.resume();
        _warningPlaying = true;
        _lastWarningVolume = targetVolume;
        return;
      }

      if ((_lastWarningVolume - targetVolume).abs() > 0.025) {
        await _warningPlayer.setVolume(targetVolume);
        _lastWarningVolume = targetVolume;
      }
    });
  }

  Future<void> playBoost() => _playEffect(_boostAsset, volume: 0.9);

  Future<void> playListenPing() => _playEffect(_listenAsset, volume: 0.65);

  Future<void> playCrash() async {
    await clearDanger();
    await stopFlightLoop();
    await _playEffect(_crashAsset, volume: 1.0);
  }

  Future<void> stopAll() async {
    await Future.wait<void>(<Future<void>>[
      clearDanger(),
      stopFlightLoop(),
      _runSafely(() => _sfxPlayer.stop()),
    ]);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    await stopAll();
    _disposed = true;
    await Future.wait<void>(<Future<void>>[
      _enginePlayer.dispose(),
      _warningPlayer.dispose(),
      _sfxPlayer.dispose(),
    ]);
  }

  Future<void> _playEffect(String assetPath, {required double volume}) async {
    await warmUp();
    if (_disposed) {
      return;
    }

    await _runSafely(() async {
      await _sfxPlayer.setVolume(volume);
      await _sfxPlayer.stop();
      await _sfxPlayer.play(AssetSource(assetPath));
    });
  }

  Future<void> _runSafely(Future<void> Function() action) async {
    if (_disposed) {
      return;
    }

    try {
      await action();
    } catch (_) {
      // Audio should never break gameplay if a platform backend is unavailable.
    }
  }
}
