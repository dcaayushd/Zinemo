import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/providers/app_providers.dart';
import 'package:zinemo/screens/watchlist/watchlist_screen.dart';
import 'package:zinemo/theme/app_theme.dart';
import 'package:zinemo/widgets/content_actions_sheet.dart';
import 'package:zinemo/widgets/detail_ratings_section.dart' as ratings_section;

class EpisodeDetailScreen extends ConsumerWidget {
  final Content episode;
  final String? directorName;

  const EpisodeDetailScreen({
    required this.episode,
    this.directorName,
    super.key,
  });

  bool get _hasRuntime => (episode.runtime ?? 0) > 0;

  String? get _episodeCode {
    final match = RegExp(
      r'\bS(\d{1,2})E(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(episode.title);
    if (match == null) {
      return null;
    }

    final season = int.tryParse(match.group(1) ?? '');
    final episodeNumber = int.tryParse(match.group(2) ?? '');
    if (season == null || episodeNumber == null) {
      return null;
    }

    return 'S${season.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
  }

  String get _releaseLabel {
    final releaseDate = episode.releaseDate;
    if (releaseDate == null) {
      return 'Unknown release date';
    }

    return DateFormat('dd MMM yyyy').format(releaseDate);
  }

  void _openContentActions(BuildContext context, WidgetRef ref) {
    final episodeCode = _episodeCode;

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
              content: episode,
              dialogMode: true,
              onDismiss: () => Navigator.of(ctx).pop(),
              onActionCompleted: () {
                ref.invalidate(watchlistProvider);
                ref.invalidate(continueWatchingProvider);
                ref.invalidate(watchHistoryProvider);
                ref.invalidate(contentRatingsProvider);
                ref.invalidate(episodeRatingsProvider);
                ref.invalidate(userLogProvider(episode.tmdbId));
                ref.invalidate(
                  userMediaLogProvider((
                    tmdbId: episode.tmdbId,
                    mediaType: 'tv',
                  )),
                );
                if (episodeCode != null) {
                  ref.invalidate(
                    episodeRatingsProvider((
                      tmdbId: episode.tmdbId,
                      episodeCode: episodeCode,
                      fallbackVoteAverage: episode.voteAverage ?? 0.0,
                      fallbackVoteCount: episode.voteCount ?? 0,
                    )),
                  );
                }
                ref.invalidate(tvDetailProvider(episode.tmdbId));
              },
            ),
          ),
        ),
      ),
    );
  }

  void _openTrailer(BuildContext context) {
    final trailers = episode.trailerUrls;
    if (trailers == null || trailers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trailer not available yet')),
      );
      return;
    }

    final youtubeId = YoutubePlayer.convertUrlToId(trailers.first);
    if (youtubeId == null || youtubeId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid trailer URL')));
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
  Widget build(BuildContext context, WidgetRef ref) {
    final episodeCode = _episodeCode;
    final episodeRatingsSnapshot = episodeCode == null
        ? null
        : ref
              .watch(
                episodeRatingsProvider((
                  tmdbId: episode.tmdbId,
                  episodeCode: episodeCode,
                  fallbackVoteAverage: episode.voteAverage ?? 0.0,
                  fallbackVoteCount: episode.voteCount ?? 0,
                )),
              )
              .asData
              ?.value;

    final effectiveVoteAverage =
        ((episodeRatingsSnapshot?.averageStars ??
                    ((episode.voteAverage ?? 0.0) / 2)) *
                2)
            .clamp(0.0, 10.0);
    final effectiveVoteCount =
        episodeRatingsSnapshot?.totalRatings ?? (episode.voteCount ?? 0);

    final userAvatar = Supabase
        .instance
        .client
        .auth
        .currentUser
        ?.userMetadata?['avatar_url']
        ?.toString();

    final hasDirector = directorName != null && directorName!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: CachedNetworkImage(
                    imageUrl: episode.backdropUrl,
                    fit: BoxFit.cover,
                    errorWidget: (ctx, url, err) =>
                        Container(color: Colors.black),
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
                      onTap: () => Navigator.of(context).pop(),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _openContentActions(context, ref),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: episode.posterUrl,
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
                          episode.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
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
                            'Episode',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppTheme.primary),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          hasDirector
                              ? '$_releaseLabel · DIRECTED BY'
                              : _releaseLabel,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.62),
                                letterSpacing: 1.4,
                              ),
                        ),
                        if (hasDirector) ...[
                          const SizedBox(height: 4),
                          Text(
                            directorName!,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => _openTrailer(context),
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
                      if (_hasRuntime) ...[
                        const SizedBox(width: 14),
                        Text(
                          '${episode.runtime} mins',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
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
                    episode.overview ?? 'No description available',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            ratings_section.DetailRatingsSection(
              voteAverage: effectiveVoteAverage,
              voteCount: effectiveVoteCount,
              distribution: episodeRatingsSnapshot?.distribution,
              distributionCounts: episodeRatingsSnapshot?.distributionCounts,
              ctaLabel: 'Rate, log, review, add to list + more',
              avatarUrl: userAvatar,
              onCtaTap: () => _openContentActions(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
