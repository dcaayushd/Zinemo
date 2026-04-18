class Person {
  final int id;
  final String name;
  final String? profilePath;
  final String? character; // Role in the movie/show (for cast)
  final String? job; // Job title (for crew)
  final String? department; // Department (for crew)
  final int? popularity;
  final String? biography;
  final DateTime? birthday;
  final String? placeOfBirth;

  Person({
    required this.id,
    required this.name,
    this.profilePath,
    this.character,
    this.job,
    this.department,
    this.popularity,
    this.biography,
    this.birthday,
    this.placeOfBirth,
  });

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      profilePath: json['profile_path'],
      character: json['character'], // Cast
      job: json['job'], // Crew
      department: json['department'], // Crew
      popularity: json['popularity']?.toInt(),
      biography: json['biography'],
      birthday: json['birthday'] != null
          ? DateTime.tryParse(json['birthday'])
          : null,
      placeOfBirth: json['place_of_birth'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'profile_path': profilePath,
      'character': character,
      'job': job,
      'department': department,
      'popularity': popularity,
      'biography': biography,
      'birthday': birthday?.toIso8601String(),
      'place_of_birth': placeOfBirth,
    };
  }

  // For cast
  bool get isCast => character != null;

  // For crew
  bool get isCrew => job != null && department != null;

  // Profile image URL
  String? get profileImageUrl => profilePath != null
      ? 'https://image.tmdb.org/t/p/w342$profilePath'
      : null;
}

/// Cast/Crew container
class Credits {
  final List<Person> cast; // Sorted by popularity
  final List<Person> crew; // Directors, producers, writers, etc.

  Credits({required this.cast, required this.crew});

  // Get directors from crew
  List<Person> get directors => crew.where((c) => c.job == 'Director').toList();

  // Get writers from crew
  List<Person> get writers =>
      crew.where((c) => c.department == 'Writing').toList();

  // Get producers from crew
  List<Person> get producers => crew.where((c) => c.job == 'Producer').toList();

  factory Credits.fromJson(Map<String, dynamic> json) {
    final castList =
        (json['cast'] as List?)
            ?.map((c) => Person.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];
    final crewList =
        (json['crew'] as List?)
            ?.map((c) => Person.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];

    // Sort cast by popularity/billing order
    castList.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));

    return Credits(cast: castList, crew: crewList);
  }

  Map<String, dynamic> toJson() {
    return {
      'cast': cast.map((c) => c.toJson()).toList(),
      'crew': crew.map((c) => c.toJson()).toList(),
    };
  }
}
