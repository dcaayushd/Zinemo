import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingPreferencesScreen extends ConsumerStatefulWidget {
  const OnboardingPreferencesScreen({super.key});

  @override
  ConsumerState<OnboardingPreferencesScreen> createState() =>
      _OnboardingPreferencesScreenState();
}

class _OnboardingPreferencesScreenState
    extends ConsumerState<OnboardingPreferencesScreen> {
  final List<int> _selectedGenreIds = [];
  bool _isLoading = false;

  static const List<(int, String)> _genres = [
    (28, 'Action'),
    (12, 'Adventure'),
    (16, 'Animation'),
    (35, 'Comedy'),
    (80, 'Crime'),
    (18, 'Drama'),
    (14, 'Fantasy'),
    (27, 'Horror'),
    (10749, 'Romance'),
    (878, 'Sci-Fi'),
    (53, 'Thriller'),
    (10752, 'War'),
  ];

  @override
  void initState() {
    super.initState();
    _checkExistingGenrePreferences();
  }

  Future<List<int>> _loadSavedGenreIds() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return [];
    }

    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('preferences')
          .eq('id', user.id)
          .single();

      final preferences = row['preferences'];
      if (preferences is! Map) {
        return [];
      }

      final prefs = Map<String, dynamic>.from(preferences);
      final dynamic genres = prefs['favorite_genre_ids'] ?? prefs['genres'];
      if (genres is! List) {
        return [];
      }

      return genres
          .map((item) => int.tryParse(item.toString()))
          .whereType<int>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _checkExistingGenrePreferences() async {
    final savedGenres = await _loadSavedGenreIds();
    if (!mounted) {
      return;
    }

    if (savedGenres.isNotEmpty) {
      context.go('/home');
      return;
    }
  }

  Future<void> _completeOnboarding() async {
    if (_selectedGenreIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one genre')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        return;
      }

      Map<String, dynamic>? existingProfile;
      try {
        final row = await supabase
            .from('profiles')
            .select('username, display_name, preferences')
            .eq('id', user.id)
            .single();
        existingProfile = Map<String, dynamic>.from(row);
      } catch (_) {
        existingProfile = null;
      }

      final existingPreferencesRaw = existingProfile?['preferences'];
      final existingPreferences = existingPreferencesRaw is Map
          ? Map<String, dynamic>.from(existingPreferencesRaw)
          : <String, dynamic>{};

      final mergedPreferences = {
        ...existingPreferences,
        'favorite_genre_ids': _selectedGenreIds,
        'genres': _selectedGenreIds,
        'onboarding_completed': true,
      };

      if (existingProfile != null) {
        await supabase
            .from('profiles')
            .update({
              'preferences': mergedPreferences,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', user.id);
      } else {
        final username = user.email?.contains('@') == true
            ? user.email!.split('@')[0]
            : 'user_${user.id.substring(0, 8)}';

        await supabase.from('profiles').insert({
          'id': user.id,
          'username': username,
          'display_name': user.userMetadata?['full_name'] ?? user.email,
          'preferences': mergedPreferences,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing onboarding: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 48,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _completeOnboarding,
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Continue to Home', style: TextStyle(fontSize: 15)),
        ),
      ),
    );
  }

  Widget _buildGenreSelection() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pick your favourite genres',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'You only need to do this once. We use these genres for your recommendations.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _genres.asMap().entries.map((entry) {
                final index = entry.key;
                final genre = entry.value;
                final isSelected = _selectedGenreIds.contains(genre.$1);

                return _buildGenreChip(
                  genre: genre,
                  isSelected: isSelected,
                  delay: Duration(milliseconds: index * 45),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedGenreIds.add(genre.$1);
                      } else {
                        _selectedGenreIds.remove(genre.$1);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenreChip({
    required (int, String) genre,
    required bool isSelected,
    required Duration delay,
    required Function(bool) onSelected,
  }) {
    return FilterChip(
          label: Text(genre.$2),
          selected: isSelected,
          onSelected: onSelected,
          backgroundColor: Colors.transparent,
          selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.8),
          showCheckmark: false,
          side: BorderSide(
            color: isSelected ? Theme.of(context).primaryColor : Colors.white30,
            width: isSelected ? 1.8 : 1,
          ),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
            fontSize: 13,
          ),
        )
        .animate()
        .fadeIn(duration: 360.ms, delay: delay)
        .scale(
          begin: const Offset(0.9, 0.9),
          end: const Offset(1.0, 1.0),
          duration: 360.ms,
          delay: delay,
          curve: Curves.easeOutBack,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Your Genres'),
        elevation: 0,
        centerTitle: true,
      ),
      body: _buildGenreSelection(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }
}
