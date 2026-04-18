#!/usr/bin/env node
import pkg from 'pg';
const { Client } = pkg;
import dotenv from 'dotenv';

dotenv.config({ path: '.env.local' });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY;

if (!supabaseUrl || !supabaseServiceKey) {
  console.error('❌ Missing SUPABASE_URL or SUPABASE_SERVICE_KEY in .env.local');
  process.exit(1);
}

// Extract connection details from Supabase URL
const urlObj = new URL(supabaseUrl);
const connectionString = `postgresql://postgres:${supabaseServiceKey}@${urlObj.hostname}:5432/postgres?sslmode=require`;

async function fixLogsConstraint() {
  const client = new Client({ connectionString });
  
  try {
    console.log('🔧 Connecting to Supabase database...');
    await client.connect();
    console.log('✓ Connected');

    console.log('🔧 Fixing logs table constraint...');

    // Drop the old constraint
    await client.query(`
      ALTER TABLE public.logs DROP CONSTRAINT IF EXISTS logs_user_id_content_id_rewatch_count_key;
    `);
    console.log('✓ Dropped old constraint');

    // Create the new constraint
    await client.query(`
      ALTER TABLE public.logs ADD CONSTRAINT logs_user_id_tmdb_id_media_type_key UNIQUE (user_id, tmdb_id, media_type);
    `);
    console.log('✓ Created new constraint on (user_id, tmdb_id, media_type)');

    console.log('\n✅ Migration completed successfully!');
  } catch (error) {
    console.error('❌ Migration failed:', error);
    process.exit(1);
  } finally {
    await client.end();
  }
}

fixLogsConstraint();
