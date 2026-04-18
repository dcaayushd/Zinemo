import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:zinemo/theme/app_theme.dart';
import 'package:zinemo/models/content.dart';
import 'package:zinemo/providers/app_providers.dart';
import 'package:zinemo/widgets/content_actions_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final Set<String> _pinnedKeys = <String>{};

  static const Map<String, String> _mediaModes = {
    'all': 'All',
    'movie': 'Movies',
    'tv': 'TV Shows',
  };

  String _contentKey(Content content) =>
      '${content.mediaType}:${content.tmdbId}';

  bool _isPinned(Content content) => _pinnedKeys.contains(_contentKey(content));

  void _togglePin(Content content) {
    final key = _contentKey(content);
    final wasPinned = _pinnedKeys.contains(key);

    setState(() {
      if (wasPinned) {
        _pinnedKeys.remove(key);
      } else {
        _pinnedKeys.add(key);
      }
    });

    final label = wasPinned ? 'Removed from Pinned' : 'Pinned for later';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label: ${content.title}')));
  }

  void _openDetails(Content content) {
    final routeName = content.mediaType == 'tv' ? 'tv-detail' : 'movie-detail';
    context.pushNamed(
      routeName,
      pathParameters: {'tmdbId': content.tmdbId.toString()},
      extra: content,
    );
  }

  void _showContentActions(Content content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ContentActionsSheet(
        content: content,
        onDismiss: () => Navigator.of(ctx).pop(),
        onActionCompleted: () {
          ref.invalidate(watchHistoryProvider);
          ref.invalidate(continueWatchingProvider);
          ref.invalidate(contentRatingsProvider);
          ref.invalidate(episodeRatingsProvider);
        },
      ),
    );
  }

  Future<void> _refreshHome(String mediaMode) async {
    ref.invalidate(trendingByMediaProvider(mediaMode));
    ref.invalidate(newReleasesByMediaProvider(mediaMode));
    ref.invalidate(continueWatchingProvider);
  }

  @override
  Widget build(BuildContext context) {
    final mediaMode = ref.watch(homeMediaTypeProvider);
    final trendingAsync = ref.watch(trendingByMediaProvider(mediaMode));
    final newReleasesAsync = ref.watch(newReleasesByMediaProvider(mediaMode));
    final continueWatchingAsync = ref.watch(continueWatchingProvider);

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppTheme.screenGradient),
            ),
          ),
          Positioned(
            top: -160,
            left: -120,
            child: _buildGlow(AppTheme.primary.withValues(alpha: 0.24)),
          ),
          Positioned(
            top: 110,
            right: -140,
            child: _buildGlow(AppTheme.secondary.withValues(alpha: 0.18)),
          ),
          Positioned(
            bottom: 130,
            left: -120,
            child: _buildGlow(AppTheme.tertiary.withValues(alpha: 0.14)),
          ),
          SafeArea(
            child: RefreshIndicator(
              color: AppTheme.primary,
              backgroundColor: AppTheme.surface,
              onRefresh: () => _refreshHome(mediaMode),
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.only(bottom: 128),
                children: [
                  _buildTopHeader(context),
                  _buildMediaModeChips(context, mediaMode),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.14),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildAsyncSection(
                    context,
                    asyncItems: trendingAsync,
                    title: 'Trending Now',
                    subtitle: mediaMode == 'tv'
                        ? 'TV everyone is binging this week'
                        : mediaMode == 'movie'
                        ? 'Movies popular this week'
                        : 'Movies + TV buzzing this week',
                    badgeLabel: 'Hot',
                  ),
                  _buildAsyncSection(
                    context,
                    asyncItems: continueWatchingAsync,
                    title: 'Continue Watching',
                    subtitle: 'Pick up right where you left off',
                    badgeLabel: 'Continue',
                    emptyMessage:
                        'Start a title and mark it as Watching to continue later.',
                  ),
                  _buildAsyncSection(
                    context,
                    asyncItems: newReleasesAsync,
                    title: 'New Releases',
                    subtitle: 'Fresh arrivals this week',
                    badgeLabel: 'New',
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlow(Color color) {
    return IgnorePointer(
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.primary, AppTheme.warning],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.38),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.local_movies_rounded,
                  color: Colors.black,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ZINEMO',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontSize: 30,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    Text(
                      'Track every movie and TV obsession',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Text('Home', style: Theme.of(context).textTheme.titleLarge),
        ],
      ).animate().fadeIn(duration: 350.ms).slideY(begin: -0.05, end: 0),
    );
  }

  Widget _buildMediaModeChips(BuildContext context, String mediaMode) {
    IconData iconFor(String key) {
      switch (key) {
        case 'movie':
          return Icons.movie_outlined;
        case 'tv':
          return Icons.tv_rounded;
        default:
          return Icons.widgets_outlined;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemBuilder: (context, index) {
            final entry = _mediaModes.entries.elementAt(index);
            final selected = mediaMode == entry.key;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  ref.read(homeMediaTypeProvider.notifier).state = entry.key;
                },
                child: AnimatedContainer(
                  duration: 220.ms,
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppTheme.primary.withValues(alpha: 0.2)
                        : AppTheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primary.withValues(alpha: 0.85)
                          : Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        iconFor(entry.key),
                        size: 16,
                        color: selected ? AppTheme.primary : Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        entry.value,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: selected ? AppTheme.primary : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemCount: _mediaModes.length,
        ),
      ),
    );
  }

  Widget _buildAsyncSection(
    BuildContext context, {
    required AsyncValue<List<Content>> asyncItems,
    required String title,
    required String subtitle,
    required String badgeLabel,
    String? emptyMessage,
  }) {
    return asyncItems.when(
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.card.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text(
                    emptyMessage ??
                        'No titles available right now. Pull to refresh.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          );
        }

        return _buildSection(
          context,
          title: title,
          subtitle: subtitle,
          children: items.take(12).map((movie) {
            return _buildPosterCard(movie, badgeLabel: badgeLabel);
          }).toList(),
        );
      },
      loading: () => _buildLoadingSection(context, title, subtitle),
      error: (error, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
        child: Text(
          'Failed to load $title. Pull to refresh.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Widget _buildLoadingSection(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    return _buildSection(
      context,
      title: title,
      subtitle: subtitle,
      children: List.generate(
        4,
        (index) => SizedBox(
          width: 164,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: AppTheme.card.withValues(alpha: 0.68),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge)
                        .animate()
                        .slideX(begin: -0.2, end: 0, duration: 400.ms)
                        .fadeIn(),
                    const SizedBox(height: 4),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall)
                        .animate()
                        .slideX(begin: -0.2, end: 0, duration: 500.ms)
                        .fadeIn(),
                  ],
                ),
              ),
              Text(
                'View all',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 274,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                children[i]
                    .animate()
                    .slideX(
                      begin: 0.3,
                      end: 0,
                      delay: (i * 100).ms,
                      duration: 400.ms,
                    )
                    .fadeIn(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPosterCard(Content movie, {required String badgeLabel}) {
    final posterUrl = movie.posterUrl;
    final pinned = _isPinned(movie);

    return SizedBox(
      width: 166,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openDetails(movie),
          onLongPress: () => _showContentActions(movie),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              color: AppTheme.card,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: AppTheme.card,
                            child: Center(
                              child: Icon(
                                Icons.image_outlined,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: AppTheme.card,
                            child: Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.08),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.68),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTap: () => _togglePin(movie),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.58),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.14),
                                ),
                              ),
                              child: Icon(
                                pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 17,
                                color: pinned ? AppTheme.primary : Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              badgeLabel,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                                letterSpacing: 0.25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 11),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        movie.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: AppTheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            (movie.voteAverage ?? 0).toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.surface.withValues(alpha: 0.74),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  movie.mediaType == 'tv'
                                      ? Icons.tv_rounded
                                      : Icons.movie_rounded,
                                  size: 12,
                                  color: AppTheme.secondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  movie.mediaType == 'tv' ? 'TV' : 'Movie',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
