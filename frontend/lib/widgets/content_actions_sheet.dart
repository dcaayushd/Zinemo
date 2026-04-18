import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/models/content.dart';
import 'package:zinemo/services/log_service.dart';
import 'package:zinemo/theme/app_theme.dart';

class ContentActionsSheet extends StatefulWidget {
  final Content content;
  final VoidCallback onDismiss;
  final VoidCallback? onActionCompleted;
  final bool dialogMode;

  const ContentActionsSheet({
    required this.content,
    required this.onDismiss,
    this.onActionCompleted,
    this.dialogMode = false,
    super.key,
  });

  @override
  State<ContentActionsSheet> createState() => _ContentActionsSheetState();
}

class _ContentActionsSheetState extends State<ContentActionsSheet> {
  bool _isLoading = false;
  bool _isInitializing = true;
  bool _isLogged = false;
  bool _isLiked = false;
  bool _isWatchlist = false;
  double _selectedRating = 0.0;

  @override
  void initState() {
    super.initState();
    _loadExistingLogState();
  }

  bool get _isEpisodeContext =>
      widget.content.mediaType == 'tv' &&
      RegExp(r'\bS\d{1,2}E\d{1,2}\b').hasMatch(widget.content.title);

  bool get _shouldShowRuntime =>
      (widget.content.runtime ?? 0) > 0 &&
      (widget.content.mediaType == 'movie' || _isEpisodeContext);

  String get _loggedStatus => _isEpisodeContext ? 'watching' : 'watched';

  String get _watchedLabel =>
      (_isLogged && _selectedRating > 0) ? 'Logged' : 'Watched';

  String _metaSubtitle() {
    final year = widget.content.releaseDate?.year;
    return year?.toString() ?? '';
  }

