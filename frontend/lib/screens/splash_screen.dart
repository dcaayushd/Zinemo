import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/theme/app_theme.dart';

/// Splash screen with cinematic intro animation
/// - Film grain noise overlay
/// - Cinematic letterbox bars slide in (800ms)
/// - Logo fades in with blur→sharp (600ms)
/// - Tagline types character by character
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  int _displayedChars = 0;
  final String _tagline = 'Track. Rate. Discover.';

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _startAnimationSequence();
  }

  void _startAnimationSequence() async {
    // Fade in logo (600ms)
    await _fadeController.forward();

    // Start typing animation
    for (int i = 0; i < _tagline.length; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (mounted) {
        setState(() => _displayedChars = i + 1);
      }
    }

    // Wait 1.8 seconds, then check if user is authenticated
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      // Check if user has an existing session
      final session = Supabase.instance.client.auth.currentSession;

      if (session != null) {
        // User is already logged in, go to home
        context.go('/home');
      } else {
        // No session, go to auth
        context.go('/auth');
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Film grain noise background
          _buildFilmGrainOverlay(),

          // Content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with fade + scale animation
                FadeTransition(
                  opacity: _fadeController,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _fadeController,
                        curve: Curves.elasticOut,
                      ),
                    ),
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Center(
                        child: Text(
                          'Z',
                          style: TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // Tagline with typewriter effect
                FadeTransition(
                  opacity: _fadeController,
                  child: SizedBox(
                    height: 32,
                    child: Text(
                      _tagline.substring(0, _displayedChars),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppTheme.secondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Letterbox top bar - slides in from top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, -1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _scaleController,
                      curve: Curves.easeInOutCubic,
                    ),
                  ),
              child: Container(height: 80, color: Colors.black),
            ),
          ),

          // Letterbox bottom bar - slides in from bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _scaleController,
                      curve: Curves.easeInOutCubic,
                    ),
                  ),
              child: Container(height: 80, color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  /// Film grain noise effect
  Widget _buildFilmGrainOverlay() {
    return CustomPaint(painter: FilmGrainPainter(), child: Container());
  }
}

/// Custom painter for film grain texture
class FilmGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
      ..blendMode = BlendMode.overlay;

    // Draw random grain dots for noisy texture
    final random = List.generate(500, (i) => i);
    for (final _ in random) {
      final x = (DateTime.now().millisecond * 12.34) % size.width;
      final y = (DateTime.now().microsecond * 45.67) % size.height;
      canvas.drawCircle(Offset(x, y), 0.5, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
