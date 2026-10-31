#!/usr/bin/env node
/**
 * Cleanup Orphan Avatars
 *
 * This script finds and removes avatar files in Supabase Storage
 * that no longer have a corresponding profile (e.g., after account deletion
 * where the storage delete failed).
 *
 * Usage:
 *   SUPABASE_URL=xxx SUPABASE_SERVICE_KEY=xxx node cleanup-orphan-avatars.js
 *
 * Or with .env file:
 *   node -r dotenv/config cleanup-orphan-avatars.js
 *
 * NOTE: This requires the service_role key, not the anon key.
 * Never expose the service_role key in frontend code.
 */

const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('Error: SUPABASE_URL and SUPABASE_SERVICE_KEY environment variables required');
  process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false }
});

async function main() {
  console.log('Fetching avatar files...');

  // List all files in avatars bucket
  const { data: files, error: listError } = await supabase.storage
    .from('avatars')
    .list('', { limit: 1000 });

  if (listError) {
    console.error('Error listing files:', listError.message);
    process.exit(1);
  }

  if (!files || files.length === 0) {
    console.log('No avatar files found.');
    return;
  }

  // Get all profile IDs
  const { data: profiles, error: profileError } = await supabase
    .from('profiles')
    .select('id');

  if (profileError) {
    console.error('Error fetching profiles:', profileError.message);
    process.exit(1);
  }

  const profileIds = new Set(profiles.map(p => p.id));

  // Find orphans (files in folders that don't match a profile ID)
  const orphans = [];

  for (const folder of files) {
    if (folder.id && !profileIds.has(folder.name)) {
      // This is a folder (user ID) without a profile
      // List files in the folder
      const { data: folderFiles } = await supabase.storage
        .from('avatars')
        .list(folder.name);

      if (folderFiles && folderFiles.length > 0) {
        for (const file of folderFiles) {
          orphans.push(`${folder.name}/${file.name}`);
        }
      }
    }
  }

  if (orphans.length === 0) {
    console.log('No orphan avatars found.');
    return;
  }

  console.log(`Found ${orphans.length} orphan avatar(s):`);
  orphans.forEach(path => console.log(`  - ${path}`));

  // Delete orphans
  console.log('\nDeleting orphans...');

  const { error: deleteError } = await supabase.storage
    .from('avatars')
    .remove(orphans);

  if (deleteError) {
    console.error('Error deleting orphans:', deleteError.message);
    process.exit(1);
  }

  console.log('Done! Deleted', orphans.length, 'orphan file(s).');
}

main().catch(err => {
  console.error('Unexpected error:', err);
  process.exit(1);
});
