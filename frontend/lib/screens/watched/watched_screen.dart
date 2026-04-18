import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/theme/app_theme.dart';

/// Filter provider for watched sorting
final watchedSortProvider = StateProvider<String>((ref) => 'date_watched');

/// Watched provider - filters logs by watched status
final watchedProvider = FutureProvider<List<Log>>((ref) async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];

    final logsData = await Supabase.instance.client
        .from('logs')
        .select()
        .eq('user_id', userId)
        .eq('status', 'watched')
        .order('watched_date', ascending: false);

    return (logsData as List)
        .map((item) => Log.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  } catch (e) {
    return [];
  }
});

class WatchedScreen extends ConsumerWidget {
  const WatchedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchedAsync = ref.watch(watchedProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watched'),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_outlined),
            onSelected: (sort) {
              ref.read(watchedSortProvider.notifier).state = sort;
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'date_watched',
                child: Text('Recently Watched'),
              ),
              const PopupMenuItem(value: 'title', child: Text('Title (A-Z)')),
              const PopupMenuItem(
                value: 'rating',
                child: Text('Highest Rated'),
              ),
            ],
          ),
        ],
      ),
      body: watchedAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You haven\'t watched anything yet',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start logging your movies',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final log = logs[idx];
              return _buildWatchedCard(context, log);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error loading watched: $e')),
      ),
    );
  }

  Widget _buildWatchedCard(BuildContext context, Log log) {
    return GestureDetector(
      onTap: () {
        final routeName = log.mediaType == 'tv' ? 'tv-detail' : 'movie-detail';
        context.pushNamed(
          routeName,
          pathParameters: {'tmdbId': log.tmdbId.toString()},
        );
      },
      child: Card(
        color: AppTheme.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Poster thumbnail
              Container(
                width: 60,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[800],
                ),
                child: Center(
                  child: Icon(
                    Icons.movie_outlined,
                    size: 32,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Movie #${log.tmdbId}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Rating
                    if (log.rating != null)
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < (log.rating ?? 0).toInt()
                                ? Icons.star
                                : Icons.star_outline,
                            size: 14,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Watch date
                    Text(
                      log.watchedDate?.toString().split(' ')[0] ??
                          'Date unknown',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),

              // Right side actions
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (log.rewatch)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Rewatched',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.primary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  if (log.liked)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Icon(
                        Icons.favorite,
                        size: 18,
                        color: Colors.red.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1);
  }
}
