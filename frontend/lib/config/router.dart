import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:zinemo/models/index.dart';
import 'package:zinemo/screens/index.dart';

/// GoRouter configuration for Zinemo app
class AppRouter {
  static final GoRouter instance = GoRouter(
    initialLocation: '/splash',
    routes: [
      // ─ Auth & Onboarding Routes
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: SplashScreen()),
      ),
      GoRoute(
        path: '/auth',
        name: 'auth',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: AuthScreen()),
      ),
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: OnboardingPreferencesScreen()),
      ),

      // ─ Main App Shell with nested routes
      StatefulShellRoute.indexedStack(
        pageBuilder: (context, state, navigationShell) {
          return NoTransitionPage(
            child: AppShell(navigationShell: navigationShell),
          );
        },
        branches: [
          // Branch 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                name: 'home',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: HomeScreen()),
                routes: [
                  GoRoute(
                    path: 'detail/:tmdbId',
                    name: 'movie-detail',
                    pageBuilder: (context, state) {
                      final tmdbId = int.parse(state.pathParameters['tmdbId']!);
                      final content = state.extra as Content?;
                      return MaterialPage(
                        child: MovieDetailScreen(
                          tmdbId: tmdbId,
                          initialContent: content,
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'tv/:tmdbId',
                    name: 'tv-detail',
                    pageBuilder: (context, state) {
                      final tmdbId = int.parse(state.pathParameters['tmdbId']!);
                      final content = state.extra as Content?;
                      return MaterialPage(
                        child: TVDetailScreen(
                          tmdbId: tmdbId,
                          initialContent: content,
                        ),
                      );
                    },
                    routes: [
                      GoRoute(
                        path: 'season/:seasonNumber',
                        name: 'tv-season-detail',
                        pageBuilder: (context, state) {
                          final tmdbId = int.parse(
                            state.pathParameters['tmdbId']!,
                          );
                          final seasonNumber = int.parse(
                            state.pathParameters['seasonNumber']!,
                          );
                          final content = state.extra as Content?;

                          return MaterialPage(
                            child: TVSeasonDetailScreen(
                              tmdbId: tmdbId,
                              seasonNumber: seasonNumber,
                              show: content,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // Branch 1: Search
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                name: 'search',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SearchScreen()),
                routes: [
                  GoRoute(
                    path: 'detail/:tmdbId',
                    name: 'search-detail',
                    pageBuilder: (context, state) {
                      final tmdbId = int.parse(state.pathParameters['tmdbId']!);
                      final content = state.extra as Content?;
                      return MaterialPage(
                        child: MovieDetailScreen(
                          tmdbId: tmdbId,
                          initialContent: content,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Branch 2: AI Recommendations
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/for-you',
                name: 'for-you',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: RecommendationsScreen()),
                routes: [
                  GoRoute(
                    path: 'detail/:tmdbId',
                    name: 'recommendation-detail',
                    pageBuilder: (context, state) {
                      final tmdbId = int.parse(state.pathParameters['tmdbId']!);
                      final content = state.extra as Content?;
                      return MaterialPage(
                        child: MovieDetailScreen(
                          tmdbId: tmdbId,
                          initialContent: content,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Branch 3: Progress
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/progress',
                name: 'progress-main',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: WatchingScreen()),
                routes: [
                  GoRoute(
                    path: 'detail/:tmdbId',
                    name: 'progress-detail',
                    pageBuilder: (context, state) {
                      final tmdbId = int.parse(state.pathParameters['tmdbId']!);
                      final content = state.extra as Content?;
                      return MaterialPage(
                        child: MovieDetailScreen(
                          tmdbId: tmdbId,
                          initialContent: content,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Branch 4: Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ProfileScreen()),
                routes: [
                  GoRoute(
                    path: 'detail/:tmdbId',
                    name: 'profile-detail',
                    pageBuilder: (context, state) {
                      final tmdbId = int.parse(state.pathParameters['tmdbId']!);
                      final content = state.extra as Content?;
                      return MaterialPage(
                        child: MovieDetailScreen(
                          tmdbId: tmdbId,
                          initialContent: content,
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'watched',
                    name: 'watched',
                    pageBuilder: (context, state) =>
                        const NoTransitionPage(child: WatchedScreen()),
                  ),
                  GoRoute(
                    path: 'watching',
                    name: 'watching',
                    pageBuilder: (context, state) =>
                        const NoTransitionPage(child: WatchingScreen()),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Person detail route (accessible from anywhere)
      GoRoute(
        path: '/person/:personId',
        name: 'person-detail',
        pageBuilder: (context, state) {
          final personId = int.parse(state.pathParameters['personId']!);
          final person = state.extra as Person?;
          return MaterialPage(
            child: PersonDetailScreen(
              personId: personId,
              initialPerson: person,
            ),
          );
        },
      ),
    ],

    // Error handling
    errorPageBuilder: (context, state) => MaterialPage(
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: ${state.error}'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    ),

    // Route debugging
    debugLogDiagnostics: true,
  );

  static void goNamed(
    BuildContext context,
    String name, {
    Map<String, String> pathParameters = const {},
    Map<String, dynamic> queryParameters = const {},
    Object? extra,
  }) {
    context.goNamed(
      name,
      pathParameters: pathParameters,
      queryParameters: queryParameters,
      extra: extra,
    );
  }

  static void push(BuildContext context, String location, {Object? extra}) {
    context.pushNamed(location, extra: extra);
  }
}
