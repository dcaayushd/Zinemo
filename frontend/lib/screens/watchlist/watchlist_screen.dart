import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/theme/app_theme.dart';

/// Filter provider for watchlist sorting
final watchlistSortProvider = StateProvider<String>((ref) => 'date_added');

/// Watchlist provider - filters logs by watchlist status
final watchlistProvider = FutureProvider<List<Log>>((ref) async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];

    final logsData = await Supabase.instance.client
        .from('logs')
        .select()
        .eq('user_id', userId)
        .eq('status', 'watchlist')
        .order('created_at', ascending: false);

    return (logsData as List)
        .map((item) => Log.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  } catch (e) {
    return [];
  }
});

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlistAsync = ref.watch(watchlistProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Watchlist'),
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_outlined),
            onSelected: (sort) {
              ref.read(watchlistSortProvider.notifier).state = sort;
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'date_added',
                child: Text('Recently Added'),
              ),
              const PopupMenuItem(value: 'title', child: Text('Title (A-Z)')),
              const PopupMenuItem(value: 'rating', child: Text('Rating')),
            ],
          ),
        ],
      ),
      body: watchlistAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bookmark_outline,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your watchlist is empty',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add movies to watch later',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.6,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: logs.length,
            itemBuilder: (context, idx) {
              final log = logs[idx];
              return _buildWatchlistCard(context, log);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error loading watchlist: $e')),
      ),
    );
  }

  Widget _buildWatchlistCard(BuildContext context, Log log) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  color: Colors.grey[800],
                ),
                child: Stack(
                  children: [
                    // Poster image (placeholder for now)
                    Center(
                      child: Icon(
                        Icons.movie_outlined,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    // Added date badge
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Added',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: Colors.amber, fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Movie #${log.tmdbId}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.bookmark,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Watchlist',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.primary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).scale();
  }
}
