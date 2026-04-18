import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/providers/app_providers.dart';
import 'package:zinemo/services/tmdb_service.dart';
import 'package:zinemo/services/log_service.dart';
import 'package:zinemo/screens/tv_detail/episode_detail_screen.dart';
import 'package:zinemo/screens/watchlist/watchlist_screen.dart';
import 'package:zinemo/theme/app_theme.dart';

class TVSeasonDetailScreen extends ConsumerStatefulWidget {
  final int tmdbId;
  final int seasonNumber;
  final Content? show;

  const TVSeasonDetailScreen({
    required this.tmdbId,
    required this.seasonNumber,
    this.show,
    super.key,
  });

  @override
  ConsumerState<TVSeasonDetailScreen> createState() =>
      _TVSeasonDetailScreenState();
}

class _TVSeasonDetailScreenState extends ConsumerState<TVSeasonDetailScreen> {
  late Future<Map<String, dynamic>?> _seasonFuture;
  bool _isUpdatingProgress = false;

  @override
  void initState() {
    super.initState();
    _seasonFuture = TMDBService.getTVSeasonDetails(
      widget.tmdbId,
      widget.seasonNumber,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userLog = ref
        .watch(userMediaLogProvider((tmdbId: widget.tmdbId, mediaType: 'tv')))
        .asData
        ?.value;
    final showFromProvider = ref
        .watch(tvDetailProvider(widget.tmdbId))
        .asData
        ?.value;
    final show = widget.show ?? showFromProvider;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _seasonFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError || snapshot.data == null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Unable to load season details right now.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final seasonData = snapshot.data!;
            final episodes =
                (seasonData['episodes'] as List?)
                    ?.map((item) => Map<String, dynamic>.from(item as Map))
                    .toList() ??
                const <Map<String, dynamic>>[];

            episodes.sort(
              (a, b) => ((a['episode_number'] as num?)?.toInt() ?? 0).compareTo(
                (b['episode_number'] as num?)?.toInt() ?? 0,
              ),
            );

            final seasonRating =
                ((seasonData['vote_average'] as num?)?.toDouble() ?? 0.0).clamp(
                  0.0,
                  10.0,
                );
            final seasonOverview =
                (seasonData['overview'] as String?)?.trim() ?? '';
            final totalSeasons = math.max(
              1,
              show?.totalSeasons ?? widget.seasonNumber,
            );
            final totalEpisodes = math.max(
              episodes.length * totalSeasons,
              show?.totalEpisodes ?? episodes.length * totalSeasons,
            );
            final episodeRatings = _extractEpisodeRatings(
              userLog?.tags ?? const <String>[],
            );
            final watchedEpisodeCodes = {
              ..._extractWatchedEpisodeCodes(userLog?.tags ?? const <String>[]),
              ...episodeRatings.keys,
            };
            final watchedEpisodes = _resolveWatchedInSeason(
              userLog,
              show,
              episodes.length,
              widget.seasonNumber,
            );
            final watchedEpisodeNumbers = <int>{};
            for (final episode in episodes) {
              final episodeNumber =
                  ((episode['episode_number'] as num?)?.toInt() ?? 0).clamp(
                    0,
                    999,
                  );
              if (episodeNumber <= 0) {
                continue;
              }

              final code = _episodeCode(widget.seasonNumber, episodeNumber);
              if (episodeNumber <= watchedEpisodes ||
                  watchedEpisodeCodes.contains(code)) {
                watchedEpisodeNumbers.add(episodeNumber);
              }
            }

            final effectiveWatchedEpisodes = watchedEpisodeNumbers.length;
            final isSeasonComplete =
                episodes.isNotEmpty &&
                effectiveWatchedEpisodes >= episodes.length;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.pop(),
                        icon: const Icon(Icons.arrow_back, size: 30),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Season ${widget.seasonNumber}',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFF4A4A),
                            size: 20,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            seasonRating > 0
                                ? seasonRating.toStringAsFixed(1)
                                : '--',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _isUpdatingProgress
                            ? null
                            : () => _markSeasonAsWatched(
                                totalSeasons: totalSeasons,
                                totalEpisodes: totalEpisodes,
                                episodesInCurrentSeason: episodes.length,
                              ),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: isSeasonComplete
                                ? const Color(0xFFFF4A4A)
                                : Colors.transparent,
                            border: Border.all(
                              color: isSeasonComplete
                                  ? const Color(0xFFFF4A4A)
                                  : Colors.white.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child: isSeasonComplete
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.black,
                                  size: 18,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (seasonOverview.isNotEmpty)
                    Text(
                      seasonOverview,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        height: 1.3,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  if (seasonOverview.isNotEmpty) const SizedBox(height: 16),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.18),
                    height: 1,
                  ),
                  const SizedBox(height: 14),
                  ...episodes.map((episode) {
                    final episodeNumber =
                        ((episode['episode_number'] as num?)?.toInt() ?? 0)
                            .clamp(0, 999);
                    final episodeCode = _episodeCode(
                      widget.seasonNumber,
                      episodeNumber,
                    );
                    final isWatched =
                        episodeNumber > 0 &&
                        (episodeNumber <= watchedEpisodes ||
                            watchedEpisodeCodes.contains(episodeCode));
                    final userEpisodeRating = episodeRatings[episodeCode];
                    final rating =
                        ((episode['vote_average'] as num?)?.toDouble() ?? 0.0)
                            .clamp(0.0, 10.0);
                    final ratingLabel = userEpisodeRating != null
                        ? userEpisodeRating.toStringAsFixed(1)
                        : (rating > 0 ? rating.toStringAsFixed(1) : '--');
                    final title =
                        (episode['name'] as String?)?.trim().isNotEmpty == true
                        ? (episode['name'] as String)
                        : 'Untitled Episode';
                    final overview =
                        (episode['overview'] as String?)?.trim() ?? '';
                    final airDate = (episode['air_date'] as String?)?.trim();

                    final hasDate = airDate != null && airDate.isNotEmpty;
                    final dateLabel = hasDate
                        ? DateFormat('EEEE, dd MMM yyyy').format(
                            DateTime.tryParse(airDate)?.toLocal() ??
                                DateTime.now(),
                          )
                        : null;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openEpisodeDetail(
                          episode: episode,
                          show: show,
                          episodeNumber: episodeNumber,
                          fallbackTitle: title,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      hasDate &&
                                              episodeNumber == episodes.length
                                          ? 'Episode $episodeNumber | $dateLabel'
                                          : 'Episode $episodeNumber',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.white.withValues(
                                              alpha: 0.62,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            height: 1.1,
                                          ),
                                    ),
                                    if (overview.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          overview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Colors.white.withValues(
                                                  alpha: 0.68,
                                                ),
                                                height: 1.25,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                children: [
                                  GestureDetector(
                                    onTap:
                                        _isUpdatingProgress ||
                                            episodeNumber <= 0
                                        ? null
                                        : () => _showEpisodeRatingSheet(
                                            episodeNumber: episodeNumber,
                                            totalSeasons: totalSeasons,
                                            totalEpisodes: totalEpisodes,
                                            currentRating: userEpisodeRating,
                                          ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.star_rounded,
                                              color: userEpisodeRating != null
                                                  ? const Color(0xFFFF4A4A)
                                                  : Colors.white.withValues(
                                                      alpha: 0.78,
                                                    ),
                                              size: 20,
                                            ),
                                            Text(
                                              ratingLabel,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color: Colors.white
                                                        .withValues(alpha: 0.8),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          userEpisodeRating != null
                                              ? 'Your rating'
                                              : 'TMDB',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.white.withValues(
                                                  alpha: 0.55,
                                                ),
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  GestureDetector(
                                    onTap: _isUpdatingProgress
                                        ? null
                                        : () => _markEpisodeAsWatched(
                                            totalSeasons: totalSeasons,
                                            totalEpisodes: totalEpisodes,
                                            episodesInCurrentSeason:
                                                episodes.length,
                                            episodeNumber: episodeNumber,
                                          ),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(7),
                                        color: isWatched
                                            ? const Color(0xFFFF4A4A)
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isWatched
                                              ? const Color(0xFFFF4A4A)
                                              : Colors.white.withValues(
                                                  alpha: 0.38,
                                                ),
                                          width: 2,
                                        ),
                                      ),
                                      child: isWatched
                                          ? const Icon(
                                              Icons.check,
                                              color: Colors.black,
                                              size: 20,
                                            )
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _markEpisodeAsWatched({
    required int totalSeasons,
    required int totalEpisodes,
    required int episodesInCurrentSeason,
    required int episodeNumber,
  }) async {
    if (episodeNumber <= 0 || episodesInCurrentSeason <= 0) {
      return;
    }

    final progress = _progressForEpisode(
      season: widget.seasonNumber,
      episode: episodeNumber,
      totalSeasons: totalSeasons,
      totalEpisodes: totalEpisodes,
    );

    await _updateProgress(
      season: widget.seasonNumber,
      episode: episodeNumber,
      progress: progress,
      totalEpisodes: totalEpisodes,
      successMessage:
          'Episode S${widget.seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')} marked watched',
    );
  }

  Future<void> _showEpisodeRatingSheet({
    required int episodeNumber,
    required int totalSeasons,
    required int totalEpisodes,
    double? currentRating,
  }) async {
    if (_isUpdatingProgress || episodeNumber <= 0) {
      return;
    }

    var draftRating = (currentRating ?? 3.0).clamp(0.5, 5.0);
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF111118),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rate Episode $episodeNumber',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        color: Color(0xFFFF4A4A),
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        draftRating.toStringAsFixed(1),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ 5',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    min: 0.5,
                    max: 5.0,
                    divisions: 9,
                    value: draftRating,
                    activeColor: const Color(0xFFFF4A4A),
                    inactiveColor: Colors.white.withValues(alpha: 0.2),
                    onChanged: (value) {
                      setModalState(() {
                        draftRating = (value * 2).round() / 2;
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => Navigator.of(ctx).pop(draftRating),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4A4A),
                          foregroundColor: Colors.black,
                        ),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (selected == null) {
      return;
    }

    await _setEpisodeRating(
      episodeNumber: episodeNumber,
      rating: selected,
      totalSeasons: totalSeasons,
      totalEpisodes: totalEpisodes,
    );
  }

  Future<void> _setEpisodeRating({
    required int episodeNumber,
    required double rating,
    required int totalSeasons,
    required int totalEpisodes,
  }) async {
    if (_isUpdatingProgress || episodeNumber <= 0) {
      return;
    }

    final progress = _progressForEpisode(
      season: widget.seasonNumber,
      episode: episodeNumber,
      totalSeasons: totalSeasons,
      totalEpisodes: totalEpisodes,
    );

    setState(() => _isUpdatingProgress = true);
    try {
      await LogService.setTVEpisodeRating(
        tmdbId: widget.tmdbId,
        season: widget.seasonNumber,
        episode: episodeNumber,
        rating: rating,
        progress: progress,
        totalEpisodes: totalEpisodes,
      );

      ref.invalidate(userLogProvider(widget.tmdbId));
      ref.invalidate(
        userMediaLogProvider((tmdbId: widget.tmdbId, mediaType: 'tv')),
      );
      ref.invalidate(contentRatingsProvider);
      ref.invalidate(episodeRatingsProvider);
      ref.invalidate(tvDetailProvider(widget.tmdbId));
      ref.invalidate(watchHistoryProvider);
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(watchlistProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved rating ${rating.toStringAsFixed(1)} for S${widget.seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save episode rating: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingProgress = false);
      }
    }
  }

  Future<void> _markSeasonAsWatched({
    required int totalSeasons,
    required int totalEpisodes,
    required int episodesInCurrentSeason,
  }) async {
    if (episodesInCurrentSeason <= 0) {
      return;
    }

    var episodesBefore = 0;
    for (var season = 1; season < widget.seasonNumber; season++) {
      episodesBefore += _episodesInSeason(
        seasonNumber: season,
        totalSeasons: totalSeasons,
        totalEpisodes: totalEpisodes,
      );
    }

    final progress = (episodesBefore + episodesInCurrentSeason).clamp(
      1,
      totalEpisodes,
    );

    await _updateProgress(
      season: widget.seasonNumber,
      episode: episodesInCurrentSeason,
      progress: progress,
      totalEpisodes: totalEpisodes,
      setWatchedDate: true,
      episodesInSeasonForSeasonMark: episodesInCurrentSeason,
      successMessage: 'Season ${widget.seasonNumber} marked watched',
    );
  }

  Future<void> _updateProgress({
    required int season,
    required int episode,
    required int progress,
    required int totalEpisodes,
    bool setWatchedDate = false,
    int? episodesInSeasonForSeasonMark,
    required String successMessage,
  }) async {
    if (_isUpdatingProgress) {
      return;
    }

    setState(() => _isUpdatingProgress = true);
    try {
      await LogService.markTVProgress(
        tmdbId: widget.tmdbId,
        season: season,
        episode: episode,
        progress: progress,
        totalEpisodes: totalEpisodes,
        setWatchedDate: setWatchedDate,
        episodesInSeasonForSeasonMark: episodesInSeasonForSeasonMark,
      );

      ref.invalidate(userLogProvider(widget.tmdbId));
      ref.invalidate(
        userMediaLogProvider((tmdbId: widget.tmdbId, mediaType: 'tv')),
      );
      ref.invalidate(contentRatingsProvider);
      ref.invalidate(episodeRatingsProvider);
      ref.invalidate(tvDetailProvider(widget.tmdbId));
      ref.invalidate(watchHistoryProvider);
      ref.invalidate(continueWatchingProvider);
      ref.invalidate(watchlistProvider);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update progress: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdatingProgress = false);
      }
    }
  }

  void _openEpisodeDetail({
    required Map<String, dynamic> episode,
    required Content? show,
    required int episodeNumber,
    required String fallbackTitle,
  }) {
    final episodeTitle = (episode['name'] as String?)?.trim().isNotEmpty == true
        ? (episode['name'] as String).trim()
        : fallbackTitle;
    final formattedEpisode =
        'S${widget.seasonNumber.toString().padLeft(2, '0')}E${episodeNumber.toString().padLeft(2, '0')}';
    final compositeTitle =
        '${show?.title ?? 'TV Show'} · $formattedEpisode · $episodeTitle';
    final episodeAirDate = DateTime.tryParse(
      (episode['air_date'] as String?)?.trim() ?? '',
    );
    final directorName = _episodeDirectorLabel(episode);

    final episodeContent = Content(
      tmdbId: widget.tmdbId,
      mediaType: 'tv',
      title: compositeTitle,
      overview: (episode['overview'] as String?)?.trim() ?? show?.overview,
      posterPath: show?.posterPath,
      backdropPath: show?.backdropPath,
      releaseDate: episodeAirDate,
      runtime: (episode['runtime'] as num?)?.toInt() ?? show?.runtime,
      totalSeasons: show?.totalSeasons,
      totalEpisodes: show?.totalEpisodes,
      voteAverage:
          (episode['vote_average'] as num?)?.toDouble() ?? show?.voteAverage,
      voteCount: (episode['vote_count'] as num?)?.toInt() ?? show?.voteCount,
      trailerUrls: show?.trailerUrls,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EpisodeDetailScreen(
          episode: episodeContent,
          directorName: directorName,
        ),
      ),
    );
  }

  String? _episodeDirectorLabel(Map<String, dynamic> episode) {
    final crew = episode['crew'];
    if (crew is! List) {
      return null;
    }

    final names = crew
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .where((member) {
          final job = (member['job'] ?? '').toString().toLowerCase();
          final department = (member['department'] ?? '')
              .toString()
              .toLowerCase();
          return job == 'director' || department == 'directing';
        })
        .map((member) => (member['name'] ?? '').toString().trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    if (names.isEmpty) {
      return null;
    }

    return names.take(2).join(', ');
  }

  int _resolveWatchedInSeason(
    Log? userLog,
    Content? show,
    int episodesInCurrentSeason,
    int selectedSeason,
  ) {
    if (episodesInCurrentSeason <= 0 || userLog == null) {
      return 0;
    }

    final seasonPrefix = 'S${selectedSeason.toString().padLeft(2, '0')}';
    final watchedByExplicitTags = {
      ..._extractWatchedEpisodeCodes(
        userLog.tags,
      ).where((code) => code.startsWith(seasonPrefix)),
      ..._extractEpisodeRatings(
        userLog.tags,
      ).keys.where((code) => code.startsWith(seasonPrefix)),
    }.length.clamp(0, episodesInCurrentSeason);

    if (userLog.status == LogStatus.watched) {
      return episodesInCurrentSeason;
    }

    if (userLog.status != LogStatus.watching) {
      return watchedByExplicitTags;
    }

    final progressTag = _extractTagInt(userLog.tags, 'progress');
    if (progressTag != null && show != null) {
      final totalSeasons = math.max(1, show.totalSeasons ?? selectedSeason);
      final totalEpisodes = math.max(
        episodesInCurrentSeason * totalSeasons,
        show.totalEpisodes ?? episodesInCurrentSeason * totalSeasons,
      );

      var episodesBefore = 0;
      for (var season = 1; season < selectedSeason; season++) {
        episodesBefore += _episodesInSeason(
          seasonNumber: season,
          totalSeasons: totalSeasons,
          totalEpisodes: totalEpisodes,
        );
      }

      final watchedFromProgress = (progressTag - episodesBefore).clamp(
        0,
        episodesInCurrentSeason,
      );
      return math.max(watchedFromProgress, watchedByExplicitTags);
    }

    final parsed = _extractSeasonEpisode(userLog.tags);
    if (selectedSeason < parsed.season) {
      return episodesInCurrentSeason;
    }

    if (selectedSeason > parsed.season) {
      return watchedByExplicitTags;
    }

    final watchedFromPosition = parsed.episode.clamp(
      0,
      episodesInCurrentSeason,
    );
    return math.max(watchedFromPosition, watchedByExplicitTags);
  }

  int _progressForEpisode({
    required int season,
    required int episode,
    required int totalSeasons,
    required int totalEpisodes,
  }) {
    var episodesBefore = 0;
    for (var currentSeason = 1; currentSeason < season; currentSeason++) {
      episodesBefore += _episodesInSeason(
        seasonNumber: currentSeason,
        totalSeasons: totalSeasons,
        totalEpisodes: totalEpisodes,
      );
    }

    return (episodesBefore + episode).clamp(1, totalEpisodes);
  }

  String _episodeCode(int season, int episode) {
    return 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
  }

  Set<String> _extractWatchedEpisodeCodes(List<String> tags) {
    final codes = <String>{};
    for (final tag in tags) {
      if (!tag.startsWith('ep_watched:')) {
        continue;
      }

      final code = tag.substring('ep_watched:'.length).trim().toUpperCase();
      if (RegExp(r'^S\d{2}E\d{2}$').hasMatch(code)) {
        codes.add(code);
      }
    }

    return codes;
  }

  Map<String, double> _extractEpisodeRatings(List<String> tags) {
    final ratings = <String, double>{};
    for (final tag in tags) {
      if (!tag.startsWith('ep_rating:')) {
        continue;
      }

      final parts = tag.split(':');
      if (parts.length < 3) {
        continue;
      }

      final code = parts[1].trim().toUpperCase();
      final rating = double.tryParse(parts[2]);
      if (rating == null || !RegExp(r'^S\d{2}E\d{2}$').hasMatch(code)) {
        continue;
      }

      ratings[code] = rating.clamp(0.5, 5.0);
    }

    return ratings;
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
}
