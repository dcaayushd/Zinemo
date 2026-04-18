import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/providers/app_providers.dart';
import 'package:zinemo/screens/watchlist/watchlist_screen.dart';
import 'package:zinemo/services/tmdb_service.dart';
import 'package:zinemo/services/log_service.dart';
import 'package:zinemo/widgets/content_actions_sheet.dart';
import 'package:zinemo/widgets/detail_ratings_section.dart' as ratings_section;
import 'package:zinemo/theme/app_theme.dart';

class TVDetailScreen extends ConsumerStatefulWidget {
  final int tmdbId;
  final String? posterPath;
  final Content? initialContent;

  const TVDetailScreen({
    required this.tmdbId,
    this.posterPath,
    this.initialContent,
    super.key,
  });

  @override
  ConsumerState<TVDetailScreen> createState() => _TVDetailScreenState();
}

class _TVDetailScreenState extends ConsumerState<TVDetailScreen>
    with TickerProviderStateMixin {
  late AnimationController _kenBurnsController;
  late AnimationController _logModalController;
  late TextEditingController _reviewController;
  late Future<Credits?> _creditsFuture;

  bool _showLogModal = false;
  bool _isUpdatingSeasonProgress = false;
  double _userRating = 0.0;
  bool _isLiked = false;
  bool _isWatchlist = false;
  DateTime? _selectedDate;
  int? _selectedSeason;
  int? _selectedEpisode;
  bool _logFullShow =
      true; // true = log entire show, false = log specific episode

  @override
  void initState() {
    super.initState();
    _kenBurnsController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat(reverse: true);

    _logModalController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _reviewController = TextEditingController();
    _selectedDate = DateTime.now();
    _creditsFuture = TMDBService.getCredits(widget.tmdbId, 'tv');
  }

  @override
  void dispose() {
    _kenBurnsController.dispose();
    _logModalController.dispose();
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _saveLog() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) return;

      // Build tags for season/episode tracking
      List<String> tags = [];
      if (!_logFullShow &&
          _selectedSeason != null &&
          _selectedEpisode != null) {
        tags = [
          'S${_selectedSeason.toString().padLeft(2, '0')}E${_selectedEpisode.toString().padLeft(2, '0')}',
          'season:$_selectedSeason',
          'episode:$_selectedEpisode',
        ];
      }

      // Check if log entry already exists
      final existingResponse = await supabase
          .from('logs')
          .select('id')
          .eq('user_id', user.id)
          .eq('tmdb_id', widget.tmdbId)
          .eq('media_type', 'tv')
          .limit(1);

      final existingLogs = existingResponse as List?;

      if (existingLogs != null && existingLogs.isNotEmpty) {
        // Update existing log
        await supabase
            .from('logs')
            .update({
              'status': _isWatchlist ? 'watchlist' : 'watched',
              'rating': _userRating > 0 ? _userRating : null,
              'liked': _isLiked,
              'watched_date': _selectedDate?.toIso8601String(),
              'review': _reviewController.text.isEmpty
                  ? null
                  : _reviewController.text,
              'tags': tags.isNotEmpty ? tags : null,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existingLogs[0]['id'] as String);
      } else {
        // Insert new log
        await supabase.from('logs').insert({
          'user_id': user.id,
          'tmdb_id': widget.tmdbId,
          'media_type': 'tv',
          'status': _isWatchlist ? 'watchlist' : 'watched',
          'rating': _userRating > 0 ? _userRating : null,
          'liked': _isLiked,
          'watched_date': _selectedDate?.toIso8601String(),
          'review': _reviewController.text.isEmpty
              ? null
              : _reviewController.text,
          'tags': tags.isNotEmpty ? tags : null,
        });
      }

      // Show success animation
      _showSuccessCheckmark();

      // Invalidate watchlist and relevant providers to refresh UI
      ref.invalidate(watchlistProvider);
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(watchHistoryProvider);
      ref.invalidate(userLogProvider(widget.tmdbId));
      ref.invalidate(
        userMediaLogProvider((tmdbId: widget.tmdbId, mediaType: 'tv')),
      );
      ref.invalidate(contentRatingsProvider);
      ref.invalidate(episodeRatingsProvider);
      ref.invalidate(
        contentRatingsProvider((
          tmdbId: widget.tmdbId,
          mediaType: 'tv',
          fallbackVoteAverage: widget.initialContent?.voteAverage ?? 0.0,
          fallbackVoteCount: widget.initialContent?.voteCount ?? 0,
        )),
      );

      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          context.pop();
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving log: $e')));
      }
    }
  }

  void _showSuccessCheckmark() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Log saved successfully'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openContentActions(Content? content) {
    final resolved = content;
    if (resolved == null) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (ctx) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.of(ctx).size.height * 0.84,
            ),
            child: ContentActionsSheet(
              content: resolved,
              dialogMode: true,
              onDismiss: () => Navigator.of(ctx).pop(),
              onActionCompleted: () {
                ref.invalidate(watchlistProvider);
                ref.invalidate(continueWatchingProvider);
                ref.invalidate(watchHistoryProvider);
                ref.invalidate(userLogProvider(widget.tmdbId));
                ref.invalidate(
                  userMediaLogProvider((
                    tmdbId: widget.tmdbId,
                    mediaType: 'tv',
                  )),
                );
                ref.invalidate(contentRatingsProvider);
                ref.invalidate(episodeRatingsProvider);
                ref.invalidate(
                  contentRatingsProvider((
                    tmdbId: widget.tmdbId,
                    mediaType: resolved.mediaType,
                    fallbackVoteAverage: resolved.voteAverage ?? 0.0,
                    fallbackVoteCount: resolved.voteCount ?? 0,
                  )),
                );
                ref.invalidate(tvDetailProvider(widget.tmdbId));
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryMetaSection(BuildContext context, Content? content) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _openTrailer(content),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF4D6178),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('TRAILER'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 18),
          Text(
            'ABOUT',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content?.overview ?? 'No description available',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String? _directorLabel(Credits? credits) {
    if (credits == null) {
      return null;
    }

    final names = credits.crew
        .where((member) {
          final job = (member.job ?? '').toLowerCase();
          final dept = (member.department ?? '').toLowerCase();
          return job == 'director' || dept == 'directing';
        })
        .map((member) => member.name)
        .toSet()
        .toList();

    if (names.isEmpty) {
      return null;
    }

    return names.take(2).join(', ');
  }

  void _openTrailer(Content? content) {
    final trailer = content?.trailerUrls;
    if (trailer == null || trailer.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trailer not available yet')),
        );
      }
      return;
    }

    final trailerUrl = trailer.first;
    final youtubeId = YoutubePlayer.convertUrlToId(trailerUrl);
    if (youtubeId == null || youtubeId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid trailer URL')));
      }
      return;
    }

    final controller = YoutubePlayerController(
      initialVideoId: youtubeId,
      flags: const YoutubePlayerFlags(autoPlay: true, mute: false),
    );

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.background,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: YoutubePlayer(
            controller: controller,
            showVideoProgressIndicator: true,
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final movieAsync = ref.watch(tvDetailProvider(widget.tmdbId));

    return movieAsync.when(
      data: (movie) =>
          _buildDetailView(context, movie ?? widget.initialContent),
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildDetailView(BuildContext context, Content? movie) {
    final userLog = ref
        .watch(userMediaLogProvider((tmdbId: widget.tmdbId, mediaType: 'tv')))
        .asData
        ?.value;

    final ratingsSnapshot = ref
        .watch(
          contentRatingsProvider((
            tmdbId: widget.tmdbId,
            mediaType: 'tv',
            fallbackVoteAverage: movie?.voteAverage ?? 0.0,
            fallbackVoteCount: movie?.voteCount ?? 0,
          )),
        )
        .asData
        ?.value;

    final effectiveVoteAverage =
        ((ratingsSnapshot?.averageStars ?? ((movie?.voteAverage ?? 0.0) / 2)) *
                2)
            .clamp(0.0, 10.0);
    final effectiveVoteCount =
        ratingsSnapshot?.totalRatings ?? (movie?.voteCount ?? 0);

    final userAvatar = Supabase
        .instance
        .client
        .auth
        .currentUser
        ?.userMetadata?['avatar_url']
        ?.toString();

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ken Burns Backdrop
            Stack(
              children: [
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 1.08).animate(
                      CurvedAnimation(
                        parent: _kenBurnsController,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: CachedNetworkImage(
                      imageUrl:
                          movie?.backdropUrl ??
                          'https://via.placeholder.com/780x440',
                      fit: BoxFit.cover,
                      errorWidget: (ctx, url, err) =>
                          Container(color: Colors.black),
                    ),
                  ),
                ),
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: SafeArea(
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Poster + Title + Rating
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster
                      GestureDetector(
                        onTap: () => _openContentActions(movie),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl:
                                movie?.posterUrl ??
                                'https://via.placeholder.com/200x300',
                            width: 100,
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              movie?.title ?? 'Unknown',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            // TV Show badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'TV Show',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppTheme.primary),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Seasons info
                            if (movie?.totalSeasons != null)
                              Text(
                                '${movie!.totalSeasons} Season${movie.totalSeasons != 1 ? 's' : ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 10),
                            FutureBuilder<Credits?>(
                              future: _creditsFuture,
                              builder: (context, snapshot) {
                                final releaseDate = movie?.releaseDate;
                                final releaseLabel = releaseDate == null
                                    ? 'Unknown release date'
                                    : DateFormat(
                                        'dd MMM yyyy',
                                      ).format(releaseDate);
                                final directorLabel = _directorLabel(
                                  snapshot.data,
                                );

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      directorLabel != null
                                          ? '$releaseLabel · DIRECTED BY'
                                          : releaseLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.62,
                                            ),
                                            letterSpacing: 1.4,
                                          ),
                                    ),
                                    if (directorLabel != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        directorLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Colors.white.withValues(
                                                alpha: 0.92,
                                              ),
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _buildPrimaryMetaSection(context, movie),

            ratings_section.DetailRatingsSection(
              voteAverage: effectiveVoteAverage,
              voteCount: effectiveVoteCount,
              distribution: ratingsSnapshot?.distribution,
              distributionCounts: ratingsSnapshot?.distributionCounts,
              ctaLabel: _buildRatingsCtaLabel(userLog),
              avatarUrl: userAvatar,
              onCtaTap: () => _openContentActions(movie),
            ),

            FutureBuilder<Credits?>(
              future: _creditsFuture,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data == null) {
                  return const SizedBox.shrink();
                }

                return _buildCastAndCrewPreview(context, snapshot.data!);
              },
            ),

            _buildNextEpisodeCard(context, movie),

            _buildSeasonsAndEpisodesSection(context, movie, userLog),

            // Related Shows Section (placeholder)
            FutureBuilder<List<Content>?>(
              future: TMDBService.getRecommendations(widget.tmdbId, 'tv'),
              builder: (ctx, snapshot) {
                final items = snapshot.data ?? [];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Related Shows',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 150,
                        child: items.isEmpty
                            ? Center(
                                child: Text(
                                  'No recommendations available',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                              )
                            : ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: items.length,
                                itemBuilder: (ctx, idx) {
                                  final item = items[idx];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: item.posterUrl,
                                        width: 100,
                                        fit: BoxFit.cover,
                                        errorWidget: (ctx, url, err) =>
                                            Container(
                                              width: 100,
                                              color: Colors.white.withValues(
                                                alpha: 0.1,
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.image_outlined,
                                                  color: Colors.white30,
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Similar Shows Section (placeholder)
            FutureBuilder<List<Content>?>(
              future: TMDBService.getSimilar(widget.tmdbId, 'tv'),
              builder: (ctx, snapshot) {
                final items = snapshot.data ?? [];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Similar Shows',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 150,
                        child: items.isEmpty
                            ? Center(
                                child: Text(
                                  'No similar shows available',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                              )
                            : ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: items.length,
                                itemBuilder: (ctx, idx) {
                                  final item = items[idx];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: item.posterUrl,
                                        width: 100,
                                        fit: BoxFit.cover,
                                        errorWidget: (ctx, url, err) =>
                                            Container(
                                              width: 100,
                                              color: Colors.white.withValues(
                                                alpha: 0.1,
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.image_outlined,
                                                  color: Colors.white30,
                                                ),
                                              ),
                                            ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Watch On Section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Watch On',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildWatchLink(context, 'IMDb', Icons.language),
                      const SizedBox(width: 12),
                      _buildWatchLink(context, 'TMDB', Icons.language),
                      const SizedBox(width: 12),
                      _buildWatchLink(
                        context,
                        'YouTube',
                        Icons.play_circle_outline,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Mentions Section
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mentions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildMentionBadge(context, 'Emmy Nominated'),
                      _buildMentionBadge(context, 'Award Winner'),
                      _buildMentionBadge(context, 'Critically Acclaimed'),
                      _buildMentionBadge(context, 'Binge-Worthy'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // Log modal
      floatingActionButton: _showLogModal
          ? ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                CurvedAnimation(
                  parent: _logModalController,
                  curve: Curves.easeOut,
                ),
              ),
              child: GestureDetector(
                onTap: () {
                  _logModalController.reverse();
                  setState(() => _showLogModal = false);
                },
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: FloatingActionButton(
                    onPressed: _saveLog,
                    child: const Text(''),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildCastAndCrewPreview(BuildContext context, Credits credits) {
    final cast = credits.cast.take(8).toList();

    final directing = <Person>[];
    final writing = <Person>[];
    final music = <Person>[];

    final directingKeys = <String>{};
    final writingKeys = <String>{};
    final musicKeys = <String>{};

    for (final person in credits.crew) {
      final department = person.department?.toLowerCase() ?? '';
      final job = person.job?.toLowerCase() ?? '';
      final key = '${person.id}:${person.name.toLowerCase()}';

      if (department == 'directing' || job == 'director') {
        if (directingKeys.add(key)) {
          directing.add(person);
        }
      }
      if (department == 'writing' ||
          job.contains('writer') ||
          job == 'creator' ||
          job == 'screenplay') {
        if (writingKeys.add(key)) {
          writing.add(person);
        }
      }
      if (department == 'sound' ||
          department == 'music' ||
          job.contains('music') ||
          job.contains('composer')) {
        if (musicKeys.add(key)) {
          music.add(person);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cast & Crew',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 168,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: cast.length,
              itemBuilder: (context, index) {
                final person = cast[index];
                return GestureDetector(
                  onTap: () => _openPersonDetail(person),
                  child: Container(
                    width: 122,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: person.profileImageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: person.profileImageUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => Container(
                                      color: Colors.white.withValues(
                                        alpha: 0.05,
                                      ),
                                      child: const Icon(
                                        Icons.person_outline,
                                        color: Colors.white30,
                                        size: 34,
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    child: const Icon(
                                      Icons.person_outline,
                                      color: Colors.white30,
                                      size: 34,
                                    ),
                                  ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                            decoration: BoxDecoration(
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(10),
                                bottomRight: Radius.circular(10),
                              ),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.88),
                                ],
                              ),
                            ),
                            child: Text(
                              person.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildCrewColumn(
                  context,
                  label: 'Directing',
                  members: directing,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCrewColumn(
                  context,
                  label: 'Writing',
                  members: writing,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildCrewColumn(
                  context,
                  label: 'Music',
                  members: music,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openPersonDetail(Person person) {
    if (person.id <= 0) {
      return;
    }

    context.pushNamed(
      'person-detail',
      pathParameters: {'personId': person.id.toString()},
      extra: person,
    );
  }

  Widget _buildCrewColumn(
    BuildContext context, {
    required String label,
    required List<Person> members,
  }) {
    final visible = members.take(3).toList();
    final hasMore = members.length > visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.68),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        if (visible.isEmpty)
          Text(
            '—',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.2,
            ),
          )
        else
          ...visible.map(
            (member) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: GestureDetector(
                onTap: () => _openPersonDetail(member),
                child: Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
        if (hasMore)
          Text(
            '...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.92),
              height: 1.2,
            ),
          ),
      ],
    );
  }

  Widget _buildNextEpisodeCard(BuildContext context, Content? movie) {
    final season = movie?.nextSeasonNumber ?? (_selectedSeason ?? 1);
    final episode = movie?.nextEpisodeNumber ?? (_selectedEpisode ?? 1);
    final episodeCode =
        'S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}';

    final nextEpisodeName = movie?.nextEpisodeName?.trim();
    final title = nextEpisodeName != null && nextEpisodeName.isNotEmpty
        ? '$episodeCode - "$nextEpisodeName"'
        : '$episodeCode - Upcoming episode';

    final nextAirDate = movie?.nextAirDate;
    final hasTime =
        nextAirDate != null && (nextAirDate.hour > 0 || nextAirDate.minute > 0);
    final dateLabel = nextAirDate == null
        ? 'Release date to be announced'
        : hasTime
        ? DateFormat('EEEE, dd MMM yyyy, HH:mm').format(nextAirDate.toLocal())
        : DateFormat('EEEE, dd MMM yyyy').format(nextAirDate.toLocal());

    const accent = Color(0xFFFF4A4A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule_rounded, color: accent, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Next Episode:',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.94),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              dateLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeasonsAndEpisodesSection(
    BuildContext context,
    Content? movie,
    Log? userLog,
  ) {
    final totalSeasons = _resolveTotalSeasons(movie);
    final totalEpisodes = _resolveTotalEpisodes(movie, totalSeasons);
    final watchedEpisodes = _watchedEpisodesFromLog(
      userLog,
      movie,
      totalSeasons,
      totalEpisodes,
    );

    final selectedFromTags = _extractSeasonEpisode(
      userLog?.tags ?? const [],
    ).season;
    final fallbackSeason = selectedFromTags <= 0 ? 1 : selectedFromTags;
    final selectedSeason = (_selectedSeason ?? fallbackSeason).clamp(
      1,
      totalSeasons,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Seasons',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.playlist_add_check_rounded,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(totalSeasons, (index) {
            final seasonNumber = totalSeasons - index;
            final episodesInSeason = _episodesInSeason(
              seasonNumber: seasonNumber,
              totalSeasons: totalSeasons,
              totalEpisodes: totalEpisodes,
            );

            var episodesBefore = 0;
            for (var season = 1; season < seasonNumber; season++) {
              episodesBefore += _episodesInSeason(
                seasonNumber: season,
                totalSeasons: totalSeasons,
                totalEpisodes: totalEpisodes,
              );
            }

            final watchedInSeason = (watchedEpisodes - episodesBefore).clamp(
              0,
              episodesInSeason,
            );
            final progress = episodesInSeason == 0
                ? 0.0
                : watchedInSeason / episodesInSeason;
            final isComplete =
                watchedInSeason >= episodesInSeason && episodesInSeason > 0;
            final isSelected = selectedSeason == seasonNumber;
            const accent = Color(0xFFFF4A4A);

            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedSeason = seasonNumber;
                });

                context.pushNamed(
                  'tv-season-detail',
                  pathParameters: {
                    'tmdbId': widget.tmdbId.toString(),
                    'seasonNumber': seasonNumber.toString(),
                  },
                  extra: movie,
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _isUpdatingSeasonProgress
                          ? null
                          : () => _markSeasonAsWatchedFromDetail(
                              seasonNumber: seasonNumber,
                              episodeInSeason: episodesInSeason,
                              totalSeasons: totalSeasons,
                              totalEpisodes: totalEpisodes,
                            ),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          color: isComplete ? accent : Colors.transparent,
                          border: Border.all(
                            color: isComplete
                                ? accent
                                : Colors.white.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                        child: isComplete
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.black,
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Season $seasonNumber',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: isComplete
                                            ? accent
                                            : Colors.white.withValues(
                                                alpha: 0.94,
                                              ),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                              Text(
                                '$watchedInSeason/$episodesInSeason (${(progress * 100).toStringAsFixed(0)}%)',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: isComplete
                                          ? accent
                                          : Colors.white.withValues(alpha: 0.9),
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: isComplete
                                    ? accent
                                    : Colors.white.withValues(alpha: 0.84),
                                size: 24,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.14,
                              ),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF4A4A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _markSeasonAsWatchedFromDetail({
    required int seasonNumber,
    required int episodeInSeason,
    required int totalSeasons,
    required int totalEpisodes,
  }) async {
    if (episodeInSeason <= 0 || _isUpdatingSeasonProgress) {
      return;
    }

    var episodesBefore = 0;
    for (var season = 1; season < seasonNumber; season++) {
      episodesBefore += _episodesInSeason(
        seasonNumber: season,
        totalSeasons: totalSeasons,
        totalEpisodes: totalEpisodes,
      );
    }

    final progress = (episodesBefore + episodeInSeason).clamp(1, totalEpisodes);

    setState(() => _isUpdatingSeasonProgress = true);
    try {
      await LogService.markTVProgress(
        tmdbId: widget.tmdbId,
        season: seasonNumber,
        episode: episodeInSeason,
        progress: progress,
        totalEpisodes: totalEpisodes,
        setWatchedDate: true,
        episodesInSeasonForSeasonMark: episodeInSeason,
      );

      ref.invalidate(userLogProvider(widget.tmdbId));
      ref.invalidate(
        userMediaLogProvider((tmdbId: widget.tmdbId, mediaType: 'tv')),
      );
      ref.invalidate(tvDetailProvider(widget.tmdbId));
      ref.invalidate(watchHistoryProvider);
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(watchlistProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Season $seasonNumber marked watched')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark season watched: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingSeasonProgress = false);
      }
    }
  }

  int _resolveTotalSeasons(Content? movie) {
    return math.max(1, movie?.totalSeasons ?? 1);
  }

  int _resolveTotalEpisodes(Content? movie, int totalSeasons) {
    final rawEpisodes = movie?.totalEpisodes;
    if (rawEpisodes != null && rawEpisodes > 0) {
      return rawEpisodes;
    }

    return totalSeasons * 8;
  }

  int _episodesInSeason({
    required int seasonNumber,
    required int totalSeasons,
    required int totalEpisodes,
  }) {
    final base = totalEpisodes ~/ totalSeasons;
    final remainder = totalEpisodes % totalSeasons;
    return base + (seasonNumber <= remainder ? 1 : 0);
  }

  int _watchedEpisodesFromLog(
    Log? userLog,
    Content? movie,
    int totalSeasons,
    int totalEpisodes,
  ) {
    if (userLog == null) {
      return 0;
    }

    if (userLog.status == LogStatus.watched) {
      return totalEpisodes;
    }

    final taggedEpisodeCount = _extractEpisodeMarkerCodes(
      userLog.tags,
    ).length.clamp(0, totalEpisodes);

    final progressTag = _extractTagInt(userLog.tags, 'progress');
    if (progressTag != null) {
      return math.max(progressTag.clamp(0, totalEpisodes), taggedEpisodeCount);
    }

    final parsed = _extractSeasonEpisode(userLog.tags);
    final epsPerSeason = math.max(1, (totalEpisodes / totalSeasons).ceil());
    final watchedFromPosition =
        (((parsed.season - 1) * epsPerSeason) + parsed.episode).clamp(
          0,
          totalEpisodes,
        );

    switch (userLog.status) {
      case LogStatus.watching:
        return math.max(watchedFromPosition, taggedEpisodeCount);
      case LogStatus.watchlist:
      case LogStatus.planToWatch:
      case LogStatus.dropped:
        return taggedEpisodeCount;
      default:
        return 0;
    }
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

  String _buildRatingsCtaLabel(Log? userLog) {
    if (userLog == null) {
      return 'Rate, log, review, add to list + more';
    }

    if (userLog.rating != null) {
      return "You've logged this show ${_formatStarsText(userLog.rating!)}";
    }

    return "You've logged this show";
  }

  String _formatStarsText(double rating) {
    final fullStars = rating.floor().clamp(0, 5);
    final halfStar = (rating - fullStars) >= 0.5;
    final stars = List.generate(fullStars, (_) => '★').join();
    return halfStar ? '$stars½' : stars;
  }

  Widget _buildWatchLink(BuildContext context, String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildMentionBadge(BuildContext context, String label) {
    // Map label to icon/color for festival/award badges
    IconData iconData = Icons.star;
    Color badgeColor = AppTheme.primary;

    switch (label.toLowerCase()) {
      case 'tiff':
        iconData = Icons.theaters;
        badgeColor = const Color(0xFF8B5CF6);
        break;
      case 'highon films':
        iconData = Icons.movie;
        badgeColor = const Color(0xFFEC4899);
        break;
      case 'award winner':
        iconData = Icons.emoji_events;
        badgeColor = const Color(0xFFF59E0B);
        break;
      case 'featured':
      case 'critically acclaimed':
      case 'binge-worthy':
      case 'emmy nominated':
        iconData = Icons.star;
        badgeColor = AppTheme.primary;
        break;
    }

    return Stack(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.2),
            border: Border.all(
              color: badgeColor.withValues(alpha: 0.5),
              width: 2,
            ),
            shape: BoxShape.circle,
          ),
          child: Center(child: Icon(iconData, color: badgeColor, size: 28)),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                '✓',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
