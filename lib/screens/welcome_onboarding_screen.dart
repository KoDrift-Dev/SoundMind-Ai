import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_assets.dart';
import '../core/constants/app_radius.dart';
import '../core/constants/app_typography.dart';
import '../core/widgets/themed_icon.dart';

import '../services/user_preferences_service.dart';
import 'genre_onboarding_screen.dart';
import 'main_navigation.dart';

class WelcomeOnboardingScreen extends StatefulWidget {
  const WelcomeOnboardingScreen({super.key});

  @override
  State<WelcomeOnboardingScreen> createState() =>
      _WelcomeOnboardingScreenState();
}

class _WelcomeOnboardingScreenState extends State<WelcomeOnboardingScreen>
    with SingleTickerProviderStateMixin {
  int _currentStep = 0; // 0: Welcome / Get Ready, 1: Name Input, 2: Theme Select
  bool _isDarkTheme = true; // Default: Dark Mode (Abyss)
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();

  final List<String> _nameSuggestions = [
    'Alex',
    'Audiophile',
    'Vibe Master',
    'Maestro',
    'Sonic',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing name if available
    final savedName = UserPreferencesService.instance.userName;
    if (savedName.isNotEmpty && savedName != 'Music Lover') {
      _nameController.text = savedName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  void _nextStep() {
    HapticFeedback.lightImpact();
    if (_currentStep < 2) {
      setState(() {
        _currentStep++;
      });
    } else {
      _completeOnboarding();
    }
  }

  void _prevStep() {
    HapticFeedback.selectionClick();
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    }
  }

  Future<void> _completeOnboarding() async {
    HapticFeedback.mediumImpact();
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      await UserPreferencesService.instance.setUserName(name);
    }
    await UserPreferencesService.instance.setTheme(_isDarkTheme);
    await UserPreferencesService.instance.setOnboardingCompleted(true);

    if (!mounted) return;

    final isGenreOnboarded =
        UserPreferencesService.instance.hasCompletedGenreOnboarding;

    final Widget targetScreen = isGenreOnboarded
        ? MainNavigation(key: MainNavigation.navKey)
        : const GenreOnboardingScreen();

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
  Widget build(BuildContext context) {
    // Dynamic text colors depending on selected theme
    final isDark = _isDarkTheme;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryTextColor = isDark
        ? Colors.white.withValues(alpha: 0.70)
        : const Color(0xFF334155).withValues(alpha: 0.85);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF060810) : const Color(0xFFF1F5F9),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background Image Layer with Animated Cross-Fade ─────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 600),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Container(
              key: ValueKey<bool>(_isDarkTheme),
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage(
                    _isDarkTheme ? AppAssets.darkBg : AppAssets.lightBg,
                  ),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),

          // ── Aesthetic Gradient & Vignette Overlay ──────────────────
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.45, 0.75, 1.0],
                  colors: _isDarkTheme
                      ? [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.82),
                          Colors.black.withValues(alpha: 0.96),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.05),
                          Colors.white.withValues(alpha: 0.25),
                          Colors.white.withValues(alpha: 0.80),
                          Colors.white.withValues(alpha: 0.95),
                        ],
                ),
              ),
            ),
          ),

          // ── Interactive Screen Steps ──────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Top App Header / Step Navigation
                _buildTopBar(isDark),

                // Main Content Area
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.04, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _buildCurrentStepWidget(
                      primaryTextColor,
                      secondaryTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top Bar with Back Button & Progress Dots ─────────────────────────
  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button (shown on steps 1 and 2)
          if (_currentStep > 0)
            GestureDetector(
              onTap: _prevStep,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.full),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
              ),
            )
          else
            // Subtle Logo Badge on Step 0
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF3898FF).withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: const ThemedIcon(size: 24, showBorder: false),
                ),
                const SizedBox(width: 8),

                Text(
                  'SOUNDMIND',
                  style: TextStyle(
                    fontFamily: AppTypography.displayFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),

          // Step Progress Dots
          Row(
            children: List.generate(3, (index) {
              final isCurrent = _currentStep == index;
              final isPassed = _currentStep > index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isCurrent ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isCurrent
                      ? const Color(0xFF3898FF)
                      : isPassed
                          ? const Color(0xFF3898FF).withValues(alpha: 0.5)
                          : (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.2),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: const Color(0xFF3898FF)
                                .withValues(alpha: 0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ── Step Router ──────────────────────────────────────────────────────
  Widget _buildCurrentStepWidget(
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    switch (_currentStep) {
      case 0:
        return _buildStepWelcome(primaryTextColor, secondaryTextColor);
      case 1:
        return _buildStepUserName(primaryTextColor, secondaryTextColor);
      case 2:
        return _buildStepThemeSelect(primaryTextColor, secondaryTextColor);
      default:
        return const SizedBox.shrink();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // STEP 0: Welcome & "Get Ready" (Exact UI matching user's image)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildStepWelcome(
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return KeyedSubtree(
      key: const ValueKey('step_welcome'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Spacer(),

            // 1. Big Headline: "Feel Every Beat."
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  letterSpacing: -0.5,
                  color: primaryTextColor,
                ),
                children: const [
                  TextSpan(text: 'Feel '),
                  TextSpan(
                    text: 'Every Beat.',
                    style: TextStyle(
                      color: Color(0xFF3898FF),
                      shadows: [
                        Shadow(
                          color: Color(0xFF3898FF),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 2. Subtitle: "AI-Powered Music Experience Tailored for You."
            Text(
              'AI-Powered Music Experience\nTailored for You.',
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.45,
                color: secondaryTextColor,
              ),
            ),

            const SizedBox(height: 28),

            // 3. Glowing Audio Wave Feature Badge (Matching user reference)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: (_isDarkTheme ? Colors.white : Colors.black)
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF3898FF).withValues(alpha: 0.35),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3898FF).withValues(alpha: 0.12),
                        blurRadius: 16,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Glowing wave icon container
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF1E3A8A),
                              Color(0xFF0284C7),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3898FF)
                                  .withValues(alpha: 0.4),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.graphic_eq_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Your Music. Your Mood.\nYour World.',
                          style: TextStyle(
                            fontFamily: AppTypography.uiFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                            color: primaryTextColor.withValues(alpha: 0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // 4. Primary "Get Ready" Button
            _buildPrimaryButton(
              label: 'Get Ready',
              icon: Icons.arrow_forward_rounded,
              onPressed: _nextStep,
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // STEP 1: User Name Input
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildStepUserName(
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return KeyedSubtree(
      key: const ValueKey('step_user_name'),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // User Avatar / Icon Badge
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3898FF), Color(0xFF8B7FFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3898FF).withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Title
            Center(
              child: Text(
                'What should we call you?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: primaryTextColor,
                ),
              ),
            ),

            const SizedBox(height: 8),

            Center(
              child: Text(
                'Personalize your SoundMind experience and AI music journey',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 14,
                  height: 1.4,
                  color: secondaryTextColor,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Glassmorphism Name Input Card
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: (_isDarkTheme ? Colors.white : Colors.black)
                        .withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: const Color(0xFF3898FF).withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR NAME / ALIAS',
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: const Color(0xFF3898FF),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        autofocus: false,
                        style: TextStyle(
                          fontFamily: AppTypography.uiFont,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: primaryTextColor,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Alex, Maya, Nova',
                          hintStyle: TextStyle(
                            color: secondaryTextColor.withValues(alpha: 0.5),
                            fontSize: 16,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          prefixIcon: Icon(
                            Icons.badge_outlined,
                            color: const Color(0xFF3898FF),
                            size: 22,
                          ),
                          suffixIcon: _nameController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.close_rounded,
                                    color: secondaryTextColor,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _nameController.clear();
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _nextStep(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Quick Suggestions Chips
            Text(
              'Quick suggestions:',
              style: TextStyle(
                fontFamily: AppTypography.uiFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _nameSuggestions.map((suggestion) {
                final isSelected = _nameController.text == suggestion;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _nameController.text = suggestion;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF3898FF)
                          : (_isDarkTheme ? Colors.white : Colors.black)
                              .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF3898FF)
                            : (_isDarkTheme ? Colors.white : Colors.black)
                                .withValues(alpha: 0.15),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      suggestion,
                      style: TextStyle(
                        fontFamily: AppTypography.uiFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : primaryTextColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 40),

            // Continue Button
            _buildPrimaryButton(
              label: 'Continue to Theme',
              icon: Icons.arrow_forward_rounded,
              onPressed: _nextStep,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // STEP 2: Mode / Theme Selection with LIVE dynamic background switching!
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildStepThemeSelect(
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    return KeyedSubtree(
      key: const ValueKey('step_theme_select'),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // Theme Icon
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3898FF), Color(0xFF00E5FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3898FF).withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isDarkTheme
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  size: 38,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Title
            Center(
              child: Text(
                'Choose Your Vibe',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.displayFont,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: primaryTextColor,
                ),
              ),
            ),

            const SizedBox(height: 8),

            Center(
              child: Text(
                'Select your theme mode. Watch the background adapt instantly!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTypography.uiFont,
                  fontSize: 14,
                  height: 1.4,
                  color: secondaryTextColor,
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Option 1: Dark Mode (Abyss) - Default
            _buildThemeOptionCard(
              title: 'Dark Mode (Abyss)',
              subtitle: 'Deep obsidian aesthetic & neon glow aura',
              icon: Icons.nightlight_round,
              accentColor: const Color(0xFF3898FF),
              isSelected: _isDarkTheme,
              primaryTextColor: primaryTextColor,
              secondaryTextColor: secondaryTextColor,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _isDarkTheme = true;
                });
              },
            ),

            const SizedBox(height: 16),

            // Option 2: Light Mode (Frost)
            _buildThemeOptionCard(
              title: 'Light Mode (Frost)',
              subtitle: 'Clean arctic white aesthetic & vibrant indigo',
              icon: Icons.wb_sunny_rounded,
              accentColor: const Color(0xFF5B4FE8),
              isSelected: !_isDarkTheme,
              primaryTextColor: primaryTextColor,
              secondaryTextColor: secondaryTextColor,
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _isDarkTheme = false;
                });
              },
            ),

            const SizedBox(height: 36),

            // Let's Get Started CTA
            _buildPrimaryButton(
              label: "Let's Get Started",
              icon: Icons.rocket_launch_rounded,
              onPressed: _completeOnboarding,
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Theme Selection Card ─────────────────────────────────────────────
  Widget _buildThemeOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isSelected,
    required Color primaryTextColor,
    required Color secondaryTextColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? (_isDarkTheme
                  ? const Color(0xFF131B2E).withValues(alpha: 0.85)
                  : Colors.white.withValues(alpha: 0.90))
              : (_isDarkTheme ? Colors.white : Colors.black)
                  .withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isSelected
                ? accentColor
                : (_isDarkTheme ? Colors.white : Colors.black)
                    .withValues(alpha: 0.12),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Icon container
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? accentColor
                    : (_isDarkTheme ? Colors.white : Colors.black)
                        .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected ? Colors.white : secondaryTextColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: AppTypography.uiFont,
                      fontSize: 12,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),

            // Active Radio / Check Badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accentColor : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? accentColor
                      : (_isDarkTheme ? Colors.white : Colors.black)
                          .withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Primary Glowing CTA Button ───────────────────────────────────────
  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF3898FF),
            Color(0xFF1D4ED8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3898FF).withValues(alpha: 0.45),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.full),
          onTap: onPressed,
          splashColor: Colors.white.withValues(alpha: 0.2),
          highlightColor: Colors.white.withValues(alpha: 0.1),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppTypography.uiFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  icon,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
