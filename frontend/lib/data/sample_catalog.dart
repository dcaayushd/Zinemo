import 'package:flutter/material.dart';

class ZinemoTitle {
  const ZinemoTitle({
    required this.id,
    required this.title,
    required this.tagline,
    required this.overview,
    required this.mediaType,
    required this.genres,
    required this.year,
    required this.runtimeMinutes,
    required this.rating,
    required this.themeColor,
    required this.availability,
    required this.cast,
    required this.reasonSeed,
    required this.badges,
  });

  final int id;
  final String title;
  final String tagline;
  final String overview;
  final String mediaType;
  final List<String> genres;
  final int year;
  final int runtimeMinutes;
  final double rating;
  final Color themeColor;
  final String availability;
  final List<String> cast;
  final String reasonSeed;
  final List<String> badges;

  String get runtimeLabel {
    final hours = runtimeMinutes ~/ 60;
    final minutes = runtimeMinutes % 60;
    if (hours == 0) {
      return '${runtimeMinutes}m';
    }
    return '${hours}h ${minutes}m';
  }
}

const kRecommendationFilters = <String>[
  'Top 10',
  'Romance',
  'Drama',
  'Horror',
  'Action',
  'Comedy',
  'Thriller',
  'Sci-Fi',
  'Documentary',
  'Animation',
];

const kOnboardingGenres = <String>[
  'Drama',
  'Sci-Fi',
  'Thriller',
  'Romance',
  'Comedy',
  'Animation',
  'Fantasy',
  'Mystery',
  'Documentary',
  'Action',
];

const kSeedTitles = <ZinemoTitle>[
  ZinemoTitle(
    id: 603,
    title: 'The Matrix',
    tagline: 'Reality bends. Choice remains.',
    overview:
        'A cyberpunk awakening that fuses kinetic action, digital paranoia, and sleek philosophy into one endlessly rewatchable ride.',
    mediaType: 'movie',
    genres: ['Sci-Fi', 'Action', 'Thriller'],
    year: 1999,
    runtimeMinutes: 136,
    rating: 8.7,
    themeColor: Color(0xFF1B6B6A),
    availability: 'Max',
    cast: ['Keanu Reeves', 'Carrie-Anne Moss', 'Laurence Fishburne'],
    reasonSeed: 'Mind-bending futures',
    badges: ['Starter Pick'],
  ),
  ZinemoTitle(
    id: 11,
    title: 'Star Wars',
    tagline: 'Myths at lightspeed.',
    overview:
        'A classic hero journey carried by cosmic scale, tactile production design, and just enough rebellion to feel eternal.',
    mediaType: 'movie',
    genres: ['Sci-Fi', 'Fantasy', 'Adventure'],
    year: 1977,
    runtimeMinutes: 121,
    rating: 8.6,
    themeColor: Color(0xFFAB6A17),
    availability: 'Disney+',
    cast: ['Mark Hamill', 'Carrie Fisher', 'Harrison Ford'],
    reasonSeed: 'Big-screen wonder',
    badges: ['Starter Pick'],
  ),
  ZinemoTitle(
    id: 872585,
    title: 'Oppenheimer',
    tagline: 'Brilliance with a blast radius.',
    overview:
        'A prestige spectacle built on dread, obsession, and the uneasy cost of intellect pushed beyond moral comfort.',
    mediaType: 'movie',
    genres: ['Drama', 'Thriller', 'History'],
    year: 2023,
    runtimeMinutes: 180,
    rating: 8.4,
    themeColor: Color(0xFF8E4B24),
    availability: 'Peacock',
    cast: ['Cillian Murphy', 'Emily Blunt', 'Robert Downey Jr.'],
    reasonSeed: 'Precision drama',
    badges: ['Starter Pick'],
  ),
  ZinemoTitle(
    id: 129,
    title: 'Spirited Away',
    tagline: 'A dream you can walk through.',
    overview:
        'Miyazaki turns vulnerability into wonder, crafting a coming-of-age fantasy where every corridor holds a new spell.',
    mediaType: 'movie',
    genres: ['Animation', 'Fantasy', 'Drama'],
    year: 2001,
    runtimeMinutes: 125,
    rating: 8.6,
    themeColor: Color(0xFF7A143D),
    availability: 'Max',
    cast: ['Rumi Hiiragi', 'Miyu Irino', 'Mari Natsuki'],
    reasonSeed: 'Tender magic',
    badges: ['Starter Pick'],
  ),
  ZinemoTitle(
    id: 238,
    title: 'The Godfather',
    tagline: 'Power whispers louder than gunfire.',
    overview:
        'An intimate crime epic where family loyalty, ritual, and patience make every decision feel heavier than violence.',
    mediaType: 'movie',
    genres: ['Drama', 'Crime'],
    year: 1972,
    runtimeMinutes: 175,
    rating: 9.2,
    themeColor: Color(0xFF471C12),
    availability: 'Paramount+',
    cast: ['Marlon Brando', 'Al Pacino', 'James Caan'],
    reasonSeed: 'Legacy storytelling',
    badges: ['Starter Pick'],
  ),
];

