import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:zinemo/theme/app_theme.dart';

class DetailRatingsSection extends StatefulWidget {
  final double voteAverage; // 0-10 scale
  final int voteCount;
  final List<double>? distribution; // normalized 0..1
  final List<int>? distributionCounts; // absolute counts per bin
  final String ctaLabel;
  final String? avatarUrl;
  final VoidCallback? onCtaTap;

  const DetailRatingsSection({
    required this.voteAverage,
    required this.voteCount,
    this.distribution,
    this.distributionCounts,
    required this.ctaLabel,
    this.avatarUrl,
    this.onCtaTap,
    super.key,
  });

  @override
  State<DetailRatingsSection> createState() => _DetailRatingsSectionState();
}

class _DetailRatingsSectionState extends State<DetailRatingsSection> {
  static const int _barCount = 9;
  int? _pressedBarIndex;

  double get _stars => (widget.voteAverage / 2).clamp(0.0, 5.0);

  List<double> _buildDistribution() {
    if (widget.distribution != null && widget.distribution!.isNotEmpty) {
      final trimmed = widget.distribution!.take(_barCount).toList();
      if (trimmed.length < _barCount) {
        trimmed.addAll(List<double>.filled(_barCount - trimmed.length, 0.0));
      }

      final maxValue = trimmed.reduce(math.max);
      if (maxValue <= 0) {
        return List<double>.filled(_barCount, 0.0);
      }

      return trimmed.map((value) => value / maxValue).toList();
    }

    const sigma = 0.62;
    final values = List<double>.generate(_barCount, (index) {
      final x = 1 + (index / (_barCount - 1)) * 4;
      final gaussian = math.exp(-math.pow(x - _stars, 2) / (2 * sigma * sigma));
      final tailBoost = index >= _barCount - 3
          ? 0.06 * (index - (_barCount - 3) + 1)
          : 0.0;
      final floor = index < 2 ? 0.015 : 0.045;
      return (gaussian + tailBoost + floor).toDouble();
    });

    final maxValue = values.reduce(math.max);
    return values.map((value) => value / maxValue).toList();
  }

  List<int> _buildCounts(List<double> bars) {
    if (widget.distributionCounts != null &&
        widget.distributionCounts!.isNotEmpty) {
      final trimmed = widget.distributionCounts!.take(_barCount).toList();
      if (trimmed.length < _barCount) {
        trimmed.addAll(List<int>.filled(_barCount - trimmed.length, 0));
      }
      return trimmed;
    }

    if (widget.voteCount <= 0) {
      return List<int>.filled(_barCount, 0);
    }

    final sum = bars.fold<double>(0.0, (acc, value) => acc + value);
    if (sum <= 0) {
      return List<int>.filled(_barCount, 0);
    }

    final raw = bars.map((value) => (value / sum) * widget.voteCount).toList();
    final counts = raw.map((value) => value.floor()).toList();
    var assigned = counts.fold<int>(0, (acc, value) => acc + value);

    if (assigned < widget.voteCount) {
      final remainder =
          raw
              .asMap()
              .entries
              .map(
                (entry) =>
                    (entry.key, entry.value - entry.value.floorToDouble()),
              )
              .toList()
            ..sort((a, b) => b.$2.compareTo(a.$2));

      var idx = 0;
      while (assigned < widget.voteCount) {
        final target = remainder[idx % remainder.length].$1;
        counts[target] += 1;
        assigned += 1;
        idx += 1;
      }
    }

    return counts;
  }

