#!/usr/bin/env node
/**
 * Build polls.json index from published poll data.json files.
 *
 * Usage: npm run polls-index
 *
 * Reads each poll's data.json and computes:
 * - awards: number of categories
 * - peopleWithGold: number of unique people who won at least one gold
 */

import { readFileSync, writeFileSync, readdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const POLL_DIR = join(__dirname, '..', 'poll');
const OUTPUT_FILE = join(POLL_DIR, 'polls.json');

// Poll metadata (manually maintained - add new polls here)
const POLL_META = {
  'halloween-2026': {
    month: 'oct 2026',
    line: 'who survives the horror movie and who gets us all killed.',
    art: 'loop'
  }
};

function computeStats(dataJson) {
  const categories = dataJson.categories || [];
  const awards = categories.length;

  // Collect all unique gold winners
  const goldWinners = new Set();
  for (const cat of categories) {
    if (cat.gold?.names) {
      for (const name of cat.gold.names) {
        goldWinners.add(name);
      }
    }
  }

  return {
    awards,
    peopleWithGold: goldWinners.size
  };
}

function buildIndex() {
  const polls = [];
  const errors = [];

  // Find all poll directories with data.json
  const entries = readdirSync(POLL_DIR, { withFileTypes: true });

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const slug = entry.name;
    const dataPath = join(POLL_DIR, slug, 'data.json');

    if (!existsSync(dataPath)) continue;

    // Read and parse data.json
    let data;
    try {
      const raw = readFileSync(dataPath, 'utf8');
      data = JSON.parse(raw);
    } catch (err) {
      errors.push(`${slug}: Failed to parse data.json - ${err.message}`);
      continue;
    }

    // Validate required fields
    if (!data.poll?.slug || !data.poll?.title) {
      errors.push(`${slug}: data.json missing poll.slug or poll.title`);
      continue;
    }

    if (!Array.isArray(data.categories)) {
      errors.push(`${slug}: data.json missing categories array`);
      continue;
    }

    // Get metadata
    const meta = POLL_META[slug];
    if (!meta) {
      errors.push(`${slug}: No metadata in POLL_META - add it to the script`);
      continue;
    }

    // Compute stats
    const stats = computeStats(data);

    polls.push({
      slug: data.poll.slug,
      title: data.poll.title,
      month: meta.month,
      line: meta.line,
      status: 'published',
      resultsUrl: `/poll/${slug}/`,
      art: meta.art,
      awards: stats.awards,
      peopleWithGold: stats.peopleWithGold
    });
  }

  // Sort by date (newest first) - for now just reverse alphabetical on slug
  polls.sort((a, b) => b.slug.localeCompare(a.slug));

  // Build output
  const output = {
    // current: null means "between polls" state
    // Set this manually or via admin when a poll is active
    current: null,
    polls
  };

  // Write output
  writeFileSync(OUTPUT_FILE, JSON.stringify(output, null, 2) + '\n');

  console.log(`Generated ${OUTPUT_FILE}`);
  console.log(`  ${polls.length} published poll(s)`);

  if (errors.length > 0) {
    console.error('\nErrors:');
    for (const err of errors) {
      console.error(`  - ${err}`);
    }
    process.exit(1);
  }
}

buildIndex();
