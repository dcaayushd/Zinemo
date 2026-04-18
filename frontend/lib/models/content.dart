import 'package:equatable/equatable.dart';

/// Represents a movie or TV show from TMDB API
class Content extends Equatable {
  final int tmdbId;
  final String mediaType; // 'movie' or 'tv'
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;
  final DateTime? releaseDate;
  final List<Genre>? genres;
  final int? runtime; // in minutes
  final int? totalSeasons;
  final int? totalEpisodes;
  final DateTime? nextAirDate;
  final String? nextEpisodeName;
  final int? nextSeasonNumber;
  final int? nextEpisodeNumber;
  final int? lastSeasonNumber;
  final int? lastEpisodeNumber;
  final double? voteAverage; // 0-10
  final int? voteCount;
  final double? popularity;
  final String? imdbId;
  final List<String>? trailerUrls;

  const Content({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.genres,
    this.runtime,
    this.totalSeasons,
    this.totalEpisodes,
    this.nextAirDate,
    this.nextEpisodeName,
    this.nextSeasonNumber,
    this.nextEpisodeNumber,
    this.lastSeasonNumber,
    this.lastEpisodeNumber,
    this.voteAverage,
    this.voteCount,
    this.popularity,
    this.imdbId,
    this.trailerUrls,
  });

  /// Build poster URL from TMDB CDN
  String get posterUrl {
    if (posterPath == null || posterPath!.isEmpty) {
      return 'https://via.placeholder.com/342x513?text=No+Image';
    }

    if (posterPath!.startsWith('http://') ||
        posterPath!.startsWith('https://')) {
      return posterPath!;
    }

    return 'https://image.tmdb.org/t/p/w342$posterPath';
  }

  /// Build backdrop URL from TMDB CDN
  String get backdropUrl {
    if (backdropPath == null || backdropPath!.isEmpty) {
      return 'https://via.placeholder.com/1280x720?text=No+Image';
    }

    if (backdropPath!.startsWith('http://') ||
        backdropPath!.startsWith('https://')) {
      return backdropPath!;
    }

    return 'https://image.tmdb.org/t/p/w1280$backdropPath';
  }

  /// Get average rating display (1-5 stars mapped from 0-10 vote average)
  double get starsRating => (voteAverage ?? 0) / 2.0;

  /// Check if content has user rating stored
  bool get hasUserRating => false; // Will be populated from logs

  /// Convert Content to JSON for local storage
  Map<String, dynamic> toJson() => {
    'tmdbId': tmdbId,
    'mediaType': mediaType,
    'title': title,
    'originalTitle': originalTitle,
    'overview': overview,
    'posterPath': posterPath,
    'backdropPath': backdropPath,
    'releaseDate': releaseDate?.toIso8601String(),
    'genres': genres?.map((g) => {'id': g.id, 'name': g.name}).toList(),
    'runtime': runtime,
    'totalSeasons': totalSeasons,
    'totalEpisodes': totalEpisodes,
    'nextAirDate': nextAirDate?.toIso8601String(),
    'nextEpisodeName': nextEpisodeName,
    'nextSeasonNumber': nextSeasonNumber,
    'nextEpisodeNumber': nextEpisodeNumber,
    'lastSeasonNumber': lastSeasonNumber,
    'lastEpisodeNumber': lastEpisodeNumber,
    'voteAverage': voteAverage,
    'voteCount': voteCount,
    'popularity': popularity,
    'imdbId': imdbId,
    'trailerUrls': trailerUrls,
  };

  /// Create Content from JSON (TMDB API or local storage)
  factory Content.fromJson(Map<String, dynamic> json) => Content(
    tmdbId: json['tmdb_id'] ?? json['tmdbId'] ?? 0,
    mediaType: json['media_type'] ?? json['mediaType'] ?? 'movie',
    title: json['title'] ?? '',
    originalTitle: json['original_title'] ?? json['originalTitle'],
    overview: json['overview'],
    posterPath: json['poster_path'] ?? json['posterPath'],
    backdropPath: json['backdrop_path'] ?? json['backdropPath'],
    releaseDate: json['release_date'] != null
        ? DateTime.tryParse(json['release_date'])
        : (json['releaseDate'] != null
              ? DateTime.tryParse(json['releaseDate'])
              : null),
    genres: json['genres'] != null
        ? List<Genre>.from(
            json['genres'].map(
              (g) =>
                  g is Map ? Genre(id: g['id'] ?? 0, name: g['name'] ?? '') : g,
            ),
          )
        : null,
    runtime: json['runtime'],
    totalSeasons: json['total_seasons'] ?? json['totalSeasons'],
    totalEpisodes: json['total_episodes'] ?? json['totalEpisodes'],
    nextAirDate: json['next_air_date'] != null
        ? DateTime.tryParse(json['next_air_date'])
        : (json['nextAirDate'] != null
              ? DateTime.tryParse(json['nextAirDate'])
              : null),
    nextEpisodeName: json['next_episode_name'] ?? json['nextEpisodeName'],
    nextSeasonNumber: json['next_season_number'] ?? json['nextSeasonNumber'],
    nextEpisodeNumber: json['next_episode_number'] ?? json['nextEpisodeNumber'],
    lastSeasonNumber: json['last_season_number'] ?? json['lastSeasonNumber'],
    lastEpisodeNumber: json['last_episode_number'] ?? json['lastEpisodeNumber'],
    voteAverage: (json['vote_average'] ?? json['voteAverage'])?.toDouble(),
    voteCount: json['vote_count'] ?? json['voteCount'],
    popularity: (json['popularity'])?.toDouble(),
    imdbId: json['imdb_id'] ?? json['imdbId'],
    trailerUrls: json['trailer_urls'] != null
        ? List<String>.from(json['trailer_urls'])
        : (json['trailerUrls'] != null
              ? List<String>.from(json['trailerUrls'])
              : null),
  );

  @override
  List<Object?> get props => [
    tmdbId,
    mediaType,
    title,
    posterPath,
    totalSeasons,
    totalEpisodes,
    voteAverage,
  ];
}

class Genre extends Equatable {
  final int id;
  final String name;

  const Genre({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Genre.fromJson(Map<String, dynamic> json) =>
      Genre(id: json['id'] ?? 0, name: json['name'] ?? '');

  @override
  List<Object?> get props => [id, name];
}

/// Recommendation result from ML service
class Recommendation extends Equatable {
  final int tmdbId;
  final String mediaType;
  final Content? content; // Full content data if available
  final double score;
  final String reason;
  final String algorithm; // 'lightfm', 'als', 'content', 'popularity', etc.

  const Recommendation({
    required this.tmdbId,
    required this.mediaType,
    this.content,
    required this.score,
    required this.reason,
    required this.algorithm,
  });

  @override
  List<Object?> get props => [tmdbId, score, algorithm];
}
