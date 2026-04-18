import 'package:dio/dio.dart';
import 'package:zinemo/config/api_client.dart';
import 'package:zinemo/services/tmdb_service.dart';

/// Recommendation item model
class RecommendationItem {
  final int tmdbId;
  final String mediaType;
  final double score;
  final String reason;
  final String algorithm;
  final String? title;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final String? releaseDate;
  final double? voteAverage;

  RecommendationItem({
    required this.tmdbId,
    required this.mediaType,
    required this.score,
    required this.reason,
    required this.algorithm,
    this.title,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
  });

  RecommendationItem copyWith({
    int? tmdbId,
    String? mediaType,
    double? score,
    String? reason,
    String? algorithm,
    String? title,
    String? overview,
    String? posterPath,
    String? backdropPath,
    String? releaseDate,
    double? voteAverage,
  }) {
    return RecommendationItem(
      tmdbId: tmdbId ?? this.tmdbId,
      mediaType: mediaType ?? this.mediaType,
      score: score ?? this.score,
      reason: reason ?? this.reason,
      algorithm: algorithm ?? this.algorithm,
      title: title ?? this.title,
      overview: overview ?? this.overview,
      posterPath: posterPath ?? this.posterPath,
      backdropPath: backdropPath ?? this.backdropPath,
      releaseDate: releaseDate ?? this.releaseDate,
      voteAverage: voteAverage ?? this.voteAverage,
    );
  }

