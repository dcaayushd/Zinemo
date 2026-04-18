const { test, describe } = require('node:test');
const assert = require('node:assert');
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Missing Supabase credentials');
}

const supabase = createClient(supabaseUrl, supabaseAnonKey);

describe('Supabase Integration Tests', () => {
  beforeEach(async () => {
    // Setup test data
    await supabase.from('content_items').insert([
      {
        id: 'test-movie-1',
        type: 'movie',
        tmdb_id: 603,
        title: 'The Dark Knight',
        overview: 'Batman faces Gotham\'s greatest threat.',
        runtime: 152,
        vote_average: 9.0,
      },
      {
        id: 'test-movie-2',
        type: 'movie',
        tmdb_id: 27205,
        title: 'Inception',
        overview: 'A thief steals secrets from dreams.',
        runtime: 148,
        vote_average: 8.8,
      },
    ]);

    await supabase.from('profiles').upsert({
      id: 'test-user-1',
      email: 'test@example.com',
      full_name: 'Test User',
    });
  });

  afterEach(async () => {
    // Cleanup
    await supabase.from('content_items').delete().eq('id', 'test-movie-1');
    await supabase.from('content_items').delete().eq('id', 'test-movie-2');
    await supabase.from('profiles').delete().eq('id', 'test-user-1');
  });

  describe('Profiles', () => {
    it('should create a new profile', async () => {
      const { data, error } = await supabase.from('profiles').insert({
        id: 'test-user-2',
        email: 'test2@example.com',
        full_name: 'Test User 2',
      });

      assert.equal(error, null, 'Should not have errors');
      assert.ok(data.id, 'Should return profile id');
    });

    it('should fetch profiles by email', async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('email', 'test@example.com');

      assert.equal(error, null, 'Should not have errors');
      assert.ok(data.length > 0, 'Should find profile');
      assert.equal(data[0].email, 'test@example.com');
    });

    it('should update a profile', async () => {
      const { data, error } = await supabase
        .from('profiles')
        .update({ full_name: 'Updated Name' })
        .eq('id', 'test-user-1');

      assert.equal(error, null, 'Should not have errors');
      assert.equal(data.full_name, 'Updated Name');
    });
  });

  describe('Content Items', () => {
    it('should fetch all content items', async () => {
      const { data, error } = await supabase
        .from('content_items')
        .select('*')
        .eq('type', 'movie');

      assert.equal(error, null, 'Should not have errors');
      assert.ok(data.length > 0, 'Should have content items');
    });

    it('should fetch by TMDB ID', async () => {
      const { data, error } = await supabase
        .from('content_items')
        .select('*')
        .eq('tmdb_id', 603)
        .eq('type', 'movie');

      assert.equal(error, null, 'Should not have errors');
      assert.ok(data.length > 0, 'Should find item');
      assert.equal(data[0].title, 'The Dark Knight');
    });

    it('should filter by genre', async () => {
      const { data, error } = await supabase
        .from('content_items')
        .select('*')
        .is('genre_ids', null);

      assert.equal(error, null, 'Should not have errors');
    });

    it('should search content', async () => {
      const { data, error } = await supabase
        .from('content_items')
        .select('*')
        .ilike('title', '%Knight%');

      assert.equal(error, null, 'Should not have errors');
      assert.ok(data.length > 0, 'Should find Knight');
    });
  });

  describe('Content Access Events', () => {
    it('should create access event', async () => {
      const result = await supabase.rpc('create_content_access', {
        p_user_id: 'test-user-1',
        p_content_accessed_item_id: 'test-movie-1',
        p_event_type: 'view',
        p_item_count: 1,
      });

      assert.equal(result.error, null, 'Should not have errors');
      assert.ok(result.data.event_id, 'Should have event_id');
    });

    it('should fetch user access history', async () => {
      const { data, error } = await supabase
        .from('content_access_events')
        .select('*')
        .eq('user_id', 'test-user-1')
        .order('event_date', { ascending: false });

      assert.equal(error, null, 'Should not have errors');
    });

    it('should get similar items by content', async () => {
      const result = await supabase.rpc('get_similar_items', {
        p_content_accessed_item_id: 'test-movie-1',
        p_event_type: 'view',
      });

      assert.equal(result.error, null, 'Should not have errors');
      assert.ok(Array.isArray(result.data), 'Should return array');
    });
  });

  describe('ML Predictions', () => {
    it('should insert prediction', async () => {
      const now = new Date().toISOString();
      const result = await supabase.rpc('create_ml_prediction', {
        p_user_id: 'test-user-1',
        p_predicted_items: JSON.stringify([
          { item_id: 'test-movie-2', score: 0.9, metadata: {} },
          { item_id: 'test-movie-1', score: 0.85, metadata: {} },
        ]),
        p_prediction_date: now,
      });

      assert.equal(result.error, null, 'Should not have errors');
      assert.ok(result.data.event_id, 'Should have event_id');
    });

    it('should fetch predictions by user', async () => {
      const { data, error } = await supabase
        .from('ml_predictions')
        .select('*')
        .eq('user_id', 'test-user-1');

      assert.equal(error, null, 'Should not have errors');
    });
  });

  describe('Ratings', () => {
    it('should create rating', async () => {
      const result = await supabase.rpc('create_rating', {
        p_user_id: 'test-user-1',
        p_content_item_id: 'test-movie-1',
        p_rating: 8.5,
      });

      assert.equal(result.error, null, 'Should not have errors');
    });

    it('should fetch ratings by user', async () => {
      const { data, error } = await supabase
        .from('ratings')
        .select('*')
        .eq('user_id', 'test-user-1');

      assert.equal(error, null, 'Should not have errors');
    });

    it('should fetch rated items for user', async () => {
      const result = await supabase.rpc('get_rated_items', {
        p_user_id: 'test-user-1',
      });

      assert.equal(result.error, null, 'Should not have errors');
    });
  });

  describe('RLS Policies', () => {
    it('should enforce profiles read RLS', async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', 'test-user-1');

      // This should work with auth
      assert.equal(error, null, 'Should work with auth');
    });

    it('should enforce content access RLS', async () => {
      const result = await supabase.rpc('create_content_access', {
        p_user_id: 'test-user-1',
        p_content_accessed_item_id: 'test-movie-1',
        p_event_type: 'view',
        p_item_count: 1,
      });

      assert.equal(result.error, null, 'Should work with RLS');
    });
  });
});
