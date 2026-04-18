import 'package:equatable/equatable.dart';

/// Represents a user's log entry for a movie/TV show
class Log extends Equatable {
  final String id;
  final String userId;
  final int tmdbId;
  final int contentId;
  final String mediaType;
  final LogStatus status;
  final double? rating; // 0.5-5.0 scale
  final bool liked;
  final bool rewatch;
  final int rewatchCount;
  final DateTime? watchedDate;
  final String? review;
  final List<String> tags;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Log({
    required this.id,
    required this.userId,
    required this.tmdbId,
    required this.contentId,
    required this.mediaType,
    required this.status,
    this.rating,
    this.liked = false,
    this.rewatch = false,
    this.rewatchCount = 0,
    this.watchedDate,
    this.review,
    this.tags = const [],
    this.isPrivate = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Log copyWith({
    String? id,
    String? userId,
    int? tmdbId,
    int? contentId,
    String? mediaType,
    LogStatus? status,
    double? rating,
    bool? liked,
    bool? rewatch,
    int? rewatchCount,
    DateTime? watchedDate,
    String? review,
    List<String>? tags,
    bool? isPrivate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Log(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      tmdbId: tmdbId ?? this.tmdbId,
      contentId: contentId ?? this.contentId,
      mediaType: mediaType ?? this.mediaType,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      liked: liked ?? this.liked,
      rewatch: rewatch ?? this.rewatch,
      rewatchCount: rewatchCount ?? this.rewatchCount,
      watchedDate: watchedDate ?? this.watchedDate,
      review: review ?? this.review,
      tags: tags ?? this.tags,
      isPrivate: isPrivate ?? this.isPrivate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Convert Log to JSON for API calls
  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'tmdb_id': tmdbId,
    'content_id': contentId,
    'media_type': mediaType,
    'status': status.name,
    'rating': rating,
    'liked': liked,
    'rewatch': rewatch,
    'rewatch_count': rewatchCount,
    'watched_date': watchedDate?.toIso8601String(),
    'review': review,
    'tags': tags,
    'is_private': isPrivate,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Create Log from JSON (Supabase or cache)
  factory Log.fromJson(Map<String, dynamic> json) => Log(
    id: json['id'] ?? '',
    userId: json['user_id'] ?? '',
    tmdbId: json['tmdb_id'] ?? 0,
    contentId: json['content_id'] ?? 0,
    mediaType: json['media_type'] ?? 'movie',
    status: LogStatus.fromString(json['status'] ?? 'watched'),
    rating: json['rating']?.toDouble(),
    liked: json['liked'] ?? false,
    rewatch: json['rewatch'] ?? false,
    rewatchCount: json['rewatch_count'] ?? 0,
    watchedDate: json['watched_date'] != null
        ? DateTime.tryParse(json['watched_date'])
        : null,
    review: json['review'],
    tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
    isPrivate: json['is_private'] ?? false,
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
  );

  @override
  List<Object?> get props => [id, tmdbId, userId];
}

enum LogStatus {
  watched,
  watching,
  watchlist,
  dropped,
  planToWatch;

  String get displayName {
    switch (this) {
      case LogStatus.watched:
        return 'Watched';
      case LogStatus.watching:
        return 'Watching';
      case LogStatus.watchlist:
        return 'Watchlist';
      case LogStatus.dropped:
        return 'Dropped';
      case LogStatus.planToWatch:
        return 'Plan to Watch';
    }
  }

  static LogStatus fromString(String value) {
    return LogStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => LogStatus.watched,
    );
  }
}