  static int _parseInt(dynamic value, {int fallback = 0}) {
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static double _parseDouble(dynamic value, {double fallback = 0.0}) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  factory RecommendationItem.fromJson(Map<String, dynamic> json) {
    return RecommendationItem(
      tmdbId: _parseInt(json['tmdb_id']),
      mediaType: json['media_type'] as String? ?? 'movie',
      score: _parseDouble(json['score']),
      reason: json['reason'] as String? ?? 'Recommended for you',
      algorithm: json['algorithm'] as String? ?? 'hybrid',
      title: json['title'] as String?,
      overview: json['overview'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      releaseDate: json['release_date'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
    );
  }
}

/// Service for personalized recommendations from ML backend
class RecommendationService {
  static const String _basePath = '/recommendations';
  static const int _maxHydrationCount = 12;

  static List<dynamic> _extractRecommendationItems(dynamic payload) {
    if (payload is List) {
      return payload;
    }

    if (payload is Map<String, dynamic>) {
      final recommendations = payload['recommendations'];
      if (recommendations is List) {
        return recommendations;
      }

      final data = payload['data'];
      if (data is List) {
        return data;
      }
    }

    return const [];
  }

  static bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  static String? _normalizeGenre(String? genre) {
    if (genre == null) {
      return null;
    }

    final trimmed = genre.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == 'top 10') {
      return null;
    }

    return trimmed;
  }

  static bool _needsHydration(RecommendationItem item) {
    return _isBlank(item.title) ||
        _isBlank(item.posterPath) ||
        _isBlank(item.backdropPath) ||
        ((item.voteAverage ?? 0) <= 0);
  }

  static Future<List<RecommendationItem>> _hydrateMissingMetadata(
    List<RecommendationItem> items,
  ) async {
    if (items.isEmpty) {
      return items;
    }

    final tasks = <Future<RecommendationItem>>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (i >= _maxHydrationCount || !_needsHydration(item)) {
        tasks.add(Future<RecommendationItem>.value(item));
        continue;
      }

      tasks.add(() async {
        try {
          final details = await TMDBService.getDetails(
            item.tmdbId,
            item.mediaType,
          );
          if (details == null) {
            return item;
          }

          final detailReleaseDate = details.releaseDate
              ?.toIso8601String()
              .split('T')
              .first;

          return item.copyWith(
            mediaType: item.mediaType.isNotEmpty
                ? item.mediaType
                : details.mediaType,
            title: _isBlank(item.title) ? details.title : item.title,
            overview: _isBlank(item.overview)
                ? (details.overview ?? item.reason)
                : item.overview,
            posterPath: _isBlank(item.posterPath)
                ? details.posterPath
                : item.posterPath,
            backdropPath: _isBlank(item.backdropPath)
                ? details.backdropPath
                : item.backdropPath,
            releaseDate: _isBlank(item.releaseDate)
                ? detailReleaseDate
                : item.releaseDate,
            voteAverage: (item.voteAverage ?? 0) <= 0
                ? details.voteAverage
                : item.voteAverage,
          );
        } catch (_) {
          return item;
        }
      }());
    }

    return Future.wait(tasks);
  }

  static Future<List<RecommendationItem>> _fallbackTrending({
    int limit = 30,
    String? genre,
  }) async {
    try {
      final trending = await TMDBService.getTrending(
        mediaType: 'movie',
        limit: limit,
        genre: genre,
      );
      if (trending.isEmpty) {
        return [];
      }

      return trending.take(limit).map((content) {
        return RecommendationItem(
          tmdbId: content.tmdbId,
          mediaType: content.mediaType,
          score: ((content.voteAverage ?? 0) / 10).clamp(0, 1),
          reason: genre == null
              ? 'Trending right now'
              : 'Trending in $genre right now',
          algorithm: 'tmdb_fallback',
          title: content.title,
          overview: content.overview,
          posterPath: content.posterPath,
          backdropPath: content.backdropPath,
          releaseDate: content.releaseDate?.toIso8601String().split('T').first,
          voteAverage: content.voteAverage,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<RecommendationItem>> _genreFocusedFallback({
    required String genre,
    required int limit,
  }) async {
    try {
      final catalog = await TMDBService.discoverByGenre(genre, limit * 2);
      final source = catalog.isNotEmpty
          ? catalog
          : await TMDBService.getTrending(
              mediaType: 'movie',
              limit: limit * 2,
              genre: genre,
            );

      if (source.isEmpty) {
        return [];
      }

      final total = source.length;
      return source.take(limit).toList().asMap().entries.map((entry) {
        final index = entry.key;
        final content = entry.value;
        final rankScore = (1 - (index / (total <= 1 ? 1 : total))).clamp(
          0.05,
          1.0,
        );
        final voteScore = ((content.voteAverage ?? 0) / 10).clamp(0, 1);
        return RecommendationItem(
          tmdbId: content.tmdbId,
          mediaType: content.mediaType,
          score: (voteScore * 0.65 + rankScore * 0.35).clamp(0, 1),
          reason: '$genre pick for your mood',
          algorithm: 'genre_focus',
          title: content.title,
          overview: content.overview,
          posterPath: content.posterPath,
          backdropPath: content.backdropPath,
          releaseDate: content.releaseDate?.toIso8601String().split('T').first,
          voteAverage: content.voteAverage,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  static List<RecommendationItem> _mergeGenreFocusedResults({
    required List<RecommendationItem> personalized,
    required List<RecommendationItem> genreCandidates,
    required int limit,
  }) {
    final merged = <RecommendationItem>[];
    final seen = <int>{};

    void push(RecommendationItem item) {
      if (merged.length >= limit || !seen.add(item.tmdbId)) {
        return;
      }
      merged.add(item);
    }

    for (final item in genreCandidates) {
      push(item);
      if (merged.length >= limit) {
        break;
      }
    }

    for (final item in personalized) {
      push(item);
      if (merged.length >= limit) {
        break;
      }
    }

    return merged;
  }

  /// Get personalized recommendations for current user
  static Future<List<RecommendationItem>> getForYou({
    String? genre,
    int limit = 30,
  }) async {
    final normalizedGenre = _normalizeGenre(genre);

    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/foryou',
        queryParameters: {
          if (normalizedGenre != null) 'genre': normalizedGenre,
          if (normalizedGenre != null) 'genre_filter': normalizedGenre,
          'limit': limit,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final rawItems = _extractRecommendationItems(response.data);
        final parsed = rawItems
            .map(
              (item) => RecommendationItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();

        final enriched = await _hydrateMissingMetadata(parsed);
        if (normalizedGenre != null) {
          final genreCandidates = await _genreFocusedFallback(
            genre: normalizedGenre,
            limit: limit,
          );
          final merged = _mergeGenreFocusedResults(
            personalized: enriched,
            genreCandidates: genreCandidates,
            limit: limit,
          );
          if (merged.isNotEmpty) {
            return merged;
          }
        }

        if (enriched.isNotEmpty) {
          return enriched;
        }
      }

      return _fallbackTrending(limit: limit, genre: normalizedGenre);
    } on DioException {
      return _fallbackTrending(limit: limit, genre: normalizedGenre);
    }
  }

  /// Get similar content by TMDB ID
  static Future<List<RecommendationItem>> getSimilar(int tmdbId) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/similar/$tmdbId',
      );

      if (response.statusCode == 200 && response.data != null) {
        final rawItems = _extractRecommendationItems(response.data);
        final parsed = rawItems
            .map(
              (item) => RecommendationItem.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList();
        return _hydrateMissingMetadata(parsed);
      }
      return [];
    } on DioException {
      // Logging: print('Get similar error: $e');
      rethrow;
    }
  }

  /// Trigger model retraining (typically after 50 new logs)
  static Future<void> triggerRetrain() async {
    try {
      await ApiClient.post('$_basePath/retrain');
    } on DioException {
      // Logging: print('Retrain trigger error: $e');
      // Non-fatal error
    }
  }
}
