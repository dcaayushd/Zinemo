import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/models/content.dart';
import 'package:zinemo/models/log.dart';
import 'package:zinemo/models/user.dart';
import 'package:zinemo/services/hive_manager.dart';
import 'package:zinemo/services/recommendation_service.dart';
import 'package:zinemo/services/tmdb_service.dart';

typedef ContentRatingsParams = ({
  int tmdbId,
  String mediaType,
  double fallbackVoteAverage,
  int fallbackVoteCount,
});

typedef EpisodeRatingsParams = ({
  int tmdbId,
  String episodeCode,
  double fallbackVoteAverage,
  int fallbackVoteCount,
});

typedef UserMediaLogParams = ({int tmdbId, String mediaType});

class ContentRatingsSnapshot {
  final double averageStars;
  final int totalRatings;
  final List<double> distribution;
  final List<int> distributionCounts;

  const ContentRatingsSnapshot({
    required this.averageStars,
    required this.totalRatings,
    required this.distribution,
    required this.distributionCounts,
  });
}

String _detailCacheKey(int tmdbId, String mediaType) {
  return mediaType == 'tv' ? 'detail_tv_$tmdbId' : 'detail_$tmdbId';
}

Future<List<Content>> _mergeMediaFeeds(
  Future<List<Content>> Function(String mediaType) fetcher,
  String mediaType,
) async {
  if (mediaType != 'all') {
    return fetcher(mediaType);
  }

  final feeds = await Future.wait([fetcher('movie'), fetcher('tv')]);
  final merged = [...feeds[0], ...feeds[1]];
  final deduped = <String, Content>{
    for (final item in merged) '${item.mediaType}:${item.tmdbId}': item,
  };

  final sorted = deduped.values.toList()
    ..sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));

  return sorted;
}

Future<List<Content>> _resolveLogsToContent(List<Log> logs) async {
  if (logs.isEmpty) {
    return [];
  }

  final uniqueLogs = <Log>[];
  final seen = <String>{};
  for (final log in logs) {
    final key = '${log.mediaType}:${log.tmdbId}';
    if (seen.add(key)) {
      uniqueLogs.add(log);
    }
  }

  final futures = uniqueLogs.take(24).map((log) async {
    final cacheKey = _detailCacheKey(log.tmdbId, log.mediaType);
    final cached = HiveManager.getCachedContent(cacheKey);
    if (cached != null) {
      return cached;
    }

    try {
      final detail = await TMDBService.getDetails(log.tmdbId, log.mediaType);
      if (detail != null) {
        await HiveManager.cacheContent(cacheKey, detail);
      }
      return detail;
    } catch (_) {
      return null;
    }
  });

  final resolved = await Future.wait(futures);
  return resolved.whereType<Content>().toList();
}

int _ratingToBin(double rating) {
  final clamped = rating.clamp(1.0, 5.0);
  return ((((clamped - 1.0) / 4.0) * 8).round()).clamp(0, 8);
}

List<double> _buildTmdbFallbackDistribution(double fallbackStars) {
  const bins = 9;
  const sigma = 0.72;
  final center = fallbackStars.clamp(1.0, 5.0);

  final weights = List<double>.generate(bins, (index) {
    final binStars = 1.0 + (index / (bins - 1)) * 4.0;
    final delta = binStars - center;
    return math.exp(-(delta * delta) / (2 * sigma * sigma));
  });

  final total = weights.fold<double>(0.0, (sum, value) => sum + value);
  if (total <= 0) {
    return List<double>.filled(bins, 0.0);
  }

  return weights.map((value) => value / total).toList();
}