  int _peakIndex(List<int> counts) {
    var bestIndex = 0;
    var bestValue = -1;

    for (var i = 0; i < counts.length; i++) {
      if (counts[i] > bestValue) {
        bestValue = counts[i];
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  double _starsForBin(int index) => 1 + (index * 0.5);

  String _compactCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  Widget _buildStarsRow(double stars) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final value = index + 1.0;
        final icon = stars >= value
            ? Icons.star_rounded
            : (stars >= value - 0.5
                  ? Icons.star_half_rounded
                  : Icons.star_outline_rounded);

        return Icon(icon, size: 14, color: AppTheme.success);
      }),
    );
  }

  void _setPressedBarFromDx(double dx, double maxWidth) {
    if (maxWidth <= 0) {
      return;
    }

    final normalized = (dx / maxWidth).clamp(0.0, 0.999999);
    final index = (normalized * _barCount).floor().clamp(0, _barCount - 1);
    if (_pressedBarIndex != index) {
      setState(() {
        _pressedBarIndex = index;
      });
    }
  }

  void _clearPressedIndex() {
    if (_pressedBarIndex != null) {
      setState(() {
        _pressedBarIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bars = _buildDistribution();
    final counts = _buildCounts(bars);
    final activeIndex = _pressedBarIndex;
    final peakIndex = _peakIndex(counts);
    final shownStars = activeIndex == null ? _stars : _starsForBin(activeIndex);

    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'RATINGS',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.voteCount} ratings',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.56),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SizedBox(
              height: 120,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTapDown: (details) => _setPressedBarFromDx(
                                  details.localPosition.dx,
                                  constraints.maxWidth,
                                ),
                                onHorizontalDragStart: (details) =>
                                    _setPressedBarFromDx(
                                      details.localPosition.dx,
                                      constraints.maxWidth,
                                    ),
                                onHorizontalDragUpdate: (details) =>
                                    _setPressedBarFromDx(
                                      details.localPosition.dx,
                                      constraints.maxWidth,
                                    ),
                                onTapUp: (_) => _clearPressedIndex(),
                                onTapCancel: _clearPressedIndex,
                                onHorizontalDragEnd: (_) =>
                                    _clearPressedIndex(),
                                onHorizontalDragCancel: _clearPressedIndex,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(_barCount, (index) {
                                    final ratio = bars[index].clamp(0.0, 1.0);
                                    final isHighlighted =
                                        (activeIndex != null &&
                                            activeIndex == index) ||
                                        (activeIndex == null &&
                                            index == peakIndex);

                                    return Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                        ),
                                        child: LayoutBuilder(
                                          builder: (context, constraints) {
                                            const minBarHeight = 8.0;
                                            const labelAreaHeight = 28.0;
                                            final maxBarHeight = math.max(
                                              minBarHeight,
                                              constraints.maxHeight -
                                                  labelAreaHeight,
                                            );
                                            final barHeight =
                                                minBarHeight +
                                                (ratio *
                                                    (maxBarHeight -
                                                        minBarHeight));

                                            return Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                if (activeIndex == index)
                                                  Align(
                                                    alignment:
                                                        Alignment.topCenter,
                                                    child: Text(
                                                      _compactCount(
                                                        counts[index],
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.fade,
                                                      softWrap: false,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            color: Colors.white
                                                                .withValues(
                                                                  alpha: 0.8,
                                                                ),
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                    ),
                                                  ),
                                                Align(
                                                  alignment:
                                                      Alignment.bottomCenter,
                                                  child: AnimatedContainer(
                                                    duration: const Duration(
                                                      milliseconds: 120,
                                                    ),
                                                    curve: Curves.easeOut,
                                                    height: barHeight,
                                                    decoration: BoxDecoration(
                                                      color: isHighlighted
                                                          ? AppTheme.primary
                                                          : const Color(
                                                              0xFF5D728A,
                                                            ).withValues(
                                                              alpha: 0.86,
                                                            ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            2,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              '1★',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              '5★',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  SizedBox(
                    width: 92,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          shownStars.toStringAsFixed(1),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.88),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 2),
                        _buildStarsRow(shownStars),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Material(
              color: const Color(0xFF4D6178).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: widget.onCtaTap,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        child: ClipOval(
                          child:
                              widget.avatarUrl != null &&
                                  widget.avatarUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: widget.avatarUrl!,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Icon(
                                    Icons.person,
                                    color: Colors.white.withValues(alpha: 0.84),
                                  ),
                                )
                              : Icon(
                                  Icons.person,
                                  color: Colors.white.withValues(alpha: 0.84),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.ctaLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.94),
                                fontWeight: FontWeight.w500,
                                fontSize: 15,
                              ),
                        ),
                      ),
                      Icon(
                        Icons.more_horiz,
                        color: Colors.white.withValues(alpha: 0.56),
                        size: 28,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
