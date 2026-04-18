import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with TickerProviderStateMixin {
  late TextEditingController _emailController;
  late TextEditingController _passwordController;
  late PageController _posterController;
  late AnimationController _cardSlideController;
  late AnimationController _passwordToggleController;

  bool _isLoading = false;
  String? _errorMessage;
  bool _isLogin = true;
  bool _showPassword = false;

  // Sample movie posters for background collage (using TMDB weighted average)
  static const List<String> _posterUrls = [
    'https://image.tmdb.org/t/p/w342/e0nqv5YOINX7ia8b8osxrZaqdz9.jpg',
    'https://image.tmdb.org/t/p/w342/6KErMXUP096HD4JGoDcIrADT3Ka.jpg',
    'https://image.tmdb.org/t/p/w342/xlVqCIkscV7a8qy6hfb9yEwKz6x.jpg',
    'https://image.tmdb.org/t/p/w342/qJ2tW6WMUDux911r6m7haGHDeQg.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController();
    _passwordController = TextEditingController();
    _posterController = PageController(viewportFraction: 0.6);
    _cardSlideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _passwordToggleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Auto-scroll posters
    _cardSlideController.forward();

    // Auto-scroll posters every 4 seconds
    Future.delayed(const Duration(seconds: 2), _autoScrollPosters);
  }

  void _autoScrollPosters() {
    if (mounted && !_isLoading) {
      _posterController.nextPage(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) _autoScrollPosters();
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _posterController.dispose();
    _cardSlideController.dispose();
    _passwordToggleController.dispose();
    super.dispose();
  }

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

  Future<void> _routeAfterAuth() async {
    final hasGenres = await _hasSavedGenrePreferences();
    if (!mounted) {
      return;
    }

    context.go(hasGenres ? '/home' : '/onboarding');
  }

  Future<void> _handleEmailAuth() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;

      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }

      if (mounted) {
        await _routeAfterAuth();
      }
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleGoogleAuth() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google);
      if (!mounted) {
        return;
      }

      final hasSession = Supabase.instance.client.auth.currentSession != null;
      if (hasSession) {
        await _routeAfterAuth();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Google sign-in failed: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated poster background (PageView auto-scroll, blurred + dark overlay)
          Positioned.fill(
            child: PageView.builder(
              controller: _posterController,
              pageSnapping: true,
              itemCount: _posterUrls.length,
              itemBuilder: (ctx, idx) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      _posterUrls[idx],
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) =>
                          Container(color: Colors.black),
                    ),
                    // Dark overlay + blur
                    BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Glassmorphism card sliding up from bottom
          SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 1.2),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _cardSlideController,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.78,
              minChildSize: 0.78,
              maxChildSize: 0.95,
              builder: (ctx, scrollCtrl) {
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1.5,
                          ),
                        ),
                      ),
                      child: SingleChildScrollView(
                        controller: scrollCtrl,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 32,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header
                              Text(
                                _isLogin ? 'Welcome Back' : 'Create Account',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isLogin
                                    ? 'Log in to continue tracking your movies'
                                    : 'Start your movie journey today',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: Colors.white70),
                              ),
                              const SizedBox(height: 32),

                              // Email field with custom focus animation
                              _buildAnimatedTextField(
                                controller: _emailController,
                                label: 'Email Address',
                                hint: 'you@example.com',
                                keyboardType: TextInputType.emailAddress,
                                enabled: !_isLoading,
                              ),
                              const SizedBox(height: 16),

                              // Password field with eye toggle
                              _buildPasswordField(),
                              const SizedBox(height: 8),

                              // Forgot password link (login only)
                              if (_isLogin)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _isLoading ? null : () {},
                                    child: const Text('Forgot password?'),
                                  ),
                                ),

                              const SizedBox(height: 24),

                              // Error message
                              if (_errorMessage != null)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.2),
                                    border: Border.all(
                                      color: Colors.red.withValues(alpha: 0.5),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 24),

                              // Sign in / Sign up button
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: _isLoading
                                      ? null
                                      : _handleEmailAuth,
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 24,
                                          width: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                      : Text(
                                          _isLogin
                                              ? 'Sign In'
                                              : 'Create Account',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Divider
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Text(
                                      'OR',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.white54),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 16),

                              // OAuth buttons
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: _isLoading
                                      ? null
                                      : _handleGoogleAuth,
                                  icon: const Text(
                                    '🔍',
                                    style: TextStyle(fontSize: 20),
                                  ),
                                  label: const Text('Continue with Google'),
                                ),
                              ),

                              const SizedBox(height: 12),

                              // Toggle auth mode
                              Center(
                                child: TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () {
                                          setState(() => _isLogin = !_isLogin);
                                          _errorMessage = null;
                                        },
                                  child: Text(
                                    _isLogin
                                        ? "Don't have an account? Sign up"
                                        : 'Already have an account? Sign in',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Custom animated text field with focus color transition
  Widget _buildAnimatedTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
    required bool enabled,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      enabled: enabled,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).primaryColor,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  // Password field with eye toggle rotation animation
  Widget _buildPasswordField() {
    return TextField(
      controller: _passwordController,
      obscureText: !_showPassword,
      enabled: !_isLoading,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: 'Password',
        labelStyle: const TextStyle(color: Colors.white70),
        hintText: 'Enter your password',
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).primaryColor,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        suffixIcon: RotationTransition(
          turns: Tween(begin: 0.0, end: 0.5).animate(_passwordToggleController),
          child: IconButton(
            icon: Icon(
              _showPassword ? Icons.visibility : Icons.visibility_off,
              color: Colors.white70,
            ),
            onPressed: () {
              setState(() => _showPassword = !_showPassword);
              if (_showPassword) {
                _passwordToggleController.forward();
              } else {
                _passwordToggleController.reverse();
              }
            },
          ),
        ),
      ),
    );
  }
}