const kSampleCatalog = <ZinemoTitle>[
  ZinemoTitle(
    id: 603,
    title: 'The Matrix',
    tagline: 'Reality bends. Choice remains.',
    overview:
        'A cyberpunk awakening that fuses kinetic action, digital paranoia, and sleek philosophy into one endlessly rewatchable ride.',
    mediaType: 'movie',
    genres: ['Sci-Fi', 'Action', 'Thriller'],
    year: 1999,
    runtimeMinutes: 136,
    rating: 8.7,
    themeColor: Color(0xFF1B6B6A),
    availability: 'Max',
    cast: ['Keanu Reeves', 'Carrie-Anne Moss', 'Laurence Fishburne'],
    reasonSeed: 'Mind-bending futures',
    badges: ['Top 10', 'Because You Watched'],
  ),
  ZinemoTitle(
    id: 11,
    title: 'Star Wars',
    tagline: 'Myths at lightspeed.',
    overview:
        'A classic hero journey carried by cosmic scale, tactile production design, and just enough rebellion to feel eternal.',
    mediaType: 'movie',
    genres: ['Sci-Fi', 'Fantasy', 'Adventure'],
    year: 1977,
    runtimeMinutes: 121,
    rating: 8.6,
    themeColor: Color(0xFFAB6A17),
    availability: 'Disney+',
    cast: ['Mark Hamill', 'Carrie Fisher', 'Harrison Ford'],
    reasonSeed: 'Big-screen wonder',
    badges: ['Classic', 'Top 10'],
  ),
  ZinemoTitle(
    id: 129,
    title: 'Spirited Away',
    tagline: 'A dream you can walk through.',
    overview:
        'Miyazaki turns vulnerability into wonder, crafting a coming-of-age fantasy where every corridor holds a new spell.',
    mediaType: 'movie',
    genres: ['Animation', 'Fantasy', 'Drama'],
    year: 2001,
    runtimeMinutes: 125,
    rating: 8.6,
    themeColor: Color(0xFF7A143D),
    availability: 'Max',
    cast: ['Rumi Hiiragi', 'Miyu Irino', 'Mari Natsuki'],
    reasonSeed: 'Tender magic',
    badges: ['Animation', 'Wrapped Favorite'],
  ),
  ZinemoTitle(
    id: 872585,
    title: 'Oppenheimer',
    tagline: 'Brilliance with a blast radius.',
    overview:
        'A prestige spectacle built on dread, obsession, and the uneasy cost of intellect pushed beyond moral comfort.',
    mediaType: 'movie',
    genres: ['Drama', 'Thriller', 'History'],
    year: 2023,
    runtimeMinutes: 180,
    rating: 8.4,
    themeColor: Color(0xFF8E4B24),
    availability: 'Peacock',
    cast: ['Cillian Murphy', 'Emily Blunt', 'Robert Downey Jr.'],
    reasonSeed: 'Precision drama',
    badges: ['New Release', 'Awards Run'],
  ),
  ZinemoTitle(
    id: 238,
    title: 'The Godfather',
    tagline: 'Power whispers louder than gunfire.',
    overview:
        'An intimate crime epic where family loyalty, ritual, and patience make every decision feel heavier than violence.',
    mediaType: 'movie',
    genres: ['Drama', 'Crime'],
    year: 1972,
    runtimeMinutes: 175,
    rating: 9.2,
    themeColor: Color(0xFF471C12),
    availability: 'Paramount+',
    cast: ['Marlon Brando', 'Al Pacino', 'James Caan'],
    reasonSeed: 'Legacy storytelling',
    badges: ['Top Rated'],
  ),
  ZinemoTitle(
    id: 157336,
    title: 'Interstellar',
    tagline: 'Time stretches, love refuses.',
    overview:
        'A vast, emotional space odyssey that uses cosmic scale to make parenthood feel crushingly immediate.',
    mediaType: 'movie',
    genres: ['Sci-Fi', 'Drama', 'Adventure'],
    year: 2014,
    runtimeMinutes: 169,
    rating: 8.7,
    themeColor: Color(0xFF203B66),
    availability: 'Prime Video',
    cast: ['Matthew McConaughey', 'Anne Hathaway', 'Jessica Chastain'],
    reasonSeed: 'Heart-forward sci-fi',
    badges: ['Popular Again'],
  ),
  ZinemoTitle(
    id: 155,
    title: 'The Dark Knight',
    tagline: 'Chaos tests the mask.',
    overview:
        'A crime saga disguised as a blockbuster, powered by moral pressure and relentless urban momentum.',
    mediaType: 'movie',
    genres: ['Action', 'Crime', 'Drama'],
    year: 2008,
    runtimeMinutes: 152,
    rating: 9.0,
    themeColor: Color(0xFF243044),
    availability: 'Max',
    cast: ['Christian Bale', 'Heath Ledger', 'Aaron Eckhart'],
    reasonSeed: 'Operatic intensity',
    badges: ['Top Rated'],
  ),
  ZinemoTitle(
    id: 12444,
    title: 'Harry Potter',
    tagline: 'Wonder with a winter bite.',
    overview:
        'School-year fantasy comfort, elevated by tactile production design and a cast that sells every corridor as legend.',
    mediaType: 'movie',
    genres: ['Fantasy', 'Adventure', 'Drama'],
    year: 2001,
    runtimeMinutes: 152,
    rating: 7.6,
    themeColor: Color(0xFF503D8B),
    availability: 'Peacock',
    cast: ['Daniel Radcliffe', 'Emma Watson', 'Rupert Grint'],
    reasonSeed: 'Cozy spectacle',
    badges: ['Rewatch'],
  ),
  ZinemoTitle(
    id: 348,
    title: 'Alien',
    tagline: 'Silence is never empty.',
    overview:
        'A haunted-house thriller in deep space where atmosphere, labor, and terror feel inseparable.',
    mediaType: 'movie',
    genres: ['Horror', 'Sci-Fi', 'Thriller'],
    year: 1979,
    runtimeMinutes: 117,
    rating: 8.5,
    themeColor: Color(0xFF304A3F),
    availability: 'Hulu',
    cast: ['Sigourney Weaver', 'Tom Skerritt', 'Veronica Cartwright'],
    reasonSeed: 'Controlled dread',
    badges: ['Late Night'],
  ),
  ZinemoTitle(
    id: 13,
    title: 'Forrest Gump',
    tagline: 'A life told at full stride.',
    overview:
        'Warm, sentimental, and surprisingly agile, balancing intimate sincerity with a sweeping sense of American memory.',
    mediaType: 'movie',
    genres: ['Drama', 'Romance'],
    year: 1994,
    runtimeMinutes: 142,
    rating: 8.8,
    themeColor: Color(0xFF6D5B4A),
    availability: 'Paramount+',
    cast: ['Tom Hanks', 'Robin Wright', 'Gary Sinise'],
    reasonSeed: 'Sweepingly human',
    badges: ['Comfort Watch'],
  ),
  ZinemoTitle(
    id: 496243,
    title: 'Parasite',
    tagline: 'A staircase built from class tension.',
    overview:
        'A razor-sharp social thriller that shifts tone with unnerving confidence while staying formally precise.',
    mediaType: 'movie',
    genres: ['Thriller', 'Drama', 'Comedy'],
    year: 2019,
    runtimeMinutes: 132,
    rating: 8.5,
    themeColor: Color(0xFF2A5A44),
    availability: 'Hulu',
    cast: ['Song Kang-ho', 'Cho Yeo-jeong', 'Park So-dam'],
    reasonSeed: 'Darkly funny tension',
    badges: ['Critics Choice'],
  ),
  ZinemoTitle(
    id: 278,
    title: 'The Shawshank Redemption',
    tagline: 'Hope under concrete weight.',
    overview:
        'Patient, humane, and quietly monumental, turning endurance and friendship into something close to transcendence.',
    mediaType: 'movie',
    genres: ['Drama'],
    year: 1994,
    runtimeMinutes: 142,
    rating: 9.3,
    themeColor: Color(0xFF2A4762),
    availability: 'Max',
    cast: ['Tim Robbins', 'Morgan Freeman', 'Bob Gunton'],
    reasonSeed: 'Earned catharsis',
    badges: ['Top Rated'],
  ),
  ZinemoTitle(
    id: 641,
    title: 'Requiem for a Dream',
    tagline: 'Beautiful descent, no landing.',
    overview:
        'An overwhelming psychological spiral that weaponizes montage, sound, and repetition into pure dread.',
    mediaType: 'movie',
    genres: ['Drama', 'Thriller'],
    year: 2000,
    runtimeMinutes: 102,
    rating: 8.3,
    themeColor: Color(0xFF5A2628),
    availability: 'Mubi',
    cast: ['Ellen Burstyn', 'Jared Leto', 'Jennifer Connelly'],
    reasonSeed: 'Formal intensity',
    badges: ['Mood Piece'],
  ),
];
