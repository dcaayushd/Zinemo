import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import 'package:zinemo/widgets/cast_section.dart';
import 'package:zinemo/widgets/content_actions_sheet.dart';
import 'package:zinemo/widgets/detail_ratings_section.dart' as ratings_section;
import 'package:zinemo/theme/app_theme.dart';

class MovieDetailScreen extends ConsumerStatefulWidget {
  final int tmdbId;
  final String? posterPath;
  final Content? initialContent;

  const MovieDetailScreen({
    required this.tmdbId,
    this.posterPath,
    this.initialContent,
    super.key,
  });

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen>
    with TickerProviderStateMixin {
  static const Color _detailTone = AppTheme.background;

  late AnimationController _kenBurnsController;
  late AnimationController _logModalController;
  late TextEditingController _reviewController;
  late TextEditingController _tagsController;

  bool _showLogModal = false;
  double _userRating = 0.0;
  bool _isLiked = false;
  final bool _isWatchlist = false;
  DateTime? _selectedDate;

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
    _tagsController = TextEditingController();
    _selectedDate = DateTime.now();
  }

  @override
  void dispose() {
    _kenBurnsController.dispose();
    _logModalController.dispose();
    _reviewController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _saveLog() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      final mediaType = widget.initialContent?.mediaType ?? 'movie';

      if (user == null) return;

      // Check if log entry already exists
      final existingResponse = await supabase
          .from('logs')
          .select('id')
          .eq('user_id', user.id)
          .eq('tmdb_id', widget.tmdbId)
          .eq('media_type', mediaType)
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
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', existingLogs[0]['id'] as String);
      } else {
        // Insert new log
        await supabase.from('logs').insert({
          'user_id': user.id,
          'tmdb_id': widget.tmdbId,
          'media_type': mediaType,
          'status': _isWatchlist ? 'watchlist' : 'watched',
          'rating': _userRating > 0 ? _userRating : null,
          'liked': _isLiked,
          'watched_date': _selectedDate?.toIso8601String(),
          'review': _reviewController.text.isEmpty
              ? null
              : _reviewController.text,
        });
      }

      // Show success animation
      _showSuccessCheckmark();

