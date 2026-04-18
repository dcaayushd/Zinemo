import 'package:dio/dio.dart';
import 'package:zinemo/config/api_client.dart';
import 'package:zinemo/models/content.dart';
import 'package:zinemo/models/person.dart';

/// Service for TMDB content operations (abstracted from API)
class TMDBService {
  static const String _basePath = '/content';

  static List<Content> _parseContentList(Response<dynamic> response) {
    if (response.statusCode != 200 || response.data == null) {
      return [];
    }

    final payload = response.data;
    final rawList = payload is List
        ? payload
        : (payload is Map<String, dynamic> ? payload['data'] : null);

    if (rawList is! List) {
      return [];
    }

    return rawList
        .whereType<Map>()
        .map((item) => Content.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Content? _parseSingleContent(Response<dynamic> response) {
    if (response.statusCode != 200 || response.data == null) {
      return null;
    }

    final payload = response.data;
    final rawMap = payload is Map<String, dynamic>
        ? (payload['data'] is Map<String, dynamic>
              ? payload['data'] as Map<String, dynamic>
              : payload)
        : null;

    if (rawMap == null) {
      return null;
    }

    return Content.fromJson(rawMap);
  }

  /// Search movies and TV shows
  static Future<List<Content>> search(String query) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/search',
        queryParameters: {'query': query},
      );

      return _parseContentList(response);
    } on DioException {
      // Logging: print('Search error: $e');
      rethrow;
    }
  }

  /// Get trending movies/TV
  static Future<List<Content>> getTrending({
    String timeWindow = 'week',
    String mediaType = 'movie',
    String? genre,
    int limit = 20,
  }) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/trending',
        queryParameters: {
          'time_window': timeWindow,
          'media_type': mediaType,
          'limit': limit,
          if (genre != null && genre.trim().isNotEmpty) 'genre': genre.trim(),
        },
      );

      return _parseContentList(response);
    } on DioException {
      // Logging: print('Get trending error: $e');
      rethrow;
    }
  }

  /// Discover content by genre name.
  static Future<List<Content>> discoverByGenre(String genre, int limit) async {
    try {
      final normalized = genre.trim();
      if (normalized.isEmpty) {
        return [];
      }

      final response = await ApiClient.get<dynamic>(
        '$_basePath/genre/${Uri.encodeComponent(normalized)}',
        queryParameters: {'limit': limit},
      );
      return _parseContentList(response);
    } on DioException {
      rethrow;
    }
  }

  /// Get top rated movies/TV
  static Future<List<Content>> getTopRated({String mediaType = 'movie'}) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/top-rated',
        queryParameters: {'media_type': mediaType},
      );

      return _parseContentList(response);
    } on DioException {
      // Logging: print('Get top rated error: $e');
      rethrow;
    }
  }

  /// Get new releases
  static Future<List<Content>> getNewReleases({
    String mediaType = 'movie',
  }) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/new-releases',
        queryParameters: {'limit': 20, 'media_type': mediaType},
      );

      return _parseContentList(response);
    } on DioException {
      // Logging: print('Get new releases error: $e');
      rethrow;
    }
  }

  /// Get movie/TV details by TMDB ID
  static Future<Content?> getDetails(int tmdbId, String mediaType) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/detail/$tmdbId',
        queryParameters: {'media_type': mediaType},
      );

      return _parseSingleContent(response);
    } on DioException {
      // Logging: print('Get details error: $e');
      rethrow;
    }
  }

  /// Get recommendations for a movie/TV
  static Future<List<Content>> getRecommendations(
    int tmdbId,
    String mediaType,
  ) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/similar/$tmdbId',
        queryParameters: {'media_type': mediaType, 'limit': 20},
      );

      return _parseContentList(response);
    } on DioException {
      // Logging: print('Get recommendations error: $e');
      rethrow;
    }
  }

  /// Get similar movies/TV
  static Future<List<Content>> getSimilar(int tmdbId, String mediaType) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/similar/$tmdbId',
        queryParameters: {'media_type': mediaType},
      );

      return _parseContentList(response);
    } on DioException {
      // Logging: print('Get similar error: $e');
      rethrow;
    }
  }

  /// Get cast and crew for a movie/TV
  static Future<Credits?> getCredits(int tmdbId, String mediaType) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/credits/$tmdbId',
        queryParameters: {'media_type': mediaType},
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final payload = response.data;
      final rawMap = payload is Map<String, dynamic>
          ? (payload['data'] is Map<String, dynamic>
                ? payload['data'] as Map<String, dynamic>
                : payload)
          : null;

      if (rawMap == null) {
        return null;
      }

      return Credits.fromJson(rawMap);
    } on DioException {
      // Logging: print('Get credits error: $e');
      return null; // Return null instead of throwing
    }
  }

  /// Get person details by ID
  static Future<Person?> getPerson(int personId) async {
    try {
      final response = await ApiClient.get<dynamic>('/person/$personId');

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final payload = response.data;
      final rawMap = payload is Map<String, dynamic>
          ? (payload['data'] is Map<String, dynamic>
                ? payload['data'] as Map<String, dynamic>
                : payload)
          : null;

      if (rawMap == null) {
        return null;
      }

      return Person.fromJson(rawMap);
    } on DioException {
      // Logging: print('Get person error: $e');
      return null;
    }
  }

  /// Get filmography for a person (movies/TV they've appeared in)
  static Future<List<Content>> getPersonFilmography(
    int personId, {
    String mediaType = 'all',
  }) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '/person/$personId/filmography',
        queryParameters: mediaType != 'all' ? {'media_type': mediaType} : null,
      );

      return _parseContentList(response);
    } on DioException {
      // Logging: print('Get filmography error: $e');
      return [];
    }
  }

  /// Get season details for a TV show (episodes list + season metadata)
  static Future<Map<String, dynamic>?> getTVSeasonDetails(
    int tmdbId,
    int seasonNumber,
  ) async {
    try {
      final response = await ApiClient.get<dynamic>(
        '$_basePath/tv/$tmdbId/season/$seasonNumber',
      );

      if (response.statusCode != 200 || response.data == null) {
        return null;
      }

      final payload = response.data;
      if (payload is Map<String, dynamic> &&
          payload['data'] is Map<String, dynamic>) {
        return payload['data'] as Map<String, dynamic>;
      }

      if (payload is Map<String, dynamic>) {
        return payload;
      }

      return null;
    } on DioException {
      return null;
    }
  }
}