List<int> _buildCountsFromDistribution(
  List<double> distribution,
  int totalCount,
) {
  if (distribution.length != 9 || totalCount <= 0) {
    return List<int>.filled(9, 0);
  }

  final sanitized = distribution
      .map((value) => value.isFinite && value > 0 ? value : 0.0)
      .toList();
  final sum = sanitized.fold<double>(0.0, (acc, value) => acc + value);
  if (sum <= 0) {
    return List<int>.filled(9, 0);
  }

  final normalized = sanitized.map((value) => value / sum).toList();
  final counts = normalized
      .map((weight) => (weight * totalCount).floor())
      .toList();

  var assigned = counts.fold<int>(0, (acc, value) => acc + value);
  var remaining = totalCount - assigned;

  if (remaining > 0) {
    final remainders = List<(double, int)>.generate(
      normalized.length,
      (index) => ((normalized[index] * totalCount) - counts[index], index),
    )..sort((a, b) => b.$1.compareTo(a.$1));

    var cursor = 0;
    while (remaining > 0) {
      final idx = remainders[cursor % remainders.length].$2;
      counts[idx] += 1;
      remaining -= 1;
      cursor += 1;
    }
  }

  return counts;
}

ContentRatingsSnapshot _snapshotFromRatingsWithFallback({
  required List<double> ratings,
  required double fallbackStars,
  required int fallbackCount,
}) {
  final safeFallbackStars = fallbackStars.isFinite
      ? fallbackStars.clamp(0.0, 5.0)
      : 0.0;
  final fallbackCenter = safeFallbackStars > 0 ? safeFallbackStars : 3.0;

  final appRatings = ratings
      .where((rating) => rating.isFinite)
      .map((rating) => rating.clamp(0.5, 5.0))
      .toList();

  final appCounts = List<int>.filled(9, 0);
  for (final rating in appRatings) {
    appCounts[_ratingToBin(rating)] += 1;
  }

  final baselineCount = math.max(0, fallbackCount);
  final baselineDistribution = _buildTmdbFallbackDistribution(fallbackCenter);
  final baselineCounts = _buildCountsFromDistribution(
    baselineDistribution,
    baselineCount,
  );

  final mergedCounts = List<int>.generate(
    9,
    (index) => baselineCounts[index] + appCounts[index],
  );

  final mergedTotal = mergedCounts.fold<int>(0, (sum, value) => sum + value);
  if (mergedTotal <= 0) {
    return ContentRatingsSnapshot(
      averageStars: safeFallbackStars,
      totalRatings: 0,
      distribution: List<double>.filled(9, 0.0),
      distributionCounts: List<int>.filled(9, 0),
    );
  }

  final maxCount = mergedCounts.reduce(math.max).toDouble();
  final normalizedDistribution = maxCount == 0
      ? List<double>.filled(9, 0.0)
      : mergedCounts.map((count) => count / maxCount).toList();

  final appAverage = appRatings.isEmpty
      ? fallbackCenter
      : appRatings.reduce((a, b) => a + b) / appRatings.length;
  final weightedDenominator = baselineCount + appRatings.length;
  final weightedAverage = weightedDenominator > 0
      ? ((fallbackCenter * baselineCount) + (appAverage * appRatings.length)) /
            weightedDenominator
      : safeFallbackStars;

  return ContentRatingsSnapshot(
    averageStars: weightedAverage.clamp(0.0, 5.0),
    totalRatings: weightedDenominator,
    distribution: normalizedDistribution,
    distributionCounts: mergedCounts,
  );
}

