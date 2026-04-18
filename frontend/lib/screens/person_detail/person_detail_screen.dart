import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:zinemo/models/person.dart';
import 'package:zinemo/models/content.dart';
import 'package:zinemo/services/tmdb_service.dart';
import 'package:zinemo/theme/app_theme.dart';

// Provider for person details
final personDetailProvider = FutureProvider.family<Person?, int>((
  ref,
  personId,
) async {
  try {
    return await TMDBService.getPerson(personId);
  } catch (e) {
    return null;
  }
});

// Provider for person's filmography
final personFilmographyProvider = FutureProvider.family<List<Content>, int>((
  ref,
  personId,
) async {
  try {
    return await TMDBService.getPersonFilmography(personId);
  } catch (e) {
    return [];
  }
});

class PersonDetailScreen extends ConsumerStatefulWidget {
  final int personId;
  final Person? initialPerson;

  const PersonDetailScreen({
    required this.personId,
    this.initialPerson,
    super.key,
  });

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final personAsync = ref.watch(personDetailProvider(widget.personId));
    final filmographyAsync = ref.watch(
      personFilmographyProvider(widget.personId),
    );

    return Scaffold(
      body: personAsync.when(
        data: (person) {
          final displayPerson = person ?? widget.initialPerson;
          if (displayPerson == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('Person not found')),
            );
          }

          return CustomScrollView(
            slivers: [
              // App bar
              SliverAppBar(
                expandedHeight: 80,
                pinned: true,
                leading: GestureDetector(
                  onTap: () => context.pop(),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircleAvatar(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      child: const Icon(Icons.arrow_back),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  title: Text(displayPerson.name),
                  centerTitle: true,
                ),
              ),

              // Profile header
              SliverToBoxAdapter(
                child: _buildProfileHeader(context, displayPerson),
              ),

              // Bio section
              if (displayPerson.biography != null &&
                  displayPerson.biography!.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildBioSection(context, displayPerson),
                ),

              // Filmography header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                  child: Text(
                    'Filmography',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),

              // Filmography list
              filmographyAsync.when(
                data: (filmography) {
                  if (filmography.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No filmography found',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                        ),
                      ),
                    );
                  }

                  return SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.6,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: filmography.length,
                    itemBuilder: (ctx, idx) {
                      final content = filmography[idx];
                      return _buildFilmographyCard(context, content);
                    },
                  );
                },
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, st) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Error loading filmography: $e'),
                  ),
                ),
              ),

              const SliverSafeArea(
                top: false,
                sliver: SliverToBoxAdapter(child: SizedBox(height: 30)),
              ),
            ],
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
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, Person person) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Profile image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl:
                  person.profileImageUrl ??
                  'https://via.placeholder.com/342x513?text=No+Photo',
              width: 200,
              height: 300,
              fit: BoxFit.cover,
              errorWidget: (ctx, url, err) => Container(
                width: 200,
                height: 300,
                color: AppTheme.card,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_outline,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: 48,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Name (large)
          Text(
            person.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Personal info
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (person.birthday != null)
                _buildInfoChip(context, '${person.birthday!.year}', 'Born'),
              if (person.placeOfBirth != null)
                _buildInfoChip(context, person.placeOfBirth!, 'From'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(BuildContext context, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildBioSection(BuildContext context, Person person) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Biography', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Text(
            person.biography ?? '',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildFilmographyCard(BuildContext context, Content content) {
    return GestureDetector(
      onTap: () {
        context.pushNamed(
          content.mediaType == 'tv' ? 'tv-detail' : 'movie-detail',
          pathParameters: {'tmdbId': content.tmdbId.toString()},
          extra: content,
        );
      },
      child: Card(
        color: AppTheme.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: CachedNetworkImage(
                  imageUrl: content.posterUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorWidget: (ctx, url, err) => Container(
                    color: AppTheme.card,
                    child: const Icon(Icons.movie_outlined),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    content.releaseDate != null
                        ? '${content.releaseDate!.year}'
                        : 'N/A',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
