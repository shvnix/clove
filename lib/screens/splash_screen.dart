import 'dart:async';

import 'package:flutter/material.dart';

import 'main_shell.dart';
import 'login_screen.dart';
import '../data/database.dart';

class CloveSplashScreen extends StatefulWidget {
  const CloveSplashScreen({super.key});

  @override
  State<CloveSplashScreen> createState() => _CloveSplashScreenState();
}

class _CloveSplashScreenState extends State<CloveSplashScreen>
    with TickerProviderStateMixin {
  static const _profileLoadTimeout = Duration(seconds: 5);

  late final AnimationController _rotationController;
  late final AnimationController _textController;

  Timer? _rotationStartTimer;
  Timer? _textRevealTimer;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );

    // Start rotation after the image is initially displayed.
    _rotationStartTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        _rotationController.repeat();
      }
    });
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Reveal the brand name after the logo begins rotating.
    _textRevealTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        _textController.forward();
      }
    });

    _navigationTimer = Timer(
      const Duration(milliseconds: 1500),
      _openNextScreen,
    );
  }

  Future<void> _openNextScreen() async {
    final database = AppDatabase.instance;

    try {
      // Opening or upgrading the local database can stall on some devices.
      // Keep that from trapping the user on the splash screen indefinitely.
      final profile = await database
          .getProfile()
          .timeout(_profileLoadTimeout);

      if (!mounted) return;

      final Widget destination = profile == null
          ? CloveLoginScreen(database: database)
          : MainShell(username: profile.name);

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => destination,
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } catch (error) {
      debugPrint('Failed to load saved profile: $error');

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => CloveLoginScreen(database: database),
          transitionDuration: const Duration(milliseconds: 600),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _rotationStartTimer?.cancel();
    _textRevealTimer?.cancel();
    _navigationTimer?.cancel();
    _rotationController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              width: double.infinity,
              height: constraints.maxHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Rotating logo at the visual center.
                  AnimatedBuilder(
                    animation: _rotationController,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle:
                            _rotationController.value * 2 * 3.141592653589793,
                        child: child,
                      );
                    },
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 300,
                      height: 300,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),

                  // Brand name near the bottom.
                  Positioned(
                    bottom: 38,
                    left: 0,
                    right: 0,
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _textController,
                        curve: Curves.easeIn,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'by',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const Text(
                            'SHVNIX',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 9,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
