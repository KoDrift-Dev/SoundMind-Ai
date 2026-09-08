import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_typography.dart';
import '../core/widgets/themed_icon.dart';
import '../services/audio_scanner_service.dart';
import '../services/user_preferences_service.dart';
import 'genre_onboarding_screen.dart';
import 'main_navigation.dart';
import 'welcome_onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotationController;
  late final AnimationController _fadeController;

  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;
  late final Animation<double> _fadeAnimation;

  bool _needsPermission = false;
  bool _isRequestingPermission = false;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _glowAnimation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _fadeController.forward();
    _checkInitialAccessAndInit();
  }

  Future<void> _checkInitialAccessAndInit() async {
    try {
      await UserPreferencesService.instance.init();

      // Check if permission is already granted
      final hasPermission = await AudioScannerService.instance.checkPermissions();

      if (!hasPermission) {
        if (!mounted) return;
        setState(() {
          _needsPermission = true;
        });
      } else {
        // Permission already granted: launch background scan and proceed
        unawaited(AudioScannerService.instance.scan());
        await Future.delayed(const Duration(milliseconds: 2200));
        if (!mounted) return;
        _navigateToNextScreen();
      }
    } catch (e, st) {
      debugPrint('SplashScreen _checkInitialAccessAndInit error: $e\n$st');
    }
  }

  Future<void> _handleGrantAccess() async {
    if (_isRequestingPermission) return;
    setState(() => _isRequestingPermission = true);
    HapticFeedback.mediumImpact();

    try {
      final granted = await AudioScannerService.instance.requestPermissions();
      if (granted) {
        // Kick off background scan immediately so files are fetched while user transitions
        unawaited(AudioScannerService.instance.scan());
      }
    } catch (e) {
      debugPrint('SplashScreen: Error requesting permissions: $e');
    }

    if (!mounted) return;
    _navigateToNextScreen();
  }

  void _handleSkip() {
    HapticFeedback.selectionClick();
    _navigateToNextScreen();
  }

  void _navigateToNextScreen() {
    final isOnboarded =
        UserPreferencesService.instance.isOnboardingCompleted;
    final isGenreOnboarded =
        UserPreferencesService.instance.hasCompletedGenreOnboarding;

    final Widget targetScreen;
    if (!isOnboarded) {
      targetScreen = const WelcomeOnboardingScreen();
    } else if (!isGenreOnboarded) {
      targetScreen = const GenreOnboardingScreen();
    } else {
      targetScreen = MainNavigation(key: MainNavigation.navKey);
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 700),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07070C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background ambient gradient
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.1),
                radius: 1.2,
                colors: [
                  Color(0xFF151828),
                  Color(0xFF090A10),
                  Color(0xFF040407),
                ],
              ),
            ),
          ),

          // Glowing animated rings & logo
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _pulseController,
                  _rotationController,
                ]),
                builder: (context, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo container with rotating soundwave halo & glow
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Outer rotating halo ring
                          Transform.rotate(
                            angle: _rotationController.value * 2 * math.pi,
                            child: Container(
                              width: 170,
                              height: 170,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF3898FF)
                                      .withValues(alpha: 0.15 * _glowAnimation.value),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),

                          // Glowing outer pulse aura
                          Container(
                            width: 140 * _scaleAnimation.value,
                            height: 140 * _scaleAnimation.value,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF3898FF)
                                      .withValues(alpha: 0.45 * _glowAnimation.value),
                                  blurRadius: 50,
                                  spreadRadius: 15,
                                ),
                                BoxShadow(
                                  color: const Color(0xFF8B7FFF)
                                      .withValues(alpha: 0.3 * _glowAnimation.value),
                                  blurRadius: 70,
                                  spreadRadius: 20,
                                ),
                              ],
                            ),
                          ),

                          // Inner glowing logo badge (Temporary Crashlytics test trigger on long press)
                          GestureDetector(
                            onLongPress: () {
                              debugPrint('*** Triggering Firebase Crashlytics Test Crash ***');
                              FirebaseCrashlytics.instance.crash();
                            },
                            child: Transform.scale(
                              scale: _scaleAnimation.value,
                              child: Container(
                                width: 110,
                                height: 110,
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF1B2236),
                                      Color(0xFF0E1220),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFF4FA0FF)
                                        .withValues(alpha: 0.5),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(50),
                                  child: const ThemedIcon(
                                    size: 74,
                                    showBorder: false,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 36),

                      // App Title Branding
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            Colors.white,
                            Color(0xFF8DC5FF),
                            Color(0xFF3898FF),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: const Text(
                          'SOUNDMIND',
                          style: TextStyle(
                            fontFamily: AppTypography.displayFont,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4.0,
                            color: Colors.white,
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Sub-tagline with sound wave dots
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF3898FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI AUDIO INTELLIGENCE',
                            style: TextStyle(
                              fontFamily: AppTypography.uiFont,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 3.0,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF3898FF),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Bottom Action: Grant Access Card if permission needed, or subtle loader
          if (_needsPermission)
            Positioned(
              bottom: 32,
              left: 20,
              right: 20,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF131726).withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: const Color(0xFF3898FF).withValues(alpha: 0.40),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3898FF).withValues(alpha: 0.22),
                        blurRadius: 28,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3898FF).withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF3898FF).withValues(alpha: 0.45),
                              ),
                            ),
                            child: const Icon(
                              Icons.folder_shared_rounded,
                              color: Color(0xFF3898FF),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Grant Audio Access',
                                  style: TextStyle(
                                    fontFamily: AppTypography.displayFont,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Allow access to discover your local music in the background for your For You feed.',
                                  style: TextStyle(
                                    fontFamily: AppTypography.uiFont,
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.70),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isRequestingPermission ? null : _handleGrantAccess,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3898FF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 4,
                            shadowColor: const Color(0xFF3898FF).withValues(alpha: 0.5),
                          ),
                          child: _isRequestingPermission
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.lock_open_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'Grant Access & Scan',
                                      style: TextStyle(
                                        fontFamily: AppTypography.uiFont,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _isRequestingPermission ? null : _handleSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.55),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text(
                          'Skip for now (Online Mode)',
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFF3898FF).withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
