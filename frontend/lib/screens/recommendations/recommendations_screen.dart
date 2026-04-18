import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:zinemo/models/content.dart';
import 'package:zinemo/providers/app_providers.dart';
import 'package:zinemo/services/recommendation_service.dart';
import 'package:zinemo/theme/app_theme.dart';
import 'package:zinemo/widgets/content_actions_sheet.dart';

/// Recommendations screen with full animation spec from CLAUDE.md
/// - Vertical PageView with scale animation
/// - Whole-screen background color morph (500ms ColorTween)
/// - Genre selector pill with slot-machine animation
class RecommendationsScreen extends ConsumerStatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  ConsumerState<RecommendationsScreen> createState() =>
      _RecommendationsScreenState();
}

class _RecommendationsScreenState extends ConsumerState<RecommendationsScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _bgColorController;
  late AnimationController _playPulseController;
  late ColorTween _bgColorTween;

  bool _disableAnimations = false;
  Color _currentBgColor = const Color(0xFF0A0A0F);
  int _currentIndex = 0;
  String? _selectedGenre;
  String? _currentPosterUrl;
  String _recommendationSignature = '';

  List<RecommendationItem> _latestRecommendations = const [];
  final Map<String, Color> _posterColorCache = <String, Color>{};

  final List<String> _genres = const [
    'Romance',
    'Top 10',
    'Drama',
    'Horror',
    'Action',
    'Comedy',
    'Thriller',
    'Sci-Fi',
    'Documentary',
    'Animation',
  ];

  final List<Color> _genreBackgrounds = const [
    Color(0xFF21192E),
    Color(0xFF1B2738),
    Color(0xFF322022),
    Color(0xFF191526),
    Color(0xFF202E1E),
    Color(0xFF2A1F18),
    Color(0xFF211A2F),
    Color(0xFF152337),
    Color(0xFF12262D),
    Color(0xFF2C2218),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.90);
    _bgColorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..value = 1;
    _playPulseController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);
    _bgColorTween = ColorTween(begin: _currentBgColor, end: _currentBgColor);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disable = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disable == _disableAnimations) {
      return;
    }

    _disableAnimations = disable;
    if (_disableAnimations) {
      _playPulseController.stop();
      _playPulseController.value = 0;
      _bgColorController.value = 1;
    } else {
      _playPulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bgColorController.dispose();
    _playPulseController.dispose();
    super.dispose();
  }

  void _showContentActions(RecommendationItem rec) {
    final content = Content(
      tmdbId: rec.tmdbId,
      mediaType: rec.mediaType,
      title: rec.title ?? 'Title #${rec.tmdbId}',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => ContentActionsSheet(
        content: content,
        onDismiss: () => Navigator.of(context).pop(),
        onActionCompleted: () {
          ref.invalidate(watchHistoryProvider);
          ref.invalidate(continueWatchingProvider);
          ref.invalidate(contentRatingsProvider);
          ref.invalidate(episodeRatingsProvider);
        },
      ),
    );
  }

  void _openDetails(RecommendationItem rec) {
    final routeName = rec.mediaType == 'tv' ? 'tv-detail' : 'movie-detail';
    context.pushNamed(
      routeName,
      pathParameters: {'tmdbId': rec.tmdbId.toString()},
    );
  }

  void _onPageChanged(int index) {
    if (_latestRecommendations.isEmpty) {
      return;
    }

    final maxIndex = _latestRecommendations.length - 1;
    final nextIndex = index.clamp(0, maxIndex);

    setState(() {
      _currentIndex = nextIndex;
    });
    _morphBackgroundForIndex(nextIndex);
  }

  String _activeGenre() {
    return _selectedGenre ?? _genres[_currentIndex % _genres.length];
  }

  RecommendationItem? _activeRecommendation() {
    if (_latestRecommendations.isEmpty) {
      return null;
    }

    final maxIndex = _latestRecommendations.length - 1;
    final safeIndex = _currentIndex.clamp(0, maxIndex);
    return _latestRecommendations[safeIndex];
  }

  double _pageDragBlend() {
    if (!_pageController.hasClients ||
        !_pageController.position.haveDimensions) {
      return 0;
    }

    final page = _pageController.page ?? _currentIndex.toDouble();
    return (page - page.roundToDouble()).abs().clamp(0.0, 1.0);
  }

  String? _resolvedPosterUrl(RecommendationItem rec) {
    final posterPath = rec.posterPath;
    if (posterPath == null || posterPath.trim().isEmpty) {
      return null;
    }

    if (posterPath.startsWith('http://') || posterPath.startsWith('https://')) {
      return posterPath;
    }

    return 'https://image.tmdb.org/t/p/w780$posterPath';
  }

  void _syncRecommendations(List<RecommendationItem> recommendations) {
    _latestRecommendations = recommendations;
    if (recommendations.isEmpty) {
      return;
    }

    final signature =
        '${recommendations.length}:${recommendations.first.tmdbId}:${recommendations.last.tmdbId}:${_selectedGenre ?? ''}';

    if (signature == _recommendationSignature) {
      return;
    }

    _recommendationSignature = signature;
    final safeIndex = _currentIndex.clamp(0, recommendations.length - 1);
    _currentIndex = safeIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || recommendations.isEmpty) {
        return;
      }

      if (_pageController.hasClients) {
        _pageController.jumpToPage(safeIndex);
      }
      _morphBackgroundForIndex(safeIndex);
    });
  }

  Future<void> _morphBackgroundForIndex(int index) async {
    if (_latestRecommendations.isEmpty) {
      return;
    }

    final maxIndex = _latestRecommendations.length - 1;
    final safeIndex = index.clamp(0, maxIndex);
    final rec = _latestRecommendations[safeIndex];
    final fallback = _genreBackgrounds[safeIndex % _genreBackgrounds.length];
    final posterUrl = _resolvedPosterUrl(rec);

    setState(() {
      _currentPosterUrl = posterUrl;
    });

    if (posterUrl == null) {
      _animateBackgroundTo(fallback);
      return;
    }

    final cached = _posterColorCache[posterUrl];
    if (cached != null) {
      _animateBackgroundTo(cached);
      return;
    }

    final requestedIndex = safeIndex;

    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(posterUrl),
        size: const Size(220, 340),
        maximumColorCount: 12,
      );

      if (!mounted || requestedIndex != _currentIndex) {
        return;
      }

      final extracted =
          palette.darkVibrantColor?.color ??
          palette.dominantColor?.color ??
          fallback;

      final hsl = HSLColor.fromColor(extracted);
      final target = hsl
          .withSaturation((hsl.saturation * 0.9).clamp(0.2, 0.95))
          .withLightness((hsl.lightness * 0.45).clamp(0.08, 0.34))
          .toColor();

      _posterColorCache[posterUrl] = target;
      _animateBackgroundTo(target);
    } catch (_) {
      if (!mounted || requestedIndex != _currentIndex) {
        return;
      }
      _animateBackgroundTo(fallback);
    }
  }

  void _animateBackgroundTo(Color target) {
    if (!mounted) {
      return;
    }

    if (_disableAnimations) {
      setState(() {
        _bgColorTween = ColorTween(begin: target, end: target);
        _currentBgColor = target;
        _bgColorController.value = 1;
      });
      return;
    }

    setState(() {
      _bgColorTween = ColorTween(begin: _currentBgColor, end: target);
      _currentBgColor = target;
    });
    _bgColorController.forward(from: 0);
  }

  Future<void> _showGenrePicker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                "what's your mood?",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 320,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _genres.length,
                  itemBuilder: (context, index) {
                    final genre = _genres[index];
                    final isSelected = genre == _activeGenre();

                    return ListTile(
                      title: Text(genre),
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              color: AppTheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(context).pop(genre),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (selected == null) {
      return;
    }

    setState(() {
      _selectedGenre = selected;
      _currentIndex = 0;
      _recommendationSignature = '';
      _posterColorCache.clear();
    });

    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }

    ref.read(genreFilterProvider.notifier).state = selected == 'Top 10'
        ? null
        : selected;
    ref.invalidate(recommendationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final recommendationsAsync = ref.watch(recommendationsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: recommendationsAsync.when(
        data: (recommendations) {
          _syncRecommendations(recommendations);

          if (recommendations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.movie_outlined,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'No recommendations yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Log some movies to get personalized recommendations',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return Stack(
            children: [
              _buildDynamicBackground(),

              PageView.builder(
                scrollDirection: Axis.vertical,
                controller: _pageController,
                padEnds: false,
                physics: const BouncingScrollPhysics(),
                onPageChanged: _onPageChanged,
                itemCount: recommendations.length,
                itemBuilder: (context, index) {
                  final rec = recommendations[index];
                  return _buildMovieCard(context, rec, index);
                },
              ),

              _buildTopBar(context),

              Positioned(
                bottom: 90,
                left: 0,
                right: 0,
                child: _buildGenrePill(context),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading recommendations: $error',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBackTap() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  void _handleBookmarkTap() {
    final active = _activeRecommendation();
    if (active != null) {
      _showContentActions(active);
      return;
    }
    _showGenrePicker();
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: Colors.white),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _buildTopActionButton(
                icon: Icons.chevron_left_rounded,
                onTap: _handleBackTap,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    'Recommendations',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ).animate().fadeIn(duration: 320.ms),
                ),
              ),
              _buildTopActionButton(
                icon: Icons.bookmark_border_rounded,
                onTap: _handleBookmarkTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicBackground() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([_bgColorController, _pageController]),
        builder: (context, _) {
          final base =
              _bgColorTween.evaluate(_bgColorController) ?? AppTheme.background;
          final dragBlend = _pageDragBlend();

          return Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.alphaBlend(
                        Colors.blue.withValues(alpha: 0.08),
                        base,
                      ),
                      base,
                      Color.alphaBlend(
                        Colors.black.withValues(alpha: 0.4),
                        base,
                      ),
                    ],
                  ),
                ),
              ),
              if (_currentPosterUrl != null)
                Opacity(
                  opacity: 0.26,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                    child: CachedNetworkImage(
                      imageUrl: _currentPosterUrl!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.14 + (dragBlend * 0.18)),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.52 + (dragBlend * 0.26)),
                    ],
                    stops: const [0.0, 0.46, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: -120,
                right: -80,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMovieCard(
    BuildContext context,
    RecommendationItem rec,
    int index,
  ) {
    final posterUrl = _resolvedPosterUrl(rec);
    final size = MediaQuery.sizeOf(context);
    final horizontalPadding = (size.width * 0.14).clamp(30.0, 66.0).toDouble();
    final topPadding = (size.height * 0.13).clamp(92.0, 168.0).toDouble();
    final bottomPadding = (size.height * 0.17).clamp(128.0, 228.0).toDouble();

    return GestureDetector(
      onTap: () => _openDetails(rec),
      onLongPress: () => _showContentActions(rec),
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _pageController,
          builder: (context, _) {
            var page = index.toDouble();
            if (_pageController.hasClients &&
                _pageController.position.haveDimensions) {
              page = _pageController.page ?? index.toDouble();
            }

            final signedDistance = index - page;
            final distance = signedDistance.abs();
            final normalizedDistance = distance.clamp(0.0, 1.0).toDouble();
            final approach = (1 - normalizedDistance).clamp(0.0, 1.0);
            final direction = signedDistance == 0 ? 0.0 : signedDistance.sign;

            final curvedApproach = Curves.easeOutCubic.transform(approach);
            final scale = (0.80 + (curvedApproach * 0.20)).clamp(0.80, 1.0);
            final opacity = (0.42 + (curvedApproach * 0.58)).clamp(0.42, 1.0);

            // Curved lane entry: incoming posters rise from the full bottom
            // left/right lanes, pop slightly toward the viewer, then settle.
            final laneSign = index.isEven ? -1.0 : 1.0;
            final sweep = Curves.easeInOutCubic.transform(normalizedDistance);
            final arc = math.sin(sweep * math.pi);
            final entryDirection = direction == 0 ? 0.0 : laneSign * direction;

            final laneWidth = size.width * 0.44;
            final translateX =
                entryDirection * ((laneWidth * sweep) + (arc * 18));
            final translateY =
                direction * ((size.height * 0.21 * sweep) + (arc * 14));
            final translateZ = 26 * sweep;
            final rotateZ =
                entryDirection * (sweep + arc) * (math.pi / 180) * 4.2;
            final rotateX = direction * sweep * 0.20;
            final scaleX = (scale * (1 - (sweep * 0.10))).clamp(0.68, 1.0);
            final scaleY = (scale * (1 + (sweep * 0.05))).clamp(0.80, 1.08);

            final dragBlend = Curves.easeOut.transform(normalizedDistance);
            final topBlend = (0.12 + (dragBlend * 0.24)).clamp(0.12, 0.36);
            final bottomBlend = (0.72 + (dragBlend * 0.22)).clamp(0.72, 0.94);

            return Opacity(
              opacity: opacity,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..translateByDouble(translateX, translateY, translateZ, 1)
                  ..rotateZ(rotateZ)
                  ..rotateX(rotateX)
                  ..scaleByDouble(scaleX, scaleY, 1, 1),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topPadding,
                    horizontalPadding,
                    bottomPadding,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: _currentBgColor.withValues(alpha: 0.4),
                          blurRadius: 42,
                          spreadRadius: 6,
                          offset: const Offset(0, 22),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (posterUrl != null)
                            CachedNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, _) =>
                                  Container(color: AppTheme.card),
                              errorWidget: (context, _, __) => Container(
                                color: AppTheme.card,
                                child: Center(
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    size: 64,
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                              ),
                            )
                          else
                            Container(
                              color: AppTheme.card,
                              child: Center(
                                child: Icon(
                                  Icons.image_not_supported_outlined,
                                  size: 64,
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                            ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: topBlend),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: bottomBlend),
                                ],
                                stops: const [0.0, 0.42, 1.0],
                              ),
                            ),
                          ),
                          Positioned(
                            top: -54,
                            left: -24,
                            child: Container(
                              width: 168,
                              height: 168,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0.16),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Center(child: _buildPlayButton()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    final pulse = _disableAnimations ? 0.0 : _playPulseController.value;
    final ringScale = 1 + (pulse * 0.12);

    return RepaintBoundary(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: ringScale,
            child: Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.4,
                ),
              ),
            ),
          ),
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 46,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenrePill(BuildContext context) {
    return GestureDetector(
      onTap: _showGenrePicker,
      child: RepaintBoundary(
        child: SizedBox(
          height: 84,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1D2D4F).withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30),
                        blurRadius: 14,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Text(
                    "what's your mood?",
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
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
