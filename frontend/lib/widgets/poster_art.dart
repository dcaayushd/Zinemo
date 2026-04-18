import 'package:flutter/material.dart';
import 'package:zinemo/data/sample_catalog.dart';
import 'package:zinemo/theme/app_theme.dart';

class PosterArt extends StatelessWidget {
  const PosterArt({
    super.key,
    required this.movie,
    this.height = 260,
    this.width,
    this.heroTag,
    this.showBadges = true,
  });

  final ZinemoTitle movie;
  final double height;
  final double? width;
  final String? heroTag;
  final bool showBadges;

  @override
  Widget build(BuildContext context) {
    final art = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            movie.themeColor.withValues(alpha: 0.95),
            movie.themeColor.withValues(alpha: 0.55),
            AppTheme.background,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: movie.themeColor.withValues(alpha: 0.35),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: 22,
            left: 22,
            right: 22,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    movie.mediaType.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.star_rounded,
                  color: AppTheme.secondary,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  movie.rating.toStringAsFixed(1),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showBadges && movie.badges.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: movie.badges.take(2).map((badge) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 14),
                Text(
                  movie.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  movie.tagline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (heroTag == null) {
      return art;
    }
    return Hero(tag: heroTag!, child: art);
  }
}