  ({int season, int episode})? _episodeMarkerFromTitle() {
    final match = RegExp(
      r'\bS(\d{1,2})E(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(widget.content.title);

    if (match == null) {
      return null;
    }

    final season = int.tryParse(match.group(1) ?? '');
    final episode = int.tryParse(match.group(2) ?? '');

    if (season == null || episode == null || season <= 0 || episode <= 0) {
      return null;
    }

    return (season: season, episode: episode);
  }

  ({int season, int episode, int progress, int totalEpisodes})?
  _episodeProgressPayload() {
    final marker = _episodeMarkerFromTitle();
    if (marker == null) {
      return null;
    }

    final totalSeasons = widget.content.totalSeasons;
    final totalEpisodes = widget.content.totalEpisodes;
    final hasBounds =
        totalSeasons != null &&
        totalSeasons > 0 &&
        totalEpisodes != null &&
        totalEpisodes > 0;

    final episodesPerSeason = hasBounds
        ? math.max(1, (totalEpisodes / totalSeasons).ceil())
        : math.max(1, marker.episode);

    final rawProgress =
        ((marker.season - 1) * episodesPerSeason) + marker.episode;
    final resolvedTotalEpisodes = hasBounds ? totalEpisodes : rawProgress;
    final progress = hasBounds
        ? rawProgress.clamp(1, resolvedTotalEpisodes)
        : rawProgress;

    return (
      season: marker.season,
      episode: marker.episode,
      progress: progress,
      totalEpisodes: resolvedTotalEpisodes,
    );
  }

  List<String>? _episodeProgressTags() {
    final payload = _episodeProgressPayload();
    if (!_isEpisodeContext || payload == null) {
      return null;
    }

    return [
      'S${payload.season.toString().padLeft(2, '0')}E${payload.episode.toString().padLeft(2, '0')}',
      'season:${payload.season}',
      'episode:${payload.episode}',
      'progress:${payload.progress}',
    ];
  }

  double? _episodeRatingFromTags(List<String> tags) {
    final payload = _episodeProgressPayload();
    if (payload == null) {
      return null;
    }

    final code =
        'S${payload.season.toString().padLeft(2, '0')}E${payload.episode.toString().padLeft(2, '0')}';
    final prefix = 'ep_rating:$code:';
    for (final tag in tags) {
      if (!tag.startsWith(prefix)) {
        continue;
      }

      final rating = double.tryParse(tag.substring(prefix.length));
      if (rating != null) {
        return rating.clamp(0.5, 5.0);
      }
    }

    return null;
  }

  double? _episodeRatingFromRows(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final tags =
          ((row['tags'] as List?)?.map((entry) => entry.toString()).toList() ??
                  <String>[])
              .toList();
      final parsed = _episodeRatingFromTags(tags);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  Future<void> _loadExistingLogState() async {
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        return;
      }

      final response = await supabase
          .from('logs')
          .select('status, liked, rating, tags')
          .eq('user_id', user.id)
          .eq('tmdb_id', widget.content.tmdbId)
          .eq('media_type', widget.content.mediaType)
          .order('updated_at', ascending: false)
          .limit(25);

      final rows = response as List?;
      if (rows == null || rows.isEmpty || !mounted) {
        return;
      }

      final typedRows = rows
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      final row = typedRows.first;
      final status = (row['status'] as String?) ?? '';
      final tags =
          ((row['tags'] as List?)?.map((entry) => entry.toString()).toList() ??
                  <String>[])
              .toList();
      final rowRating = (row['rating'] as num?)?.toDouble() ?? 0.0;
      final episodeRating = _isEpisodeContext
          ? (_episodeRatingFromRows(typedRows) ?? _episodeRatingFromTags(tags))
          : null;
      final ratingValue = (episodeRating ?? rowRating).clamp(0.0, 5.0);

      setState(() {
        _isWatchlist = status == 'watchlist';
        _isLogged = status == 'watched' || status == 'watching';
        _isLiked = row['liked'] == true;
        _selectedRating = ratingValue.clamp(0.0, 5.0);
      });
    } catch (_) {
      // Non-blocking: sheet still works even if prefill fetch fails.
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _performAction(Future<void> Function() action) async {
    if (_isLoading) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      await action();
      widget.onActionCompleted?.call();
    } catch (e) {
      _showSnackbar('Error: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleLogged() async {
    final episodeTags = _episodeProgressTags();
    final episodePayload = _episodeProgressPayload();

    await _performAction(() async {
      if (_isLogged) {
        await LogService.addToWatchlist(
          widget.content.tmdbId,
          widget.content.mediaType,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _isLogged = false;
          _isWatchlist = true;
        });
        _showSnackbar('Moved to watchlist');
        return;
      }

      if (_isEpisodeContext && episodePayload != null) {
        if (_selectedRating > 0) {
          await LogService.setTVEpisodeRating(
            tmdbId: widget.content.tmdbId,
            season: episodePayload.season,
            episode: episodePayload.episode,
            rating: _selectedRating,
            progress: episodePayload.progress,
            totalEpisodes: episodePayload.totalEpisodes,
          );
        } else {
          await LogService.markTVProgress(
            tmdbId: widget.content.tmdbId,
            season: episodePayload.season,
            episode: episodePayload.episode,
            progress: episodePayload.progress,
            totalEpisodes: episodePayload.totalEpisodes,
          );
        }

        if (!mounted) {
          return;
        }
        setState(() {
          _isLogged = true;
          _isWatchlist = false;
        });
        _showSnackbar('Episode logged');
        return;
      }

      await LogService.quickLog(
        tmdbId: widget.content.tmdbId,
        mediaType: widget.content.mediaType,
        status: _loggedStatus,
        rating: _selectedRating > 0 ? _selectedRating : null,
        tags: episodeTags,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _isLogged = true;
        _isWatchlist = false;
      });
      _showSnackbar(_isEpisodeContext ? 'Episode logged' : 'Marked as watched');
    });
  }

  Future<void> _toggleLike() async {
    final next = !_isLiked;
    final episodeTags = _episodeProgressTags();

    await _performAction(() async {
      final status = _isWatchlist ? 'watchlist' : _loggedStatus;
      await LogService.quickLog(
        tmdbId: widget.content.tmdbId,
        mediaType: widget.content.mediaType,
        status: status,
        rating: _selectedRating > 0 ? _selectedRating : null,
        liked: next,
        tags: _isEpisodeContext ? null : episodeTags,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _isLiked = next;
        _isLogged = !_isWatchlist;
      });
      _showSnackbar(next ? 'Liked' : 'Removed like');
    });
  }

