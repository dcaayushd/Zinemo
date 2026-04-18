import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/services/tmdb_service.dart';
import 'package:zinemo/theme/app_theme.dart';

enum _LibraryType { shows, movies }

enum _ProgressCategory { progress, watchlist, watched, hold }

class TvProgressItem {
  const TvProgressItem({
    required this.log,
    required this.show,
    required this.currentSeason,
    required this.currentEpisode,
    required this.watchedEpisodes,
    required this.totalEpisodes,
    required this.totalSeasons,
    required this.progress,
  });

  final Log log;
  final Content show;
  final int currentSeason;
  final int currentEpisode;
  final int watchedEpisodes;
  final int totalEpisodes;
  final int totalSeasons;
  final double progress;

  bool get isOnHold => log.status == LogStatus.dropped;

  bool get isWatching => log.status == LogStatus.watching;

  bool get isWatchlist =>
      log.status == LogStatus.watchlist || log.status == LogStatus.planToWatch;

  bool get isWatched => log.status == LogStatus.watched;

  bool get hasUpcoming =>
      show.nextAirDate != null &&
      show.nextAirDate!.isAfter(
        DateTime.now().subtract(const Duration(days: 1)),
      );

  int get episodesLeft => math.max(0, totalEpisodes - watchedEpisodes);

  String get progressLabel =>
      '$watchedEpisodes/$totalEpisodes ($episodesLeft left)';

  String get episodeLabel =>
      'S.${_twoDigits(currentSeason)} E.${_twoDigits(currentEpisode)}';

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');
}

class MovieProgressItem {
  const MovieProgressItem({required this.log, required this.movie});

  final Log log;
  final Content movie;
}

int? _extractTagInt(List<String> tags, String key) {
  for (final tag in tags) {
    if (tag.startsWith('$key:')) {
      final value = int.tryParse(tag.split(':').last.trim());
      if (value != null) {
        return value;
      }
    }
  }
  return null;
}

({int season, int episode}) _extractSeasonEpisode(List<String> tags) {
  for (final tag in tags) {
    final match = RegExp(r'[sS](\d+)[\s._-]*[eE](\d+)').firstMatch(tag);
    if (match != null) {
      final season = int.tryParse(match.group(1) ?? '');
      final episode = int.tryParse(match.group(2) ?? '');
      if (season != null && episode != null) {
        return (season: season, episode: episode);
      }
    }
  }

  final seasonFromTag = _extractTagInt(tags, 'season');
  final episodeFromTag = _extractTagInt(tags, 'episode');
  return (season: seasonFromTag ?? 1, episode: episodeFromTag ?? 0);
}

Set<String> _extractEpisodeMarkerCodes(List<String> tags) {
  final codes = <String>{};
  for (final tag in tags) {
    if (tag.startsWith('ep_watched:')) {
      final code = tag.substring('ep_watched:'.length).trim().toUpperCase();
      if (RegExp(r'^S\d{2}E\d{2}$').hasMatch(code)) {
        codes.add(code);
      }
      continue;
    }

    if (tag.startsWith('ep_rating:')) {
      final parts = tag.split(':');
      if (parts.length < 3) {
        continue;
      }

      final code = parts[1].trim().toUpperCase();
      if (RegExp(r'^S\d{2}E\d{2}$').hasMatch(code)) {
        codes.add(code);
      }
    }
  }

  return codes;
}

({int season, int episode})? _latestMarkerEpisode(
  Set<String> codes,
  int totalSeasons,
  int totalEpisodes,
) {
  if (codes.isEmpty) {
    return null;
  }

  final epsPerSeason = math.max(1, (totalEpisodes / totalSeasons).ceil());
  var bestProgress = -1;
  var bestSeason = 1;
  var bestEpisode = 1;

  for (final code in codes) {
    final match = RegExp(r'^S(\d{2})E(\d{2})$').firstMatch(code);
    if (match == null) {
      continue;
    }

    final season = int.tryParse(match.group(1) ?? '');
    final episode = int.tryParse(match.group(2) ?? '');
    if (season == null || episode == null || season <= 0 || episode <= 0) {
      continue;
    }

    final progress = ((season - 1) * epsPerSeason) + episode;
    if (progress > bestProgress) {
      bestProgress = progress;
      bestSeason = season;
      bestEpisode = episode;
    }
  }

  if (bestProgress < 0) {
    return null;
  }

  return (season: bestSeason, episode: bestEpisode);
}

