import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zinemo/theme/app_theme.dart';
import 'package:zinemo/services/tmdb_service.dart';
import 'package:zinemo/services/log_service.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/providers/app_providers.dart';
import 'package:zinemo/screens/watchlist/watchlist_screen.dart';
import 'package:zinemo/widgets/content_actions_sheet.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late TextEditingController _searchController;
  late Timer _debounceTimer;
  String _searchQuery = '';
  bool _isSearching = false;
  List<Content> _searchResults = [];
  String? _error;
  final Set<int> _favoriteContentIds = <int>{};
  final Set<int> _favoriteLoadingIds = <int>{};

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _debounceTimer = Timer(Duration.zero, () {}); // Initialize with dummy timer
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _isSearching = value.isNotEmpty;
      _error = null;
    });

    _debounceTimer.cancel();

    if (value.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    // Debounce search for 500ms
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _performSearch(value);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;

    setState(() => _isSearching = true);

    try {
      final results = await TMDBService.search(query);

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Search failed: $e';
        _isSearching = false;
      });
    }
  }

  void _showContentActions(Content content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ContentActionsSheet(
        content: content,
        onDismiss: () => Navigator.of(ctx).pop(),
        onActionCompleted: () {
          ref.invalidate(watchHistoryProvider);
          ref.invalidate(watchlistProvider);
          ref.invalidate(continueWatchingProvider);
          ref.invalidate(contentRatingsProvider);
          ref.invalidate(episodeRatingsProvider);
        },
      ),
    );
  }

  Future<void> _addToFavorites(Content content) async {
    if (_favoriteLoadingIds.contains(content.tmdbId)) {
      return;
    }

    setState(() => _favoriteLoadingIds.add(content.tmdbId));
    try {
      await LogService.quickLog(
        tmdbId: content.tmdbId,
        mediaType: content.mediaType,
        status: 'watchlist',
        liked: true,
      );

      if (!mounted) {
        return;
      }

      setState(() => _favoriteContentIds.add(content.tmdbId));
      ref.invalidate(watchHistoryProvider);
      ref.invalidate(watchlistProvider);
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(contentRatingsProvider);
      ref.invalidate(episodeRatingsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${content.title} to favorites')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add favorite: $e')));
    } finally {
      if (mounted) {
        setState(() => _favoriteLoadingIds.remove(content.tmdbId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search'), elevation: 0),
      body: Column(
        children: [
          // Search bar with hero animation
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search movies, shows, people...',
                prefixIcon: const Icon(Icons.search, size: 24),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),

          // Results, loading, or empty state
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 100),
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ),
      );
    }

    if (_searchQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                  Icons.search_outlined,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.2),
                )
                .animate()
                .fadeIn(duration: 600.ms)
                .moveY(begin: 20, duration: 600.ms),
            const SizedBox(height: 16),
            Text(
              'Search for movies,\nshows, and more',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ).animate().fadeIn(duration: 600.ms, delay: 100.ms),
          ],
        ),
      );
    }

    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Searching for "$_searchQuery"...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found\nfor "$_searchQuery"',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    // Results grid with staggered animation
    return CustomScrollView(
      slivers: [
        SliverAnimatedGrid(
          initialItemCount: _searchResults.length,
          itemBuilder: (ctx, index, animation) {
            final content = _searchResults[index];
            return ScaleTransition(
              scale: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.1),
                  end: Offset.zero,
                ).animate(animation),
                child: _buildSearchResultTile(content),
              ),
            );
          },
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
        ),
      ],
    );
  }

  // Individual search result card with Hero animation
  Widget _buildSearchResultTile(Content content) {
    final isFavorite = _favoriteContentIds.contains(content.tmdbId);
    final isFavoriteLoading = _favoriteLoadingIds.contains(content.tmdbId);

    return GestureDetector(
      onTap: () {
        final routeName = content.mediaType == 'tv'
            ? 'tv-detail'
            : 'movie-detail';
        context.pushNamed(
          routeName,
          pathParameters: {'tmdbId': content.tmdbId.toString()},
          extra: content,
        );
      },
      onLongPress: () => _showContentActions(content),
      child: Card(
        elevation: 0,
        color: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster image
            Hero(
              tag: 'poster-${content.tmdbId}',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl:
                      content.posterPath ??
                      'https://via.placeholder.com/342x513',
                  fit: BoxFit.cover,
                  placeholder: (ctx, url) => Container(
                    color: AppTheme.card,
                    child: Icon(
                      Icons.movie,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  errorWidget: (ctx, url, error) => Container(
                    color: AppTheme.card,
                    child: Icon(
                      Icons.error,
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ),

            // Gradient overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: isFavoriteLoading
                      ? null
                      : () => _addToFavorites(content),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: isFavoriteLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 18,
                            color: isFavorite
                                ? const Color(0xFFFF5D8F)
                                : Colors.white,
                          ),
                  ),
                ),
              ),
            ),

            // Title and rating at bottom
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          content.releaseDate?.year.toString() ?? 'N/A',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.white70),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.star,
                                size: 12,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                (content.voteAverage ?? 0.0).toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