UserPreferences _parseUserPreferences(dynamic rawPreferences) {
  if (rawPreferences is! Map) {
    return const UserPreferences();
  }

  final prefs = Map<String, dynamic>.from(rawPreferences);

  List<int> parseGenres(dynamic raw) {
    if (raw is! List) {
      return const <int>[];
    }

    return raw
        .map((item) {
          if (item is num) {
            return item.toInt();
          }
          return int.tryParse(item.toString());
        })
        .whereType<int>()
        .toList();
  }

  final genreIds = parseGenres(
    prefs['favorite_genre_ids'] ?? prefs['genres'] ?? const <dynamic>[],
  );

  final languages =
      (prefs['languages'] as List?)
          ?.map((item) => item.toString())
          .where((lang) => lang.isNotEmpty)
          .toList() ??
      const <String>['en'];

  return UserPreferences(
    favoriteGenreIds: genreIds,
    languages: languages.isEmpty ? const <String>['en'] : languages,
    simpleModeEnabled: prefs['simple_mode_enabled'] == true,
    privateDefaultLogs: prefs['private_default_logs'] == true,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// AUTH & USER PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final authUserProvider = FutureProvider<UserProfile?>((ref) async {
  final supabase = Supabase.instance.client;
  final currentUser = supabase.auth.currentUser;

  if (currentUser == null) {
    return null;
  }

  try {
    final rows = await supabase
        .from('profiles')
        .select()
        .eq('id', currentUser.id)
        .limit(1);

    if (rows.isNotEmpty) {
      final row = Map<String, dynamic>.from(rows.first as Map);
      final username = (row['username']?.toString().trim().isNotEmpty ?? false)
          ? row['username'].toString()
          : (currentUser.email?.split('@').first ?? 'zinemo_user');

      return UserProfile(
        id: row['id']?.toString() ?? currentUser.id,
        username: username,
        displayName: row['display_name']?.toString(),
        avatarUrl: row['avatar_url']?.toString(),
        bio: row['bio']?.toString(),
        preferences: _parseUserPreferences(row['preferences']),
        isPrivate: row['is_private'] == true,
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '') ??
            DateTime.now(),
        updatedAt:
            DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
            DateTime.now(),
      );
    }
  } catch (_) {
    // Fall through to auth metadata fallback.
  }

  final metadata = currentUser.userMetadata ?? <String, dynamic>{};
  final username = (metadata['username']?.toString().trim().isNotEmpty ?? false)
      ? metadata['username'].toString()
      : (currentUser.email?.split('@').first ?? 'zinemo_user');

  return UserProfile(
    id: currentUser.id,
    username: username,
    displayName: metadata['full_name']?.toString(),
    avatarUrl: metadata['avatar_url']?.toString(),
    bio: null,
    preferences: const UserPreferences(),
    isPrivate: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
});

/// Compatibility alias for older screens that still reference currentUserProvider.
final currentUserProvider = authUserProvider;

/// Whether the current user session is authenticated.
final isAuthenticatedProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  return user != null;
});

/// Whether onboarding preferences are completed.
final isOnboardedProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    return false;
  }
  return user.preferences.favoriteGenreIds.isNotEmpty;
});

/// User's latest log for a TMDB id regardless of media type.
final userLogProvider = FutureProvider.family<Log?, int>((ref, tmdbId) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    return null;
  }

  try {
    final response = await Supabase.instance.client
        .from('logs')
        .select()
        .eq('user_id', user.id)
        .eq('tmdb_id', tmdbId)
        .order('updated_at', ascending: false)
        .limit(1);

    final rows = response as List?;
    if (rows == null || rows.isEmpty) {
      return null;
    }

    return Log.fromJson(Map<String, dynamic>.from(rows.first as Map));
  } catch (_) {
    return null;
  }
});

/// User's latest log for a TMDB id and explicit media type.
final userMediaLogProvider = FutureProvider.family<Log?, UserMediaLogParams>((
  ref,
  params,
) async {
  final user = await ref.watch(authUserProvider.future);
  if (user == null) {
    return null;
  }

  try {
    final response = await Supabase.instance.client
        .from('logs')
        .select()
        .eq('user_id', user.id)
        .eq('tmdb_id', params.tmdbId)
        .eq('media_type', params.mediaType)
        .order('updated_at', ascending: false)
        .limit(1);

    final rows = response as List?;
    if (rows == null || rows.isEmpty) {
      return null;
    }

    return Log.fromJson(Map<String, dynamic>.from(rows.first as Map));
  } catch (_) {
    return null;
  }
});

