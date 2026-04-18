import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  Future<bool> _hasSavedGenrePreferences() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('preferences')
          .eq('id', user.id)
          .single();

      final preferences = row['preferences'];
      if (preferences is! Map) {
        return false;
      }

      final prefs = Map<String, dynamic>.from(preferences);
      final dynamic genres = prefs['favorite_genre_ids'] ?? prefs['genres'];
      return genres is List && genres.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _routeAfterSplash() async {
    if (!mounted) {
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      context.go('/auth');
      return;
    }

    final hasGenres = await _hasSavedGenrePreferences();
    if (!mounted) {
      return;
    }

    context.go(hasGenres ? '/home' : '/onboarding');
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _routeAfterSplash();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo animation
            FadeTransition(
              opacity: Tween<double>(begin: 0, end: 1).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: const Interval(0.0, 0.4),
                ),
              ),
              child: const Text(
                '🎬 Zinemo',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Tagline
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.2),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: const Interval(0.2, 0.6),
                    ),
                  ),
              child: const Text(
                'Your Personal Movie & TV Logger',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF8B8B9E),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
