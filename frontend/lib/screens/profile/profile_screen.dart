import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/providers/app_providers.dart';
import 'package:zinemo/services/tmdb_service.dart';
import 'package:zinemo/theme/app_theme.dart';
import 'package:zinemo/widgets/detail_ratings_section.dart' as ratings_section;

enum _ProfileTopTab { profile, diary, lists, watchlist }

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  _ProfileTopTab _selectedTab = _ProfileTopTab.profile;
  final Map<String, Future<Content?>> _contentFutures = {};

  Future<Content?> _contentForLog(Log log) {
    final key = '${log.mediaType}:${log.tmdbId}';
    return _contentFutures.putIfAbsent(
      key,
      () => TMDBService.getDetails(log.tmdbId, log.mediaType),
    );
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      context.go('/auth');
    }
  }

  void _openContentDetails(Content content) {
    final routeName = content.mediaType == 'tv' ? 'tv-detail' : 'movie-detail';
    context.pushNamed(
      routeName,
      pathParameters: {'tmdbId': content.tmdbId.toString()},
      extra: content,
    );
  }

  void _goToSearch() {
    context.go('/search');
  }

  bool _isPinned(Log log) {
    for (final tag in log.tags) {
      final normalized = tag.toLowerCase().trim();
      if (normalized == 'pin' ||
          normalized == 'pinned' ||
          normalized.startsWith('pin:')) {
        return true;
      }
    }
    return false;
  }

  List<Log> _uniqueByContent(List<Log> logs, {int limit = 9999}) {
    final seen = <String>{};
    final unique = <Log>[];

    for (final log in logs) {
      final key = '${log.mediaType}:${log.tmdbId}';
      if (!seen.add(key)) {
        continue;
      }
      unique.add(log);
      if (unique.length >= limit) {
        break;
      }
    }

    return unique;
  }

  List<Log> _favoriteLogs(List<Log> logs) {
    final favorites = logs.where((log) => log.liked || _isPinned(log)).toList();
    favorites.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _uniqueByContent(favorites, limit: 12);
  }

  List<Log> _recentActivityLogs(List<Log> logs) {
    final active = logs
        .where(
          (log) =>
              log.status == LogStatus.watched ||
              log.status == LogStatus.watching ||
              log.rating != null ||
              (log.review?.trim().isNotEmpty ?? false),
        )
        .toList();

    active.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return _uniqueByContent(active, limit: 12);
  }

  List<double> _allRatingValues(List<Log> logs) {
    final values = <double>[];

    for (final log in logs) {
      if (log.rating != null) {
        values.add(log.rating!.clamp(0.5, 5.0));
      }

      for (final tag in log.tags) {
        if (!tag.startsWith('ep_rating:')) {
          continue;
        }

        final parts = tag.split(':');
        if (parts.length < 3) {
          continue;
        }

        final rating = double.tryParse(parts[2]);
        if (rating != null) {
          values.add(rating.clamp(0.5, 5.0));
        }
      }
    }

    return values;
  }

  ({List<double> distribution, List<int> counts}) _buildRatingsDistribution(
    List<double> ratingValues,
  ) {
    const bins = 9;
    final counts = List<int>.filled(bins, 0);

    for (final raw in ratingValues) {
      final stars = raw.clamp(0.5, 5.0);
      final normalized = ((stars < 1.0 ? 1.0 : stars) - 1.0) / 0.5;
      final index = normalized.round().clamp(0, bins - 1);
      counts[index] += 1;
    }

    final maxCount = counts.fold<int>(
      0,
      (prev, value) => math.max(prev, value),
    );
    if (maxCount == 0) {
      return (distribution: List<double>.filled(bins, 0), counts: counts);
    }

    final distribution = counts
        .map((count) => count / maxCount)
        .toList(growable: false);

    return (distribution: distribution, counts: counts);
  }

  Widget _sectionDivider() {
    return Container(height: 1, color: Colors.white.withValues(alpha: 0.12));
  }

  Widget _buildRatingStars(double rating, {double iconSize = 12}) {
    final clamped = rating.clamp(0.0, 5.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final value = index + 1.0;
        final icon = clamped >= value
            ? Icons.star_rounded
            : (clamped >= value - 0.5
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded);

        return Icon(icon, size: iconSize, color: AppTheme.success);
      }),
    );
  }

  Widget _buildLogRatingRow(Log log) {
    final hasReview = (log.review?.trim().isNotEmpty ?? false);
    if (log.rating == null && !hasReview) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (log.rating != null) _buildRatingStars(log.rating!, iconSize: 11.5),
        if (hasReview) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.notes_rounded,
            size: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ],
      ],
    );
  }

  Widget _buildTopHeader(BuildContext context, UserProfile? user) {
    final name = user?.displayName ?? user?.username ?? 'Your Profile';

    return Container(
      color: Colors.black,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.settings, size: 32, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    onPressed: _logout,
                    tooltip: 'Logout',
                    icon: const Icon(Icons.logout_rounded, size: 24),
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              child: Row(
                children: _ProfileTopTab.values.map((tab) {
                  final isSelected = _selectedTab == tab;
                  final label = switch (tab) {
                    _ProfileTopTab.profile => 'Profile',
                    _ProfileTopTab.diary => 'Diary',
                    _ProfileTopTab.lists => 'Lists',
                    _ProfileTopTab.watchlist => 'Watchlist',
                  };

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTab = tab),
                      child: Container(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                maxLines: 1,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white.withValues(
                                              alpha: 0.62,
                                            ),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              height: 4,
                              width: isSelected ? 56 : 0,
                              decoration: BoxDecoration(
                                color: AppTheme.success,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHero(
    BuildContext context,
    UserProfile? user,
    List<Log> logs,
  ) {
    final location = user?.preferences.languages.isNotEmpty == true
        ? user!.preferences.languages.first.toUpperCase()
        : 'Location not set';
    final handle = '@${user?.username ?? 'user'}';
    final bio = (user?.bio?.trim().isNotEmpty ?? false)
        ? user!.bio!.trim()
        : 'Cinephile';

    final loggedCount = logs.length;
    final watchedCount = logs
        .where((log) => log.status == LogStatus.watched)
        .length;
    final ratedCount = logs.where((log) => log.rating != null).length;

    return Container(
      color: AppTheme.background,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: AppTheme.card,
            backgroundImage:
                (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty)
                ? CachedNetworkImageProvider(user.avatarUrl!)
                : null,
            child: (user?.avatarUrl == null || user!.avatarUrl!.isEmpty)
                ? const Icon(Icons.person, size: 52, color: Colors.white70)
                : null,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_on,
                size: 16,
                color: Colors.white.withValues(alpha: 0.48),
              ),
              const SizedBox(width: 4),
              Text(
                location,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'X',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                handle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            bio,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$loggedCount logged  •  $watchedCount watched  •  $ratedCount rated',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.72),
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyAddCard({
    required BuildContext context,
    required String message,
    required String buttonLabel,
    required VoidCallback onAdd,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                minimumSize: const Size(0, 34),
              ),
              child: Text(
                buttonLabel,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterTile(
    BuildContext context,
    Log log, {
    bool showRating = false,
    double tileWidth = 104,
    double posterHeight = 152,
  }) {
    return FutureBuilder<Content?>(
      future: _contentForLog(log),
      builder: (context, snapshot) {
        final content = snapshot.data;

        return GestureDetector(
          onTap: content == null ? null : () => _openContentDetails(content),
          child: SizedBox(
            width: tileWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: tileWidth,
                    height: posterHeight,
                    color: AppTheme.card,
                    child: content == null
                        ? Icon(
                            Icons.local_movies,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 20,
                          )
                        : CachedNetworkImage(
                            imageUrl: content.posterUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Icon(
                              Icons.local_movies,
                              color: Colors.white.withValues(alpha: 0.3),
                              size: 20,
                            ),
                          ),
                  ),
                ),
                if (showRating) ...[
                  const SizedBox(height: 5),
                  _buildLogRatingRow(log),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddPosterCard({
    required BuildContext context,
    String label = 'Add',
    double tileWidth = 104,
    double posterHeight = 152,
  }) {
    return GestureDetector(
      onTap: _goToSearch,
      child: SizedBox(
        width: tileWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: tileWidth,
              height: posterHeight,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Icon(
                Icons.add,
                size: 42,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesSection(BuildContext context, List<Log> logs) {
    final favorites = _favoriteLogs(logs).take(4).toList();

    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          if (index < favorites.length) {
            return _buildPosterTile(context, favorites[index]);
          }
          return _buildAddPosterCard(context: context, label: 'Favorite');
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: 4,
      ),
    );
  }

  Widget _buildRecentActivitySection(BuildContext context, List<Log> logs) {
    final recent = _recentActivityLogs(logs);

    if (recent.isEmpty) {
      return _buildEmptyAddCard(
        context: context,
        message:
            'No recent activity yet. Start logging to populate this section.',
        buttonLabel: 'Add',
        onAdd: _goToSearch,
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 172,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) =>
                _buildPosterTile(context, recent[index], showRating: true),
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemCount: recent.length,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Newest items appear first',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingsSection(BuildContext context, List<Log> logs) {
    final ratingValues = _allRatingValues(logs);

    if (ratingValues.isEmpty) {
      return _buildEmptyAddCard(
        context: context,
        message: 'No ratings yet. Rate movies/shows from detail screens.',
        buttonLabel: 'Add',
        onAdd: _goToSearch,
      );
    }

    final averageStars =
        ratingValues.reduce((a, b) => a + b) / ratingValues.length;
    final distribution = _buildRatingsDistribution(ratingValues);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ratings_section.DetailRatingsSection(
          voteAverage: averageStars * 2,
          voteCount: ratingValues.length,
          distribution: distribution.distribution,
          distributionCounts: distribution.counts,
          ctaLabel: 'Your ratings',
          avatarUrl: null,
          onCtaTap: null,
        ),
      ],
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required String label,
    required int valueCount,
    required String valueText,
    bool showAddWhenEmpty = true,
    VoidCallback? onAddTap,
    VoidCallback? onTap,
  }) {
    final canAdd = showAddWhenEmpty && valueCount == 0 && onAddTap != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.88),
              ),
            ),
          ),
          Text(
            valueText,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (canAdd) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onAddTap,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 30),
              ),
              child: const Text('Add'),
            ),
          ],
          if (onTap != null)
            IconButton(
              onPressed: onTap,
              icon: Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummarySection(BuildContext context, List<Log> logs) {
    final now = DateTime.now();
    final yearLogs = logs
        .where((log) => log.updatedAt.year == now.year)
        .toList();

    final filmsWatchedThisYear = yearLogs
        .where(
          (log) => log.mediaType == 'movie' && log.status == LogStatus.watched,
        )
        .length;
    final tvWatchedThisYear = yearLogs
        .where(
          (log) => log.mediaType == 'tv' && log.status == LogStatus.watched,
        )
        .length;
    final reviewsCount = yearLogs
        .where((log) => (log.review?.trim().isNotEmpty ?? false))
        .length;
    final watchlistCount = yearLogs
        .where(
          (log) =>
              log.status == LogStatus.watchlist ||
              log.status == LogStatus.planToWatch,
        )
        .length;
    final likesCount = yearLogs.where((log) => log.liked).length;
    final ratedCount = yearLogs.where((log) => log.rating != null).length;
    final holdsCount = yearLogs
        .where((log) => log.status == LogStatus.dropped)
        .length;
    final pinsCount = yearLogs.where(_isPinned).length;
    final statsCount = yearLogs.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMetricRow(
            context,
            label: 'Films',
            valueCount: filmsWatchedThisYear,
            valueText: '$filmsWatchedThisYear this year',
            onAddTap: _goToSearch,
          ),
          _buildMetricRow(
            context,
            label: 'TV shows',
            valueCount: tvWatchedThisYear,
            valueText: '$tvWatchedThisYear this year',
            onAddTap: _goToSearch,
          ),
          _buildMetricRow(
            context,
            label: 'Reviews',
            valueCount: reviewsCount,
            valueText: '$reviewsCount',
            onAddTap: _goToSearch,
          ),
          _buildMetricRow(
            context,
            label: 'Watchlist',
            valueCount: watchlistCount,
            valueText: '$watchlistCount',
            onAddTap: _goToSearch,
          ),
          _buildMetricRow(
            context,
            label: 'Likes',
            valueCount: likesCount,
            valueText: '$likesCount',
            onAddTap: _goToSearch,
          ),
          _buildMetricRow(
            context,
            label: 'Rated',
            valueCount: ratedCount,
            valueText: '$ratedCount',
            onAddTap: _goToSearch,
          ),
          _buildMetricRow(
            context,
            label: 'Holds',
            valueCount: holdsCount,
            valueText: '$holdsCount',
            onAddTap: _goToSearch,
          ),
          _buildMetricRow(
            context,
            label: 'Pins',
            valueCount: pinsCount,
            valueText: '$pinsCount',
            onAddTap: _goToSearch,
          ),
          _buildMetricRow(
            context,
            label: 'Stats',
            valueCount: statsCount,
            valueText: '$statsCount',
            onAddTap: _goToSearch,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _ProfileStatsPage(logs: logs),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDiaryTab(BuildContext context, List<Log> logs) {
    final diaryLogs = logs
        .where(
          (log) =>
              log.status == LogStatus.watched ||
              log.status == LogStatus.watching,
        )
        .toList();

    if (diaryLogs.isEmpty) {
      return _buildEmptyAddCard(
        context: context,
        message: 'No diary entries yet.',
        buttonLabel: 'Add',
        onAdd: _goToSearch,
      );
    }

    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) =>
            _buildPosterTile(context, diaryLogs[index], showRating: true),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: diaryLogs.length.clamp(0, 16),
      ),
    );
  }

  Widget _buildWatchlistTab(BuildContext context, List<Log> logs) {
    final watchlistLogs = logs
        .where(
          (log) =>
              log.status == LogStatus.watchlist ||
              log.status == LogStatus.planToWatch,
        )
        .toList();

    if (watchlistLogs.isEmpty) {
      return _buildEmptyAddCard(
        context: context,
        message: 'Your watchlist is empty.',
        buttonLabel: 'Add',
        onAdd: _goToSearch,
      );
    }

    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) =>
            _buildPosterTile(context, watchlistLogs[index]),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: watchlistLogs.length.clamp(0, 16),
      ),
    );
  }

  Widget _buildListsTab(BuildContext context) {
    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) =>
            _buildAddPosterCard(context: context, label: 'List'),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: 4,
      ),
    );
  }

  Widget _buildProfileTabBody(
    BuildContext context,
    UserProfile? user,
    List<Log> logs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProfileHero(context, user, logs),
        _sectionDivider(),
        _buildSectionTitle(context, 'FAVORITES'),
        _buildFavoritesSection(context, logs),
        _sectionDivider(),
        _buildSectionTitle(context, 'RECENT ACTIVITY'),
        _buildRecentActivitySection(context, logs),
        _sectionDivider(),
        _buildSectionTitle(context, 'RATINGS'),
        _buildRatingsSection(context, logs),
        _sectionDivider(),
        _buildSectionTitle(context, 'SUMMARY'),
        _buildSummarySection(context, logs),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(authUserProvider);
    final logsAsync = ref.watch(watchHistoryProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(authUserProvider);
          ref.invalidate(watchHistoryProvider);
          _contentFutures.clear();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: userAsync.when(
                data: (user) => _buildTopHeader(context, user),
                loading: () => _buildTopHeader(context, null),
                error: (_, __) => _buildTopHeader(context, null),
              ),
            ),
            SliverToBoxAdapter(
              child: logsAsync.when(
                data: (logs) {
                  return userAsync.when(
                    data: (user) {
                      return Column(
                        children: [
                          if (_selectedTab == _ProfileTopTab.profile)
                            _buildProfileTabBody(context, user, logs)
                          else if (_selectedTab == _ProfileTopTab.diary)
                            _buildDiaryTab(context, logs)
                          else if (_selectedTab == _ProfileTopTab.watchlist)
                            _buildWatchlistTab(context, logs)
                          else
                            _buildListsTab(context),
                          const SizedBox(height: 110),
                        ],
                      );
                    },
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Error loading profile: $e'),
                    ),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Error loading activity: $e'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStatsPage extends StatelessWidget {
  const _ProfileStatsPage({required this.logs});

  final List<Log> logs;

  List<int> _buildCurrentMonthWeeklyCounts() {
    final now = DateTime.now();
    final monthLogs = logs
        .where(
          (log) =>
              log.updatedAt.year == now.year &&
              log.updatedAt.month == now.month,
        )
        .toList();

    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final weekCount = (daysInMonth / 7).ceil();
    final counts = List<int>.filled(weekCount, 0);

    for (final log in monthLogs) {
      final weekIndex = ((log.updatedAt.day - 1) / 7).floor().clamp(
        0,
        weekCount - 1,
      );
      counts[weekIndex] += 1;
    }

    return counts;
  }

  List<int> _buildYearMovieMonthlyCounts() {
    final now = DateTime.now();
    final counts = List<int>.filled(12, 0);

    for (final log in logs) {
      final isMovie = log.mediaType == 'movie';
      final isWatched = log.status == LogStatus.watched;
      final isThisYear = log.updatedAt.year == now.year;
      if (isMovie && isWatched && isThisYear) {
        counts[log.updatedAt.month - 1] += 1;
      }
    }

    return counts;
  }

  Widget _buildBarChart(
    BuildContext context, {
    required String title,
    required List<int> counts,
    required List<String> labels,
  }) {
    final maxValue = counts.fold<int>(
      0,
      (prev, value) => math.max(prev, value),
    );
    final hasData = maxValue > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No data yet. Add logs to generate this chart.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.66),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => context.go('/search'),
                  child: const Text('Add'),
                ),
              ],
            )
          else
            SizedBox(
              height: 150,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(counts.length, (index) {
                  final value = counts[index];
                  final ratio = maxValue == 0 ? 0.0 : value / maxValue;
                  final barHeight = 14 + ratio * 92;

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '$value',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.62),
                                ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            labels[index],
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.7),
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthCounts = _buildCurrentMonthWeeklyCounts();
    final yearCounts = _buildYearMovieMonthlyCounts();

    final monthLabels = List<String>.generate(
      monthCounts.length,
      (i) => 'W${i + 1}',
    );
    const yearLabels = [
      'J',
      'F',
      'M',
      'A',
      'M',
      'J',
      'J',
      'A',
      'S',
      'O',
      'N',
      'D',
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Stats')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildBarChart(
            context,
            title: 'App Month Activity',
            counts: monthCounts,
            labels: monthLabels,
          ),
          _buildBarChart(
            context,
            title: 'This Year Movies Watched',
            counts: yearCounts,
            labels: yearLabels,
          ),
        ],
      ),
    );
  }
}