/// User's watch history.
final watchHistoryProvider = FutureProvider<List<Log>>((ref) async {
  try {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return [];
    }

    final logsData = await Supabase.instance.client
        .from('logs')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (logsData as List)
        .map((item) => Log.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  } catch (_) {
    return HiveManager.getAllLogs();
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// CONTENT PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

/// Search provider with debounce.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Home feed media mode: all | movie | tv.
final homeMediaTypeProvider = StateProvider<String>((ref) => 'all');

final searchResultsProvider = FutureProvider<List<Content>>((ref) async {
  final query = ref.watch(searchQueryProvider).trim();
  if (query.isEmpty) {
    return [];
  }

  try {
    final results = await TMDBService.search(query);
    return results;
  } catch (_) {
    return [];
  }
});

/// Trending content.
final trendingByMediaProvider = FutureProvider.family<List<Content>, String>((
  ref,
  mediaType,
) async {
  try {
    final cacheKey = 'trending_v4_$mediaType';
    final cached = HiveManager.getCachedContentList(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return mediaType == 'all'
          ? cached
          : cached.where((item) => item.mediaType == mediaType).toList();
    }

    final trending = await _mergeMediaFeeds(
      (type) => TMDBService.getTrending(mediaType: type),
      mediaType,
    );

    if (trending.isNotEmpty) {
      await HiveManager.cacheContentList(cacheKey, trending);
    }

    return trending;
  } catch (_) {
    return [];
  }
});

final trendingProvider = FutureProvider<List<Content>>((ref) async {
  return ref.watch(trendingByMediaProvider('movie').future);
});

/// Top-rated content.
final topRatedByMediaProvider = FutureProvider.family<List<Content>, String>((
  ref,
  mediaType,
) async {
  try {
    final cacheKey = 'top_rated_v4_$mediaType';
    final cached = HiveManager.getCachedContentList(cacheKey);
    if (cached != null && cached.isNotEmpty) {
      return mediaType == 'all'
          ? cached
          : cached.where((item) => item.mediaType == mediaType).toList();
    }

    final topRated = await _mergeMediaFeeds(
      (type) => TMDBService.getTopRated(mediaType: type),
      mediaType,
    );

    if (topRated.isNotEmpty) {
      await HiveManager.cacheContentList(cacheKey, topRated);
    }

    return topRated;
  } catch (_) {
    return [];
  }
});

final topRatedProvider = FutureProvider<List<Content>>((ref) async {
  return ref.watch(topRatedByMediaProvider('movie').future);
});

/// New releases.
final newReleasesByMediaProvider = FutureProvider.family<List<Content>, String>(
  (ref, mediaType) async {
    try {
      final cacheKey = 'new_releases_v4_$mediaType';
      final cached = HiveManager.getCachedContentList(cacheKey);
      if (cached != null && cached.isNotEmpty) {
        return mediaType == 'all'
            ? cached
            : cached.where((item) => item.mediaType == mediaType).toList();
      }

      final newReleases = await _mergeMediaFeeds(
        (type) => TMDBService.getNewReleases(mediaType: type),
        mediaType,
      );

      if (newReleases.isNotEmpty) {
        await HiveManager.cacheContentList(cacheKey, newReleases);
      }

      return newReleases;
    } catch (_) {
      return [];
    }
  },
);

final newReleasesProvider = FutureProvider<List<Content>>((ref) async {
  return ref.watch(newReleasesByMediaProvider('movie').future);
});

/// Continue watching shelf from user logs.
final continueWatchingProvider = FutureProvider<List<Content>>((ref) async {
  try {
    final logs = await ref.watch(watchHistoryProvider.future);
    final watchingLogs = logs
        .where((log) => log.status == LogStatus.watching)
        .toList();

    if (watchingLogs.isEmpty) {
      return [];
    }

    return _resolveLogsToContent(watchingLogs);
  } catch (_) {
    return [];
  }
});

/// On hold + watchlist shelf from user logs.
final onHoldProvider = FutureProvider<List<Content>>((ref) async {
  try {
    final logs = await ref.watch(watchHistoryProvider.future);
    final holdLogs = logs
        .where(
          (log) =>
              log.status == LogStatus.watchlist ||
              log.status == LogStatus.planToWatch ||
              log.status == LogStatus.dropped,
        )
        .toList();

    if (holdLogs.isEmpty) {
      return [];
    }

    return _resolveLogsToContent(holdLogs);
  } catch (_) {
    return [];
  }
});

/// Movie detail by TMDB ID.
final movieDetailProvider = FutureProvider.family<Content?, int>((
  ref,
  tmdbId,
) async {
  try {
    final cacheKey = _detailCacheKey(tmdbId, 'movie');
    final cached = HiveManager.getCachedContent(cacheKey);
    if (cached != null) {
      return cached;
    }

    final detail = await TMDBService.getDetails(tmdbId, 'movie');
    if (detail != null) {
      await HiveManager.cacheContent(cacheKey, detail);
    }

    return detail;
  } catch (_) {
    return null;
  }
});

/// TV detail by TMDB ID.
final tvDetailProvider = FutureProvider.family<Content?, int>((
  ref,
  tmdbId,
) async {
  try {
    final cacheKey = _detailCacheKey(tmdbId, 'tv');
    final cached = HiveManager.getCachedContent(cacheKey);
    if (cached != null && cached.mediaType == 'tv') {
      return cached;
    }

    final detail = await TMDBService.getDetails(tmdbId, 'tv');
    if (detail != null) {
      await HiveManager.cacheContent(cacheKey, detail);
    }

    return detail;
  } catch (_) {
    return null;
  }
});

/// Ratings snapshot for detail pages using app ratings blended with fallback baseline.
final contentRatingsProvider =
    FutureProvider.family<ContentRatingsSnapshot, ContentRatingsParams>((
      ref,
      params,
    ) async {
      final fallbackStars = (params.fallbackVoteAverage / 2).clamp(0.0, 5.0);

      try {
        final rows = await Supabase.instance.client
            .from('logs')
            .select('rating')
            .eq('tmdb_id', params.tmdbId)
            .eq('media_type', params.mediaType)
            .gte('rating', 0.5)
            .lte('rating', 5.0);

        final ratings = (rows as List)
            .map((row) => (row as Map<String, dynamic>)['rating'])
            .where((rating) => rating != null)
            .map((rating) => (rating as num).toDouble())
            .toList();

        return _snapshotFromRatingsWithFallback(
          ratings: ratings,
          fallbackStars: fallbackStars,
          fallbackCount: params.fallbackVoteCount,
        );
      } catch (_) {
        return _snapshotFromRatingsWithFallback(
          ratings: const <double>[],
          fallbackStars: fallbackStars,
          fallbackCount: params.fallbackVoteCount,
        );
      }
    });

/// Ratings snapshot for a specific TV episode using all user episode ratings.
final episodeRatingsProvider =
    FutureProvider.family<ContentRatingsSnapshot, EpisodeRatingsParams>((
      ref,
      params,
    ) async {
      final fallbackStars = (params.fallbackVoteAverage / 2).clamp(0.0, 5.0);

      try {
        final rows = await Supabase.instance.client
            .from('logs')
            .select('tags')
            .eq('tmdb_id', params.tmdbId)
            .eq('media_type', 'tv');

        final prefix = 'ep_rating:${params.episodeCode.toUpperCase()}:';
        final ratings = <double>[];

        for (final row in (rows as List)) {
          final tags =
              ((row as Map<String, dynamic>)['tags'] as List?)
                  ?.map((entry) => entry.toString())
                  .toList() ??
              const <String>[];

          for (final tag in tags) {
            if (!tag.startsWith(prefix)) {
              continue;
            }

            final value = double.tryParse(tag.substring(prefix.length));
            if (value != null) {
              ratings.add(value.clamp(0.5, 5.0));
            }
          }
        }

        return _snapshotFromRatingsWithFallback(
          ratings: ratings,
          fallbackStars: fallbackStars,
          fallbackCount: params.fallbackVoteCount,
        );
      } catch (_) {
        return _snapshotFromRatingsWithFallback(
          ratings: const <double>[],
          fallbackStars: fallbackStars,
          fallbackCount: params.fallbackVoteCount,
        );
      }
    });

/// Similar content to a movie.
final similarContentProvider = FutureProvider.family<List<Content>, int>((
  ref,
  tmdbId,
) async {
  try {
    return await TMDBService.getRecommendations(tmdbId, 'movie');
  } catch (_) {
    return [];
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// RECOMMENDATION PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

/// Selected genre filter.
final genreFilterProvider = StateProvider<String?>((ref) => null);

/// Personalized recommendations from ML backend.
final recommendationsProvider = FutureProvider<List<RecommendationItem>>((
  ref,
) async {
  try {
    final genre = ref.watch(genreFilterProvider);
    return await RecommendationService.getForYou(genre: genre);
  } catch (_) {
    return [];
  }
});

/// Similar recommendations to a specific content item.
final similarRecommendationsProvider =
    FutureProvider.family<List<RecommendationItem>, int>((ref, tmdbId) async {
      try {
        return await RecommendationService.getSimilar(tmdbId);
      } catch (_) {
        return [];
      }
    });

// ═══════════════════════════════════════════════════════════════════════════
// PROFILE & STATS PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final userProfileProvider = FutureProvider<UserProfile?>((ref) async {
  return ref.watch(authUserProvider.future);
});

final userStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final history = await ref.watch(watchHistoryProvider.future);
    final ratedLogs = history.where((log) => log.rating != null).toList();

    final totalWatched = history.length;
    final avgRating = ratedLogs.isEmpty
        ? 0.0
        : ratedLogs.fold<double>(0.0, (sum, log) => sum + (log.rating ?? 0.0)) /
              ratedLogs.length;

    return {
      'totalWatched': totalWatched,
      'avgRating': avgRating,
      'favoriteGenres': <String, int>{},
      'totalMinutesWatched': history.length * 120,
    };
  } catch (_) {
    return {
      'totalWatched': 0,
      'avgRating': 0.0,
      'favoriteGenres': <String, int>{},
      'totalMinutesWatched': 0,
    };
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// LOG MANAGEMENT PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final addLogProvider = FutureProvider.family<void, Log>((ref, log) async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) {
    throw Exception('User not authenticated');
  }

  final newLog = log.copyWith(userId: userId);

  await Supabase.instance.client.from('logs').insert(newLog.toJson());
  await HiveManager.saveLog(newLog);

  ref.invalidate(watchHistoryProvider);
  ref.invalidate(userStatsProvider);
  ref.invalidate(recommendationsProvider);
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(onHoldProvider);
});

final updateLogProvider = FutureProvider.family<void, Log>((ref, log) async {
  await Supabase.instance.client
      .from('logs')
      .update(log.toJson())
      .eq('id', log.id);
  await HiveManager.saveLog(log);

  ref.invalidate(watchHistoryProvider);
  ref.invalidate(userStatsProvider);
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(onHoldProvider);
});

final deleteLogProvider = FutureProvider.family<void, String>((
  ref,
  logId,
) async {
  await Supabase.instance.client.from('logs').delete().eq('id', logId);
  await HiveManager.deleteLog(logId);

  ref.invalidate(watchHistoryProvider);
  ref.invalidate(userStatsProvider);
  ref.invalidate(continueWatchingProvider);
  ref.invalidate(onHoldProvider);
});
