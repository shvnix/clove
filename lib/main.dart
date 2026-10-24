import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/splash_screen.dart';
import 'services/audio/playback_service.dart';
import 'services/clove_notifications.dart';
import 'services/online_music_provider.dart';
import 'services/online_music_provider_registry.dart';
import 'services/online_music_provider_scope.dart';

const Color cloveObsidian = Color(0xFF0B0B0B);
const Color cloveInput = Color(0xFF202020);
const Color cloveMint = Color(0xFF1DE9B6);
const Color cloveText = Color(0xFFFFFFFF);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final registry = OnlineMusicProviderRegistry.forCurrentBuild();
  runApp(CloveApp(providerRegistry: registry));
  // Do not block the first Flutter frame on a platform-channel response.
  // If this call stalls, awaiting it here leaves Android's launch splash up.
  unawaited(_setPortraitOrientation());
  unawaited(_initializePlaybackService(registry.provider));
}

Future<void> _setPortraitOrientation() async {
  try {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  } catch (error) {
    debugPrint('CLOVE: Could not set portrait orientation: $error');
  }
}

Future<void> _initializePlaybackService(OnlineMusicProvider provider) async {
  try {
    await PlaybackService.initialize(onlineMusicProvider: provider);
    debugPrint('CLOVE: Audio service initialized successfully.');
  } catch (error, stackTrace) {
    debugPrint('CLOVE: Audio initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class CloveApp extends StatelessWidget {
  const CloveApp({super.key, this.onlineMusicProvider, this.providerRegistry});

  static final _defaultProviderRegistry =
      OnlineMusicProviderRegistry.forCurrentBuild();

  final OnlineMusicProvider? onlineMusicProvider;
  final OnlineMusicProviderRegistry? providerRegistry;

  @override
  Widget build(BuildContext context) {
    final registry =
        providerRegistry ??
        (onlineMusicProvider == null
            ? _defaultProviderRegistry
            : OnlineMusicProviderRegistry(provider: onlineMusicProvider!));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clove',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cloveObsidian,
        colorScheme: const ColorScheme.dark(
          primary: cloveMint,
          surface: cloveObsidian,
          onPrimary: cloveObsidian,
          onSurface: cloveText,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cloveInput,
          hintStyle: const TextStyle(color: Colors.white38),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: cloveMint, width: 1.3),
          ),
        ),
      ),
      builder: (context, child) => OnlineMusicProviderScope(
        provider: registry.provider,
        child: Stack(
          fit: StackFit.expand,
          children: [child ?? const SizedBox.shrink(), const CloveAlertHost()],
        ),
      ),
      home: const CloveSplashScreen(),
    );
  }
}
