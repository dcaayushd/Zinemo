import authRouter from '../routes/auth';
import logsRouter from '../routes/logs';
import { getRecommendationsForUser } from '../services/recommendationService';
import * as supabaseConfig from '../config/supabase';
import * as retrainWorker from '../workers/retrainWorker';
import { createMockResponse, getRouteHandler } from '../testUtils/routerTestUtils';

type SmokeState = {
  profiles: Record<string, { id: string; preferences: Record<string, unknown> }>;
  logs: Array<Record<string, unknown>>;
  activity: Array<Record<string, unknown>>;
};

function createSmokeClient(state: SmokeState) {
  return {
    from(table: string) {
      if (table === 'profiles') {
        return {
          update(updates: Record<string, unknown>) {
            return {
              eq(field: string, value: string) {
                return {
                  select() {
                    return {
                      async single() {
                        const current = state.profiles[value] ?? {
                          id: value,
                          preferences: {},
                        };
                        const merged = {
                          ...current,
                          ...updates,
                          preferences: (updates.preferences as Record<string, unknown>) ??
                              current.preferences,
                        };
                        state.profiles[value] = merged;

                        return {
                          data: {
                            id: merged.id,
                            preferences: merged.preferences,
                          },
                          error: null,
                        };
                      },
                    };
                  },
                };
              },
            };
          },
        };
      }

      if (table === 'content') {
        return {
          select() {
            return {
              eq() {
                return {
                  eq() {
                    return {
                      async single() {
                        return {
                          data: { id: 99 },
                          error: null,
                        };
                      },
                    };
                  },
                };
              },
            };
          },
        };
      }

      if (table === 'logs') {
        return {
          insert(payload: Record<string, unknown>) {
            return {
              select() {
                return {
                  async single() {
                    const row = {
                      id: `log-${state.logs.length + 1}`,
                      ...payload,
                    };
                    state.logs.push(row);
                    return {
                      data: row,
                      error: null,
                    };
                  },
                };
              },
            };
          },
        };
      }

      if (table === 'activity') {
        return {
          async insert(payload: Record<string, unknown>) {
            state.activity.push(payload);
            return { error: null };
          },
        };
      }

      throw new Error(`Unexpected table: ${table}`);
    },
  };
}

describe('Smoke loops', () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('runs onboarding -> for-you genre fetch -> add log -> recommendation refresh', async () => {
    const state: SmokeState = {
      profiles: {},
      logs: [],
      activity: [],
    };

    const client = createSmokeClient(state);
    jest.spyOn(supabaseConfig, 'requireSupabase').mockReturnValue(client as never);
    jest.spyOn(retrainWorker, 'onNewLog').mockResolvedValue();

    let recommendationCallCount = 0;
    const fetchSpy = jest
      .spyOn(globalThis, 'fetch')
      .mockImplementation(async () => {
        recommendationCallCount += 1;
        const payload = recommendationCallCount === 1
          ? [
              {
                tmdb_id: 101,
                media_type: 'movie',
                score: 0.93,
                reason: 'Genre affinity',
                algorithm: 'lightfm',
              },
            ]
          : [
              {
                tmdb_id: 202,
                media_type: 'movie',
                score: 0.97,
                reason: 'Refreshed after new signal',
                algorithm: 'hybrid',
              },
            ];

        return new Response(JSON.stringify(payload), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      });

    const onboardingHandler = getRouteHandler(authRouter, 'post', '/preferences');
    const onboardingRes = createMockResponse();

    await onboardingHandler(
      {
        user: { id: 'user-1' },
        body: {
          genres: ['Drama', 'Sci-Fi'],
          initialRatings: [{ tmdb_id: 101, rating: 4.5 }],
        },
      },
      onboardingRes,
    );

    expect(onboardingRes.statusCode).toBe(200);
    expect(state.profiles['user-1']?.preferences).toEqual({
      genres: ['Drama', 'Sci-Fi'],
      initial_ratings: [{ tmdb_id: 101, rating: 4.5 }],
      updated_from: 'onboarding',
    });

    const beforeRefresh = await getRecommendationsForUser('user-1', 'Drama', 20);
    expect(beforeRefresh).toHaveLength(1);
    expect(beforeRefresh[0]?.tmdb_id).toBe(101);

    const addLogHandler = getRouteHandler(logsRouter, 'post', '/');
    const addLogRes = createMockResponse();

    await addLogHandler(
      {
        user: { id: 'user-1' },
        body: {
          tmdbId: 101,
          mediaType: 'movie',
          status: 'watchlist',
          rating: 4.5,
          liked: true,
          rewatch: false,
        },
      },
      addLogRes,
    );

    expect(addLogRes.statusCode).toBe(200);
    expect(state.logs).toHaveLength(1);

    const afterRefresh = await getRecommendationsForUser('user-1', 'Drama', 20);
    expect(afterRefresh).toHaveLength(1);
    expect(afterRefresh[0]?.tmdb_id).toBe(202);

    const eventTypes = state.activity.map((entry) => entry.activity_type);
    expect(eventTypes).toContain('recommendation_foryou_served');
    expect(eventTypes).toContain('recommendation_log_created');
    expect(eventTypes).toContain('recommendation_add_rating');
    expect(eventTypes).toContain('recommendation_add_bookmark');

    fetchSpy.mockRestore();
  });
});
