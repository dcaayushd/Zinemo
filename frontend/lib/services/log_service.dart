import 'package:supabase_flutter/supabase_flutter.dart';

class LogService {
  static final _supabase = Supabase.instance.client;

  static List<String> buildTVProgressTags({
    required int season,
    required int episode,
    required int progress,
  }) {
    return [
      'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}',
      'season:$season',
      'episode:$episode',
      'progress:$progress',
    ];
  }

  static String _episodeCode(int season, int episode) {
    return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
  }

  static int? _extractTagInt(List<String> tags, String key) {
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

  static ({int season, int episode}) _extractSeasonEpisode(List<String> tags) {
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

  static List<String> _upsertEpisodeWatchedTag(
    List<String> tags,
    String episodeCode,
  ) {
    if (tags.contains('ep_watched:$episodeCode')) {
      return tags;
    }

    return [...tags, 'ep_watched:$episodeCode'];
  }

  static List<String> _upsertEpisodeRatingTag(
    List<String> tags,
    String episodeCode,
    double rating,
  ) {
    final prefix = 'ep_rating:$episodeCode:';
    final next = tags.where((tag) => !tag.startsWith(prefix)).toList();
    next.add('$prefix${rating.toStringAsFixed(1)}');
    return next;
  }

  static int resolveCurrentTVProgressFromTags(List<String> tags) {
    final progress = _extractTagInt(tags, 'progress');
    if (progress != null && progress > 0) {
      return progress;
    }

    final parsed = _extractSeasonEpisode(tags);
    if (parsed.season <= 1) {
      return parsed.episode < 0 ? 0 : parsed.episode;
    }

    return ((parsed.season - 1) * 8) + parsed.episode;
  }

  static List<String> _stripProgressTags(List<String> tags) {
    return tags.where((tag) {
      return !tag.startsWith('season:') &&
          !tag.startsWith('episode:') &&
          !tag.startsWith('progress:') &&
          !RegExp(r'^[sS]\d+[\s._-]*[eE]\d+$').hasMatch(tag);
    }).toList();
  }

  /// Quick log action - creates or updates a log entry
  static Future<void> quickLog({
    required int tmdbId,
    required String mediaType,
    required String status, // 'watched', 'watchlist', 'dropped', 'watching'
    double? rating,
    bool liked = false,
    bool rewatch = false,
    List<String>? tags,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    // First, try to get existing log entry
    final existingResponse = await _supabase
        .from('logs')
        .select('id, tags')
        .eq('user_id', user.id)
        .eq('tmdb_id', tmdbId)
        .eq('media_type', mediaType)
        .limit(1);

    final existingLogs = existingResponse as List?;
    final existingTags = existingLogs != null && existingLogs.isNotEmpty
        ? ((existingLogs[0]['tags'] as List?)
                  ?.map((entry) => entry.toString())
                  .toList() ??
              <String>[])
        : <String>[];

    final resolvedTags =
        tags ??
        ((mediaType == 'tv' && status == 'watching')
            ? (existingTags.isNotEmpty
                  ? existingTags
                  : ['S01E01', 'season:1', 'episode:1', 'progress:1'])
            : (mediaType == 'tv' && status == 'watched')
            ? _stripProgressTags(existingTags)
            : existingTags);

    if (existingLogs != null && existingLogs.isNotEmpty) {
      // Update existing log
      await _supabase
          .from('logs')
          .update({
            'status': status,
            'rating': rating,
            'liked': liked,
            'rewatch': rewatch,
            'watched_date': status == 'watched'
                ? DateTime.now().toIso8601String()
                : null,
            'tags': resolvedTags.isNotEmpty ? resolvedTags : null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', existingLogs[0]['id'] as String);
    } else {
      // Insert new log
      await _supabase.from('logs').insert({
        'user_id': user.id,
        'tmdb_id': tmdbId,
        'media_type': mediaType,
        'status': status,
        'rating': rating,
        'liked': liked,
        'rewatch': rewatch,
        'watched_date': status == 'watched'
            ? DateTime.now().toIso8601String()
            : null,
        'tags': resolvedTags.isNotEmpty ? resolvedTags : null,
      });
    }
  }

  /// Add to watchlist
  static Future<void> addToWatchlist(int tmdbId, String mediaType) {
    return quickLog(tmdbId: tmdbId, mediaType: mediaType, status: 'watchlist');
  }

  /// Mark as watched
  static Future<void> markAsWatched(
    int tmdbId,
    String mediaType, {
    double? rating,
    List<String>? tags,
  }) {
    return quickLog(
      tmdbId: tmdbId,
      mediaType: mediaType,
      status: 'watched',
      rating: rating,
      tags: tags,
    );
  }

  /// Add to hold (dropped)
  static Future<void> addToHold(int tmdbId, String mediaType) {
    return quickLog(tmdbId: tmdbId, mediaType: mediaType, status: 'dropped');
  }

  /// Quick rate
  static Future<void> quickRate(
    int tmdbId,
    String mediaType,
    double rating, {
    List<String>? tags,
  }) {
    return quickLog(
      tmdbId: tmdbId,
      mediaType: mediaType,
      status: 'watched',
      rating: rating,
      tags: tags,
    );
  }

  /// Start watching a show
  static Future<void> startWatching(
    int tmdbId,
    String mediaType, {
    List<String>? tags,
  }) {
    return quickLog(
      tmdbId: tmdbId,
      mediaType: mediaType,
      status: 'watching',
      tags: tags,
    );
  }

  /// Mark TV progress by season/episode index while preserving existing like/rating.
  static Future<void> markTVProgress({
    required int tmdbId,
    required int season,
    required int episode,
    required int progress,
    required int totalEpisodes,
    bool setWatchedDate = false,
    int? episodesInSeasonForSeasonMark,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final safeSeason = season < 1 ? 1 : season;
    final safeEpisode = episode < 1 ? 1 : episode;
    final safeTotal = totalEpisodes < 1 ? 1 : totalEpisodes;
    final safeProgress = progress.clamp(1, safeTotal);
    final status = safeProgress >= safeTotal ? 'watched' : 'watching';

    final tags = buildTVProgressTags(
      season: safeSeason,
      episode: safeEpisode,
      progress: safeProgress,
    );
    final episodeCode = _episodeCode(safeSeason, safeEpisode);
    final tagsWithEpisode = _upsertEpisodeWatchedTag(tags, episodeCode);

    final existingResponse = await _supabase
        .from('logs')
        .select('id, tags')
        .eq('user_id', user.id)
        .eq('tmdb_id', tmdbId)
        .eq('media_type', 'tv')
        .limit(1);

    final existingLogs = existingResponse as List?;
    if (existingLogs != null && existingLogs.isNotEmpty) {
      final row = existingLogs.first as Map<String, dynamic>;
      final existingTags =
          ((row['tags'] as List?)?.map((entry) => entry.toString()).toList() ??
                  <String>[])
              .toList();

      var nextTags = _stripProgressTags(existingTags);
      nextTags.addAll(tags);
      nextTags = _upsertEpisodeWatchedTag(nextTags, episodeCode);

      if (episodesInSeasonForSeasonMark != null &&
          episodesInSeasonForSeasonMark > 0) {
        for (
          var currentEpisode = 1;
          currentEpisode <= episodesInSeasonForSeasonMark;
          currentEpisode++
        ) {
          nextTags = _upsertEpisodeWatchedTag(
            nextTags,
            _episodeCode(safeSeason, currentEpisode),
          );
        }
      }

      if (setWatchedDate) {
        nextTags = nextTags
            .where((tag) => !tag.startsWith('season_marked:'))
            .toList();
        nextTags.add(
          'season_marked:S${safeSeason.toString().padLeft(2, '0')}:${DateTime.now().toIso8601String()}',
        );
      }

      nextTags = nextTags.toSet().toList();

      await _supabase
          .from('logs')
          .update({
            'status': status,
            'tags': nextTags,
            'watched_date': status == 'watched' || setWatchedDate
                ? DateTime.now().toIso8601String()
                : null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', row['id'] as String);
      return;
    }

    var insertTags = tagsWithEpisode;
    if (episodesInSeasonForSeasonMark != null &&
        episodesInSeasonForSeasonMark > 0) {
      for (
        var currentEpisode = 1;
        currentEpisode <= episodesInSeasonForSeasonMark;
        currentEpisode++
      ) {
        insertTags = _upsertEpisodeWatchedTag(
          insertTags,
          _episodeCode(safeSeason, currentEpisode),
        );
      }
    }
    if (setWatchedDate) {
      insertTags = [
        ...insertTags,
        'season_marked:S${safeSeason.toString().padLeft(2, '0')}:${DateTime.now().toIso8601String()}',
      ];
    }

    await _supabase.from('logs').insert({
      'user_id': user.id,
      'tmdb_id': tmdbId,
      'media_type': 'tv',
      'status': status,
      'tags': insertTags.toSet().toList(),
      'watched_date': status == 'watched' || setWatchedDate
          ? DateTime.now().toIso8601String()
          : null,
    });
  }

  /// Persist a per-episode rating for TV while keeping overall show state intact.
  static Future<void> setTVEpisodeRating({
    required int tmdbId,
    required int season,
    required int episode,
    required double rating,
    int? progress,
    int? totalEpisodes,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final safeRating = rating.clamp(0.5, 5.0);
    final safeSeason = season < 1 ? 1 : season;
    final safeEpisode = episode < 1 ? 1 : episode;
    final episodeCode = _episodeCode(safeSeason, safeEpisode);

    final existingResponse = await _supabase
        .from('logs')
        .select('id, tags, status')
        .eq('user_id', user.id)
        .eq('tmdb_id', tmdbId)
        .eq('media_type', 'tv')
        .limit(1);

    final existingLogs = existingResponse as List?;
    final nowIso = DateTime.now().toIso8601String();

    if (existingLogs != null && existingLogs.isNotEmpty) {
      final row = existingLogs.first as Map<String, dynamic>;
      final existingTags =
          ((row['tags'] as List?)?.map((entry) => entry.toString()).toList() ??
                  <String>[])
              .toList();

      var nextTags = _upsertEpisodeWatchedTag(existingTags, episodeCode);
      nextTags = _upsertEpisodeRatingTag(nextTags, episodeCode, safeRating);

      final currentStatus = (row['status'] as String?) ?? 'watching';
      final nextStatus =
          currentStatus == 'watchlist' || currentStatus == 'dropped'
          ? 'watching'
          : currentStatus;

      var nextProgress = progress;
      if (nextProgress == null || nextProgress <= 0) {
        nextProgress = resolveCurrentTVProgressFromTags(existingTags);
      }

      if (nextProgress <= 0) {
        nextProgress = safeEpisode;
      }

      if (totalEpisodes != null && totalEpisodes > 0) {
        nextProgress = nextProgress.clamp(1, totalEpisodes);
      }

      if (nextProgress > 0) {
        final progressTags = buildTVProgressTags(
          season: safeSeason,
          episode: safeEpisode,
          progress: nextProgress,
        );

        nextTags = nextTags
            .where(
              (tag) =>
                  !tag.startsWith('season:') &&
                  !tag.startsWith('episode:') &&
                  !tag.startsWith('progress:') &&
                  !RegExp(r'^[sS]\d+[\s._-]*[eE]\d+$').hasMatch(tag),
            )
            .toList();
        nextTags.addAll(progressTags);
        nextTags = _upsertEpisodeWatchedTag(nextTags, episodeCode);
        nextTags = _upsertEpisodeRatingTag(nextTags, episodeCode, safeRating);
      }

      await _supabase
          .from('logs')
          .update({
            'status': nextStatus,
            'tags': nextTags,
            'updated_at': nowIso,
          })
          .eq('id', row['id'] as String);

      return;
    }

    final computedProgress = (progress ?? safeEpisode).clamp(
      1,
      totalEpisodes == null || totalEpisodes <= 0 ? safeEpisode : totalEpisodes,
    );
    var tags = buildTVProgressTags(
      season: safeSeason,
      episode: safeEpisode,
      progress: computedProgress,
    );
    tags = _upsertEpisodeWatchedTag(tags, episodeCode);
    tags = _upsertEpisodeRatingTag(tags, episodeCode, safeRating);

    await _supabase.from('logs').insert({
      'user_id': user.id,
      'tmdb_id': tmdbId,
      'media_type': 'tv',
      'status': 'watching',
      'tags': tags,
      'updated_at': nowIso,
    });
  }
}
