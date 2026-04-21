import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) {
      return _web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _android;
      case TargetPlatform.iOS:
        return _ios;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return null;
    }
  }

  static bool get supportsCurrentPlatform {
    return kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static String get currentPlatformLabel {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.fuchsia:
        return 'Fuchsia';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
    }
  }

  static FirebaseOptions? get _android {
    if (!_hasRequiredValues(
      _FirebaseEnvironment.androidApiKey,
      _FirebaseEnvironment.androidAppId,
      _FirebaseEnvironment.messagingSenderId,
      _FirebaseEnvironment.projectId,
    )) {
      return null;
    }

    return FirebaseOptions(
      apiKey: _FirebaseEnvironment.androidApiKey,
      appId: _FirebaseEnvironment.androidAppId,
      messagingSenderId: _FirebaseEnvironment.messagingSenderId,
      projectId: _FirebaseEnvironment.projectId,
      storageBucket: _FirebaseEnvironment.storageBucketOrNull,
    );
  }

  static FirebaseOptions? get _ios {
    if (!_hasRequiredValues(
      _FirebaseEnvironment.iosApiKey,
      _FirebaseEnvironment.iosAppId,
      _FirebaseEnvironment.messagingSenderId,
      _FirebaseEnvironment.projectId,
    )) {
      return null;
    }

    return FirebaseOptions(
      apiKey: _FirebaseEnvironment.iosApiKey,
      appId: _FirebaseEnvironment.iosAppId,
      messagingSenderId: _FirebaseEnvironment.messagingSenderId,
      projectId: _FirebaseEnvironment.projectId,
      storageBucket: _FirebaseEnvironment.storageBucketOrNull,
      iosBundleId: _FirebaseEnvironment.iosBundleIdOrNull,
    );
  }

  static FirebaseOptions? get _web {
    if (!_hasRequiredValues(
      _FirebaseEnvironment.webApiKey,
      _FirebaseEnvironment.webAppId,
      _FirebaseEnvironment.messagingSenderId,
      _FirebaseEnvironment.projectId,
    )) {
      return null;
    }

    return FirebaseOptions(
      apiKey: _FirebaseEnvironment.webApiKey,
      appId: _FirebaseEnvironment.webAppId,
      messagingSenderId: _FirebaseEnvironment.messagingSenderId,
      projectId: _FirebaseEnvironment.projectId,
      authDomain:
          _FirebaseEnvironment.webAuthDomainOrNull ??
          '${_FirebaseEnvironment.projectId}.firebaseapp.com',
      storageBucket: _FirebaseEnvironment.storageBucketOrNull,
      measurementId: _FirebaseEnvironment.webMeasurementIdOrNull,
    );
  }

  static bool _hasRequiredValues(
    String first,
    String second,
    String third,
    String fourth,
  ) {
    return first.trim().isNotEmpty &&
        second.trim().isNotEmpty &&
        third.trim().isNotEmpty &&
        fourth.trim().isNotEmpty;
  }
}

class _FirebaseEnvironment {
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );

  static const String androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const String androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );

  static const String iosApiKey = String.fromEnvironment(
    'FIREBASE_IOS_API_KEY',
  );
  static const String iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
  );

  static const String webApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
  );
  static const String webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const String webAuthDomain = String.fromEnvironment(
    'FIREBASE_WEB_AUTH_DOMAIN',
  );
  static const String webMeasurementId = String.fromEnvironment(
    'FIREBASE_WEB_MEASUREMENT_ID',
  );

  static String? get storageBucketOrNull =>
      storageBucket.trim().isEmpty ? null : storageBucket;

  static String? get iosBundleIdOrNull =>
      iosBundleId.trim().isEmpty ? null : iosBundleId;

  static String? get webAuthDomainOrNull =>
      webAuthDomain.trim().isEmpty ? null : webAuthDomain;

  static String? get webMeasurementIdOrNull =>
      webMeasurementId.trim().isEmpty ? null : webMeasurementId;
}
