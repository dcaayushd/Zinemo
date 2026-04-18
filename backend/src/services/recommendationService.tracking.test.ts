import { trackRecommendationBehaviorEvent } from './recommendationService';

describe('Recommendation behavior tracking', () => {
  it('persists behavior events to activity table with mode metadata', async () => {
    const insert = jest.fn().mockResolvedValue({ error: null });
    const mockClient = {
      from: jest.fn(() => ({
        insert,
      })),
    };

    const ok = await trackRecommendationBehaviorEvent(
      'user-123',
      'recommendation_foryou_served',
      {
        genre_filter: 'Drama',
        result_count: 10,
      },
      mockClient,
    );

    expect(ok).toBe(true);
    expect(mockClient.from).toHaveBeenCalledWith('activity');
    expect(insert).toHaveBeenCalledTimes(1);

    const payload = insert.mock.calls[0][0] as {
      user_id: string;
      activity_type: string;
      metadata: Record<string, unknown>;
      created_at: string;
    };

    expect(payload.user_id).toBe('user-123');
    expect(payload.activity_type).toBe('recommendation_foryou_served');
    expect(payload.metadata.genre_filter).toBe('Drama');
    expect(payload.metadata.result_count).toBe(10);
    expect(payload.metadata).toHaveProperty('recommendation_mode');
    expect(typeof payload.created_at).toBe('string');
  });

  it('returns false when persistence fails', async () => {
    const insert = jest.fn().mockResolvedValue({
      error: { message: 'insert failed' },
    });
    const mockClient = {
      from: jest.fn(() => ({
        insert,
      })),
    };

    const ok = await trackRecommendationBehaviorEvent(
      'user-123',
      'recommendation_similar_served',
      { tmdb_id: 55 },
      mockClient,
    );

    expect(ok).toBe(false);
    expect(mockClient.from).toHaveBeenCalledWith('activity');
    expect(insert).toHaveBeenCalledTimes(1);
  });
});