TvProgressItem _buildTvProgressItem(Log log, Content show) {
  final totalEpisodes = math.max(1, show.totalEpisodes ?? 24);
  final totalSeasons = math.max(1, show.totalSeasons ?? 1);

  final parsed = _extractSeasonEpisode(log.tags);
  final parsedProgress = _extractTagInt(log.tags, 'progress');
  final episodeMarkers = _extractEpisodeMarkerCodes(log.tags);
  final watchedFromMarkers = episodeMarkers.length.clamp(0, totalEpisodes);

  final fallbackWatched = switch (log.status) {
    LogStatus.watched => totalEpisodes,
    LogStatus.watching => 1,
    _ => 0,
  };

  final watchedEpisodes = log.status == LogStatus.watched
      ? totalEpisodes
      : math.max(
          (parsedProgress ?? fallbackWatched).clamp(0, totalEpisodes),
          watchedFromMarkers,
        );

  var season = parsed.season;
  var episode = parsed.episode;

  final latestMarker = _latestMarkerEpisode(
    episodeMarkers,
    totalSeasons,
    totalEpisodes,
  );
  if (latestMarker != null) {
    season = latestMarker.season;
    episode = latestMarker.episode;
  }

  if (season <= 0) season = 1;
  if (episode < 0) episode = 0;

  if (episode == 0 && watchedEpisodes > 0) {
    final epsPerSeason = math.max(1, (totalEpisodes / totalSeasons).ceil());
    season = ((watchedEpisodes - 1) ~/ epsPerSeason) + 1;
    episode = ((watchedEpisodes - 1) % epsPerSeason) + 1;
  }

  if (log.status == LogStatus.watched) {
    season = show.lastSeasonNumber ?? totalSeasons;
    episode = show.lastEpisodeNumber ?? totalEpisodes;
  }

  final progress = watchedEpisodes / totalEpisodes;

  return TvProgressItem(
    log: log,
    show: show,
    currentSeason: season,
    currentEpisode: episode,
    watchedEpisodes: watchedEpisodes,
    totalEpisodes: totalEpisodes,
    totalSeasons: totalSeasons,
    progress: progress,
  );
}

List<String> _upsertProgressTags({
  required List<String> tags,
  required int season,
  required int episode,
  required int watchedEpisodes,
}) {
  final cleaned = tags.where((tag) {
    return !tag.startsWith('season:') &&
        !tag.startsWith('episode:') &&
        !tag.startsWith('progress:') &&
        !RegExp(r'^[sS]\d+[\s._-]*[eE]\d+$').hasMatch(tag);
  }).toList();

  cleaned.addAll([
    'season:$season',
    'episode:$episode',
    'progress:$watchedEpisodes',
    'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
    'ep_watched:S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
  ]);

  return cleaned.toSet().toList();
}

final tvProgressProvider = FutureProvider<List<TvProgressItem>>((ref) async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await Supabase.instance.client
        .from('logs')
        .select()
        .eq('user_id', userId)
        .eq('media_type', 'tv')
        .inFilter('status', [
          'watching',
          'watchlist',
          'plan_to_watch',
          'dropped',
          'watched',
        ])
        .order('updated_at', ascending: false);

    final logs = (rows as List)
        .map((item) => Log.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    final resolved = await Future.wait(
      logs.map((log) async {
        final details = await TMDBService.getDetails(log.tmdbId, 'tv');
        if (details == null) return null;
        return _buildTvProgressItem(log, details);
      }),
    );

    return resolved.whereType<TvProgressItem>().toList();
  } catch (_) {
    return [];
  }
});

final movieProgressProvider = FutureProvider<List<MovieProgressItem>>((
  ref,
) async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return [];

    final rows = await Supabase.instance.client
        .from('logs')
        .select()
        .eq('user_id', userId)
        .eq('media_type', 'movie')
        .inFilter('status', [
          'watching',
          'watchlist',
          'plan_to_watch',
          'dropped',
          'watched',
        ])
        .order('updated_at', ascending: false)
        .limit(30);

    final logs = (rows as List)
        .map((item) => Log.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    final resolved = await Future.wait(
      logs.map((log) async {
        final details = await TMDBService.getDetails(log.tmdbId, 'movie');
        if (details == null) return null;
        return MovieProgressItem(log: log, movie: details);
      }),
    );

    return resolved.whereType<MovieProgressItem>().toList();
  } catch (_) {
    return [];
  }
});

class WatchingScreen extends ConsumerStatefulWidget {
  const WatchingScreen({super.key});

  @override
  ConsumerState<WatchingScreen> createState() => _WatchingScreenState();
}

class _WatchingScreenState extends ConsumerState<WatchingScreen> {
  _LibraryType _libraryType = _LibraryType.shows;
  _ProgressCategory _category = _ProgressCategory.progress;

