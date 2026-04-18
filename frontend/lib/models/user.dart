import 'package:equatable/equatable.dart';

/// Represents an authenticated user profile
class UserProfile extends Equatable {
  final String id; // Supabase UUID
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? bio;
  final UserPreferences preferences;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.bio,
    required this.preferences,
    this.isPrivate = false,
    required this.createdAt,
    required this.updatedAt,
  });

  UserProfile copyWith({
    String? id,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? bio,
    UserPreferences? preferences,
    bool? isPrivate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      preferences: preferences ?? this.preferences,
      isPrivate: isPrivate ?? this.isPrivate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Convert to JSON for API calls
  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'bio': bio,
    'preferences': preferences.toJson(),
    'is_private': isPrivate,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Create from JSON
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] ?? '',
    username: json['username'] ?? '',
    displayName: json['display_name'] ?? json['displayName'],
    avatarUrl: json['avatar_url'] ?? json['avatarUrl'],
    bio: json['bio'],
    preferences: json['preferences'] != null
        ? UserPreferences.fromJson(json['preferences'])
        : const UserPreferences(),
    isPrivate: json['is_private'] ?? json['isPrivate'] ?? false,
    createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
  );

  @override
  List<Object?> get props => [id, username, displayName];
}

/// User preferences including favorite genres and languages
class UserPreferences extends Equatable {
  final List<int> favoriteGenreIds; // TMDB genre IDs selected during onboarding
  final List<String> languages;
  final bool simpleModeEnabled;
  final bool privateDefaultLogs;

  const UserPreferences({
    this.favoriteGenreIds = const [],
    this.languages = const ['en'],
    this.simpleModeEnabled = false,
    this.privateDefaultLogs = false,
  });

  UserPreferences copyWith({
    List<int>? favoriteGenreIds,
    List<String>? languages,
    bool? simpleModeEnabled,
    bool? privateDefaultLogs,
  }) {
    return UserPreferences(
      favoriteGenreIds: favoriteGenreIds ?? this.favoriteGenreIds,
      languages: languages ?? this.languages,
      simpleModeEnabled: simpleModeEnabled ?? this.simpleModeEnabled,
      privateDefaultLogs: privateDefaultLogs ?? this.privateDefaultLogs,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'favorite_genre_ids': favoriteGenreIds,
    'languages': languages,
    'simple_mode_enabled': simpleModeEnabled,
    'private_default_logs': privateDefaultLogs,
  };

  /// Create from JSON
  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        favoriteGenreIds: json['favorite_genre_ids'] != null
            ? List<int>.from(json['favorite_genre_ids'])
            : [],
        languages: json['languages'] != null
            ? List<String>.from(json['languages'])
            : ['en'],
        simpleModeEnabled: json['simple_mode_enabled'] ?? false,
        privateDefaultLogs: json['private_default_logs'] ?? false,
      );

  @override
  List<Object?> get props => [favoriteGenreIds, languages];
}
