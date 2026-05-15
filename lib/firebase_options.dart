import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) return _web;
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
    if (kIsWeb) return 'web';
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

  static const FirebaseOptions _android = FirebaseOptions(
    apiKey: 'AIzaSyCz2zfCmRTvOtGi6TkMhOks0a2UxW9Nd0M',
    appId: '1:862542697682:android:2872d333f93d5b6611890b',
    messagingSenderId: '862542697682',
    projectId: 'learnify-rafik-20260421',
    storageBucket: 'learnify-rafik-20260421.firebasestorage.app',
  );

  static const FirebaseOptions _ios = FirebaseOptions(
    apiKey: 'AIzaSyDl7gguUv55FL6oY9OEDm9UMKug6rP2CYc',
    appId: '1:862542697682:ios:3e2c54b123b5f1b711890b',
    messagingSenderId: '862542697682',
    projectId: 'learnify-rafik-20260421',
    storageBucket: 'learnify-rafik-20260421.firebasestorage.app',
    iosBundleId: 'com.example.learnify',
  );

  static const FirebaseOptions _web = FirebaseOptions(
    apiKey: 'AIzaSyDP54kCQTf7JWiBVv6WrmqVruXibRxdb0o',
    appId: '1:862542697682:web:0796ea7b8301b3f011890b',
    messagingSenderId: '862542697682',
    projectId: 'learnify-rafik-20260421',
    storageBucket: 'learnify-rafik-20260421.firebasestorage.app',
    authDomain: 'learnify-rafik-20260421.firebaseapp.com',
  );
}
