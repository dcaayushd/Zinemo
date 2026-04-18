import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:zinemo/models/person.dart';
import 'package:zinemo/theme/app_theme.dart';

// Provider to track liked actors
final likedActorsProvider = StateProvider<Set<int>>((ref) => {});

class CastSection extends ConsumerWidget {
  final List<Person> cast;
  final String? title;

  const CastSection({required this.cast, this.title = 'Cast', super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cast.isEmpty) {
      return const SizedBox.shrink();
    }

    final likedActors = ref.watch(likedActorsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              title ?? 'Cast',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cast.length,
              itemBuilder: (context, index) {
                final person = cast[index];
                final isLiked = likedActors.contains(person.id);
                return _buildCastCard(context, person, ref, isLiked);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCastCard(
    BuildContext context,
    Person person,
    WidgetRef ref,
    bool isLiked,
  ) {
    return GestureDetector(
      onTap: () {
        // Navigate to person detail screen
        context.pushNamed(
          'person-detail',
          pathParameters: {'personId': person.id.toString()},
          extra: person,
        );
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile image with like button
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl:
                        person.profileImageUrl ??
                        'https://via.placeholder.com/180x270?text=No+Photo',
                    width: 120,
                    height: 150,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => Container(
                      color: AppTheme.card,
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (ctx, url, err) => Container(
                      color: AppTheme.card,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_outline,
                            color: Colors.white.withValues(alpha: 0.3),
                            size: 32,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Like button overlay
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      final notifier = ref.read(likedActorsProvider.notifier);
                      if (isLiked) {
                        notifier.state = {...notifier.state..remove(person.id)};
                      } else {
                        notifier.state = {...notifier.state, person.id};
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_outline,
                        color: isLiked ? AppTheme.primary : Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Actor name
            Text(
              person.name,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // Character name
            if (person.character != null)
              Text(
                person.character!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

class CrewSection extends ConsumerWidget {
  final List<Person> crew;
  final String? title;

  const CrewSection({required this.crew, this.title = 'Crew', super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (crew.isEmpty) {
      return const SizedBox.shrink();
    }

    final likedActors = ref.watch(likedActorsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title ?? 'Crew', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          // Group crew by department/job
          ...crew.take(12).map((person) {
            final isLiked = likedActors.contains(person.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  context.pushNamed(
                    'person-detail',
                    pathParameters: {'personId': person.id.toString()},
                    extra: person,
                  );
                },
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        person.name,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        person.job ?? person.department ?? '',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        final notifier = ref.read(likedActorsProvider.notifier);
                        if (isLiked) {
                          notifier.state = {
                            ...notifier.state..remove(person.id),
                          };
                        } else {
                          notifier.state = {...notifier.state, person.id};
                        }
                      },
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_outline,
                        color: isLiked ? AppTheme.primary : Colors.white70,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