  Future<void> _advanceEpisode(TvProgressItem item) async {
    final epsPerSeason = math.max(
      1,
      (item.totalEpisodes / item.totalSeasons).ceil(),
    );

    var nextWatched = (item.watchedEpisodes + 1).clamp(0, item.totalEpisodes);
    var season = item.currentSeason;
    var episode = item.currentEpisode + 1;

    if (episode > epsPerSeason) {
      season += 1;
      episode = 1;
    }

    season = season.clamp(1, item.totalSeasons);

    final tags = _upsertProgressTags(
      tags: item.log.tags,
      season: season,
      episode: episode,
      watchedEpisodes: nextWatched,
    );

    final nextStatus = nextWatched >= item.totalEpisodes
        ? LogStatus.watched.name
        : LogStatus.watching.name;

    await Supabase.instance.client
        .from('logs')
        .update({
          'tags': tags,
          'status': nextStatus,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', item.log.id);

    if (mounted) {
      ref.invalidate(tvProgressProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Progress updated for ${item.show.title}')),
      );
    }
  }

  Future<void> _toggleHold(TvProgressItem item) async {
    final nextStatus = item.isOnHold
        ? LogStatus.watching.name
        : LogStatus.dropped.name;

    await Supabase.instance.client
        .from('logs')
        .update({
          'status': nextStatus,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', item.log.id);

    if (mounted) {
      ref.invalidate(tvProgressProvider);
      final label = item.isOnHold ? 'Moved to Watching' : 'Moved to On Hold';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(label)));
    }
  }

  void _openDetails(int tmdbId, Content content) {
    final routeName = content.mediaType == 'tv' ? 'tv-detail' : 'movie-detail';
    context.pushNamed(
      routeName,
      pathParameters: {'tmdbId': tmdbId.toString()},
      extra: content,
    );
  }

  List<TvProgressItem> _filteredShows(List<TvProgressItem> items) {
    List<TvProgressItem> filtered;

    switch (_category) {
      case _ProgressCategory.progress:
        filtered = items.where((item) => item.isWatching).toList();
        break;
      case _ProgressCategory.watchlist:
        filtered = items.where((item) => item.isWatchlist).toList();
        break;
      case _ProgressCategory.watched:
        filtered = items.where((item) => item.isWatched).toList();
        break;
      case _ProgressCategory.hold:
        filtered = items.where((item) => item.isOnHold).toList();
        break;
    }

    filtered.sort((a, b) => b.log.updatedAt.compareTo(a.log.updatedAt));
    return filtered;
  }

  List<MovieProgressItem> _filteredMovies(List<MovieProgressItem> items) {
    List<MovieProgressItem> filtered;

    switch (_category) {
      case _ProgressCategory.progress:
        filtered = items
            .where((item) => item.log.status == LogStatus.watching)
            .toList();
        break;
      case _ProgressCategory.watchlist:
        filtered = items
            .where(
              (item) =>
                  item.log.status == LogStatus.watchlist ||
                  item.log.status == LogStatus.planToWatch,
            )
            .toList();
        break;
      case _ProgressCategory.watched:
        filtered = items
            .where((item) => item.log.status == LogStatus.watched)
            .toList();
        break;
      case _ProgressCategory.hold:
        filtered = items
            .where((item) => item.log.status == LogStatus.dropped)
            .toList();
        break;
    }

    filtered.sort((a, b) => b.log.updatedAt.compareTo(a.log.updatedAt));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final tvAsync = ref.watch(tvProgressProvider);
    final moviesAsync = ref.watch(movieProgressProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 14),
              _buildLibrarySwitcher(context),
              const SizedBox(height: 10),
              _buildFilterChips(context),
              const SizedBox(height: 12),
              Expanded(
                child: _libraryType == _LibraryType.shows
                    ? _buildShowsBody(context, tvAsync)
                    : _buildMoviesBody(context, moviesAsync),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.card.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(Icons.search, color: Colors.white.withValues(alpha: 0.75)),
                const SizedBox(width: 10),
                Text(
                  'Search progress',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton(onPressed: () {}, icon: const Icon(Icons.verified_outlined)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.settings)),
      ],
    );
  }

  Widget _buildLibrarySwitcher(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _libraryType = _LibraryType.shows),
          child: Text(
            'Shows',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: _libraryType == _LibraryType.shows
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: () => setState(() => _libraryType = _LibraryType.movies),
          child: Text(
            'Movies',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: _libraryType == _LibraryType.movies
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final chips = <_ProgressCategory, String>{
      _ProgressCategory.progress: 'Progress',
      _ProgressCategory.watchlist: 'Watchlist',
      _ProgressCategory.watched: 'Watched',
      _ProgressCategory.hold: 'Hold',
    };

    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          final entry = chips.entries.elementAt(i);
          final selected = entry.key == _category;
          return ChoiceChip(
            selected: selected,
            onSelected: (_) => setState(() => _category = entry.key),
            label: Text(entry.value),
            selectedColor: AppTheme.primary.withValues(alpha: 0.2),
            backgroundColor: Colors.transparent,
            side: BorderSide(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.7)
                  : Colors.white.withValues(alpha: 0.24),
            ),
            labelStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: chips.length,
      ),
    );
  }