  Future<void> _toggleWatchlist() async {
    final episodeTags = _episodeProgressTags();
    final episodePayload = _episodeProgressPayload();

    await _performAction(() async {
      if (_isWatchlist) {
        if (_isEpisodeContext && episodePayload != null) {
          if (_selectedRating > 0) {
            await LogService.setTVEpisodeRating(
              tmdbId: widget.content.tmdbId,
              season: episodePayload.season,
              episode: episodePayload.episode,
              rating: _selectedRating,
              progress: episodePayload.progress,
              totalEpisodes: episodePayload.totalEpisodes,
            );
          } else {
            await LogService.markTVProgress(
              tmdbId: widget.content.tmdbId,
              season: episodePayload.season,
              episode: episodePayload.episode,
              progress: episodePayload.progress,
              totalEpisodes: episodePayload.totalEpisodes,
            );
          }

          if (!mounted) {
            return;
          }
          setState(() {
            _isWatchlist = false;
            _isLogged = true;
          });
          _showSnackbar('Episode logged');
          return;
        }

        await LogService.quickLog(
          tmdbId: widget.content.tmdbId,
          mediaType: widget.content.mediaType,
          status: _loggedStatus,
          rating: _selectedRating > 0 ? _selectedRating : null,
          tags: episodeTags,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _isWatchlist = false;
          _isLogged = true;
        });
        _showSnackbar(
          _isEpisodeContext ? 'Episode logged' : 'Moved to watched',
        );
        return;
      }

      await LogService.addToWatchlist(
        widget.content.tmdbId,
        widget.content.mediaType,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _isWatchlist = true;
        _isLogged = false;
      });
      _showSnackbar('Added to watchlist');
    });
  }

  Future<void> _setRating(double rating) async {
    final episodeTags = _episodeProgressTags();
    final episodePayload = _episodeProgressPayload();

    await _performAction(() async {
      if (_isEpisodeContext && episodePayload != null) {
        await LogService.setTVEpisodeRating(
          tmdbId: widget.content.tmdbId,
          season: episodePayload.season,
          episode: episodePayload.episode,
          rating: rating,
          progress: episodePayload.progress,
          totalEpisodes: episodePayload.totalEpisodes,
        );

        if (!mounted) {
          return;
        }
        setState(() {
          _selectedRating = rating;
          _isLogged = true;
          _isWatchlist = false;
        });
        _showSnackbar('Rated ${rating.toStringAsFixed(1)} and logged episode');
        return;
      }

      await LogService.quickLog(
        tmdbId: widget.content.tmdbId,
        mediaType: widget.content.mediaType,
        status: _loggedStatus,
        rating: rating,
        tags: episodeTags,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _selectedRating = rating;
        _isLogged = true;
        _isWatchlist = false;
      });
      _showSnackbar(
        _isEpisodeContext
            ? 'Rated ${rating.toStringAsFixed(1)} and logged episode'
            : 'Rated ${rating.toStringAsFixed(1)}',
      );
    });
  }

  void _showComingSoon(String label) {
    _showSnackbar('$label coming soon');
  }

  IconData _iconForStar(int index) {
    final star = index + 1.0;
    if (_selectedRating >= star) {
      return Icons.star_rounded;
    }
    if (_selectedRating >= (star - 0.5)) {
      return Icons.star_half_rounded;
    }
    return Icons.star_outline_rounded;
  }

  double _ratingFromTap({
    required int index,
    required double localDx,
    required double width,
  }) {
    final isLeftHalf = localDx <= (width / 2);
    final value = index + (isLeftHalf ? 0.5 : 1.0);
    return value.clamp(0.5, 5.0);
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _metaSubtitle();
    const sheetColor = AppTheme.background;

    return Container(
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: widget.dialogMode
            ? const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              )
            : const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: SafeArea(
        top: false,
        bottom: !widget.dialogMode,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 72,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (widget.dialogMode)
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      onPressed: widget.onDismiss,
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                const SizedBox(height: 22),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.content.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.46),
                                fontWeight: FontWeight.w400,
                              ),
                        ),
                      ],
                      if (_shouldShowRuntime) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${widget.content.runtime} mins',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.56),
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Divider(height: 1, color: Colors.black.withValues(alpha: 0.18)),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatusAction(
                        icon: Icons.remove_red_eye_outlined,
                        label: _watchedLabel,
                        active: _isLogged,
                        activeColor: AppTheme.success,
                        isLoading: _isLoading || _isInitializing,
                        onTap: _toggleLogged,
                      ),
                      _StatusAction(
                        icon: _isLiked
                            ? Icons.favorite
                            : Icons.favorite_border_rounded,
                        label: 'Like',
                        active: _isLiked,
                        activeColor: const Color(0xFFFF5D8F),
                        isLoading: _isLoading || _isInitializing,
                        onTap: _toggleLike,
                      ),
                      _StatusAction(
                        icon: Icons.watch_later_outlined,
                        label: 'Watchlist',
                        active: _isWatchlist,
                        activeColor: const Color(0xFFFFD54F),
                        isLoading: _isLoading || _isInitializing,
                        onTap: _toggleWatchlist,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: Colors.black.withValues(alpha: 0.18)),
                const SizedBox(height: 16),
                Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final rowWidth = math.min(constraints.maxWidth, 5 * 48.0);
                      return SizedBox(
                        width: rowWidth,
                        child: GestureDetector(
                          onHorizontalDragUpdate: _isLoading
                              ? null
                              : (details) {
                                  final dx = details.localPosition.dx.clamp(
                                    0.0,
                                    rowWidth,
                                  );
                                  final raw = (dx / rowWidth) * 5.0;
                                  final next = ((raw * 2).round() / 2).clamp(
                                    0.5,
                                    5.0,
                                  );
                                  if (next != _selectedRating) {
                                    setState(() => _selectedRating = next);
                                  }
                                },
                          onHorizontalDragEnd: _isLoading
                              ? null
                              : (_) {
                                  if (_selectedRating > 0) {
                                    _setRating(_selectedRating);
                                  }
                                },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(5, (index) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: _isLoading
                                    ? null
                                    : (details) {
                                        const starTapWidth = 48.0;
                                        final rating = _ratingFromTap(
                                          index: index,
                                          localDx: details.localPosition.dx,
                                          width: starTapWidth,
                                        );
                                        _setRating(rating);
                                      },
                                child: SizedBox(
                                  width: 48,
                                  height: 52,
                                  child: Icon(
                                    _iconForStar(index),
                                    size: 44,
                                    color: _selectedRating >= (index + 0.5)
                                        ? const Color(0xFFFFD54F)
                                        : const Color(0xFF2F4358),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: Colors.black.withValues(alpha: 0.18)),
                const SizedBox(height: 4),
                _MenuAction(
                  icon: Icons.show_chart_rounded,
                  label: 'Show your activity',
                  onTap: () => _showComingSoon('Show your activity'),
                ),
                _MenuAction(
                  icon: Icons.add,
                  label: 'Review or log again',
                  onTap: _toggleLogged,
                ),
                _MenuAction(
                  icon: Icons.playlist_add,
                  label: 'Add to lists',
                  onTap: () => _showComingSoon('Add to lists'),
                ),
                _MenuAction(
                  icon: Icons.share_outlined,
                  label: 'Share',
                  onTap: () => _showComingSoon('Share'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final bool isLoading;
  final Future<void> Function() onTap;

  const _StatusAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = active
        ? activeColor
        : Colors.white.withValues(alpha: 0.42);

    return GestureDetector(
      onTap: isLoading ? null : () => onTap(),
      child: SizedBox(
        width: 88,
        child: Column(
          children: [
            Icon(icon, size: 46, color: iconColor),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white.withValues(alpha: active ? 0.86 : 0.62),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 26, color: Colors.white.withValues(alpha: 0.45)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