      // Invalidate watchlist and relevant providers to refresh UI
      ref.invalidate(watchlistProvider);
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(watchHistoryProvider);
      ref.invalidate(userLogProvider(widget.tmdbId));
      ref.invalidate(contentRatingsProvider);
      ref.invalidate(episodeRatingsProvider);
      ref.invalidate(
        contentRatingsProvider((
          tmdbId: widget.tmdbId,
          mediaType: mediaType,
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
    // Play success animation (could use Lottie here)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Log saved successfully'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentAsync = ref.watch(movieDetailProvider(widget.tmdbId));

    // Check if this is a TV show and redirect accordingly
    return contentAsync.when(
      data: (content) {
        if (content?.mediaType == 'tv') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.pushReplacementNamed(
              'tv-detail',
              pathParameters: {'tmdbId': widget.tmdbId.toString()},
              extra: content,
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: _detailTone,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 400,
                collapsedHeight: kToolbarHeight + 20,
                pinned: true,
                backgroundColor: _detailTone,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                    child: IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedBuilder(
                        animation: _kenBurnsController,
                        builder: (ctx, child) {
                          final scaleValue =
                              1.0 + (_kenBurnsController.value * 0.08);
                          return Transform.scale(
                            scale: scaleValue,
                            child: child,
                          );
                        },
                        child: CachedNetworkImage(
                          imageUrl:
                              content?.backdropUrl ??
                              content?.posterUrl ??
                              'https://via.placeholder.com/1280x720',
                          fit: BoxFit.cover,
                          errorWidget: (ctx, err, st) => Container(
                            color: AppTheme.card,
                            child: const Icon(Icons.movie),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: ClipPath(
                          clipper: DiagonalClipper(),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  _detailTone.withValues(alpha: 0.55),
                                  _detailTone,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildContent(context, contentAsync)),
            ],
          ),
        );
      },
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

  // Main content section
  Widget _buildContent(
    BuildContext context,
    AsyncValue<Content?> contentAsync,
  ) {
    final movie = contentAsync.value ?? widget.initialContent;
    final mediaType = movie?.mediaType ?? 'movie';
    final userLog = ref.watch(userLogProvider(widget.tmdbId)).asData?.value;

    final ratingsSnapshot = ref
        .watch(
          contentRatingsProvider((
            tmdbId: widget.tmdbId,
            mediaType: mediaType,
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

    return Container(
      color: _detailTone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster + Title + Rating
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster thumbnail
                Hero(
                  tag: 'poster-${widget.tmdbId}',
                  child: GestureDetector(
                    onTap: () => _openContentActions(movie),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl:
                            movie?.posterPath ??
                            'https://via.placeholder.com/342x513',
                        width: 100,
                        height: 150,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie?.title ?? 'Movie Title',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            movie?.releaseDate?.year.toString() ?? 'N/A',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                      // TV Show info if applicable
                      if (movie?.mediaType == 'tv') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.tv,
                              size: 14,
                              color: Colors.white70,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'TV Show',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                        if (movie?.nextSeasonNumber != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 14,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'S${movie!.nextSeasonNumber.toString().padLeft(2, '0')}E${movie.nextEpisodeNumber?.toString().padLeft(2, '0') ?? '?'}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppTheme.primary),
                              ),
                            ],
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      // TMDB Rating Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              (movie?.voteAverage ?? 0.0).toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          FutureBuilder<Credits?>(
            future: TMDBService.getCredits(widget.tmdbId, mediaType),
            builder: (context, snapshot) {
              final credits = snapshot.data;
              return _buildPrimaryMetaSection(context, movie, credits);
            },
          ),

          // Log Modal - Spring slide-up
          if (_showLogModal)
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _logModalController,
                      curve: Curves.elasticOut,
                    ),
                  ),
              child: _buildLogModal(context),
            ),

          ratings_section.DetailRatingsSection(
            voteAverage: effectiveVoteAverage,
            voteCount: effectiveVoteCount,
            distribution: ratingsSnapshot?.distribution,
            distributionCounts: ratingsSnapshot?.distributionCounts,
            ctaLabel: _buildRatingsCtaLabel(userLog),
            avatarUrl: userAvatar,
            onCtaTap: () => _openContentActions(movie),
          ),

          // Cast and Crew sections
          FutureBuilder<Credits?>(
            future: TMDBService.getCredits(
              widget.tmdbId,
              movie?.mediaType ?? 'movie',
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return const SizedBox.shrink();
              }

              final credits = snapshot.data!;
              return Column(
                children: [
                  if (credits.cast.isNotEmpty)
                    CastSection(cast: credits.cast.take(15).toList()),
                  if (credits.directors.isNotEmpty)
                    CrewSection(crew: credits.directors, title: 'Directors'),
                  if (credits.writers.isNotEmpty)
                    CrewSection(crew: credits.writers, title: 'Writers'),
                ],
              );
            },
          ),

          // Related Films Section (placeholder)
          FutureBuilder<List<Content>?>(
            future: TMDBService.getRecommendations(widget.tmdbId, 'movie'),
            builder: (ctx, snapshot) {
              final items = snapshot.data ?? [];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Related Films',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                                      errorWidget: (ctx, url, err) => Container(
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

          // Similar Films Section (placeholder)
          FutureBuilder<List<Content>?>(
            future: TMDBService.getSimilar(widget.tmdbId, 'movie'),
            builder: (ctx, snapshot) {
              final items = snapshot.data ?? [];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Similar Films',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 150,
                      child: items.isEmpty
                          ? Center(
                              child: Text(
                                'No similar films available',
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
                                      errorWidget: (ctx, url, err) => Container(
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

          // Open In Section
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
                    _buildMentionBadge(context, 'TIFF'),
                    _buildMentionBadge(context, 'HighOn Films'),
                    _buildMentionBadge(context, 'Award Winner'),
                    _buildMentionBadge(context, 'Featured'),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
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
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryMetaSection(
    BuildContext context,
    Content? content,
    Credits? credits,
  ) {
    final releaseDate = content?.releaseDate;
    final releaseLabel = releaseDate == null
        ? 'Unknown release date'
        : DateFormat('dd MMM yyyy').format(releaseDate);

    final directorLabel = _directorLabel(credits);
    final runtime = content?.runtime;
    final runtimeLabel = runtime != null && runtime > 0
        ? '$runtime mins'
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            directorLabel != null
                ? '$releaseLabel · DIRECTED BY'
                : releaseLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.62),
              letterSpacing: 1.4,
            ),
          ),
          if (directorLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              directorLabel,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
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
              if (runtimeLabel != null) ...[
                const SizedBox(width: 14),
                Text(
                  runtimeLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ],
          ),
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

  // Log Modal with rating, date picker, review
  Widget _buildLogModal(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Log Your Watch',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Star Rating with half-star support
            Text(
              'Your Rating',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildStarRating(),
            const SizedBox(height: 20),

            // Date Picker
            Text(
              'Watched Date',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('MMM dd, yyyy').format(_selectedDate!),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const Icon(Icons.calendar_today, size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Review Text Field
            Text(
              'Your Review (Optional)',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'What did you think?',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Liked toggle
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() => _isLiked = !_isLiked);
                  },
                  icon: Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_outline,
                    color: _isLiked ? Colors.red : Colors.white70,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Mark as favorite',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() => _showLogModal = false);
                      _logModalController.reverse();
                    },
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _saveLog,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Log It'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Star rating widget with half-star support
  Widget _buildStarRating() {
    final stars = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0];
    return Wrap(
      spacing: 6,
      children: stars.map((star) {
        final isFilled = _userRating >= star;
        return GestureDetector(
          onTap: () {
            setState(() => _userRating = star);
            HapticFeedback.selectionClick();
          },
          child: Icon(
            isFilled ? Icons.star : Icons.star_outline,
            color: isFilled ? Colors.amber : Colors.white30,
            size: 28,
          ).animate(target: isFilled ? 1 : 0).scale(duration: 200.ms),
        );
      }).toList(),
    );
  }

  String _buildRatingsCtaLabel(Log? userLog) {
    if (userLog == null) {
      return 'Rate, log, review, add to list + more';
    }

    if (userLog.rating != null) {
      return "You've logged this film ${_formatStarsText(userLog.rating!)}";
    }

    return "You've logged this film";
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

// Diagonal clipper for backdrop gradient
class DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height * 0.7);
    path.quadraticBezierTo(
      size.width / 2,
      size.height * 0.85,
      size.width,
      size.height,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(DiagonalClipper oldClipper) => false;
}