  Widget _buildShowsBody(
    BuildContext context,
    AsyncValue<List<TvProgressItem>> tvAsync,
  ) {
    return tvAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load shows: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.tv_off_rounded,
            title: 'No TV progress yet',
            subtitle:
                'Mark shows as watching and your episode timeline appears here.',
          );
        }

        final filtered = _filteredShows(items);
        if (filtered.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.filter_list_off,
            title: 'Nothing in this category',
            subtitle: 'Switch category to see more titles.',
          );
        }

        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, idx) => _buildShowCard(context, filtered[idx]),
        );
      },
    );
  }

  Widget _buildMoviesBody(
    BuildContext context,
    AsyncValue<List<MovieProgressItem>> moviesAsync,
  ) {
    return moviesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Failed to load movies: $e')),
      data: (items) {
        if (items.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.local_movies_outlined,
            title: 'No movie progress yet',
            subtitle: 'Start a movie and mark it as watching to track it here.',
          );
        }

        final filtered = _filteredMovies(items);
        if (filtered.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.filter_list_off,
            title: 'Nothing in this category',
            subtitle: 'Switch category to see more titles.',
          );
        }

        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, idx) => _buildMovieCard(context, filtered[idx]),
        );
      },
    );
  }

  Widget _buildShowCard(BuildContext context, TvProgressItem item) {
    final isCompleted = item.isWatched;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster with badge
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: item.show.posterUrl,
                  width: 90,
                  height: 136,
                  fit: BoxFit.cover,
                ),
              ),
              // Status badge
              if (isCompleted)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Completed',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              else if (item.isOnHold)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'On Hold',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  item.show.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),

                // Episode info with season details
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_outlined,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        item.episodeLabel,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${item.totalSeasons} seasons',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Next episode name if available
                if (item.show.nextEpisodeName != null &&
                    item.show.nextEpisodeName!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Next: ${item.show.nextEpisodeName!}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                // Progress info
                Row(
                  children: [
                    Text(
                      item.progressLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(item.progress * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: item.progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(
                      isCompleted ? AppTheme.success : AppTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            _openDetails(item.show.tmdbId, item.show),
                        icon: const Icon(Icons.info_outline, size: 16),
                        label: const Text('Details'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.secondary.withValues(
                            alpha: 0.15,
                          ),
                          foregroundColor: AppTheme.secondary,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: OutlinedButton(
                        onPressed: () => _toggleHold(item),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text(
                          item.isOnHold ? 'Resume' : 'On Hold',
                          style: Theme.of(
                            context,
                          ).textTheme.labelLarge?.copyWith(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      width: 40,
                      child: FilledButton(
                        onPressed: item.isWatched
                            ? null
                            : () => _advanceEpisode(item),
                        style: FilledButton.styleFrom(
                          backgroundColor: isCompleted
                              ? AppTheme.success.withValues(alpha: 0.6)
                              : AppTheme.primary,
                          padding: EdgeInsets.zero,
                        ),
                        child: Icon(
                          isCompleted ? Icons.check_circle : Icons.add,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMovieCard(BuildContext context, MovieProgressItem item) {
    final isOnHold = item.log.status == LogStatus.dropped;
    final isWatched = item.log.status == LogStatus.watched;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openDetails(item.movie.tmdbId, item.movie),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: item.movie.posterUrl,
                    width: 80,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                if (isWatched)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.movie.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isOnHold
                          ? AppTheme.warning.withValues(alpha: 0.12)
                          : AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isOnHold
                            ? AppTheme.warning.withValues(alpha: 0.3)
                            : AppTheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      isOnHold ? 'Hold' : item.log.status.displayName,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isOnHold ? AppTheme.warning : AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 16,
                        color: AppTheme.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        (item.movie.voteAverage ?? 0).toStringAsFixed(1),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (item.log.rating != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.secondary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            'You: ${item.log.rating}★',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppTheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 60, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontSize: 28),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
