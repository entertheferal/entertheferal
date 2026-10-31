#!/usr/bin/env node
/**
 * Validate poll data.json for Halloween Horror Movie Poll
 * Usage: node scripts/validate-poll.mjs [path/to/data.json]
 */

import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

const defaultPath = resolve(__dirname, '../poll/halloween-2026/data.json');
const dataPath = process.argv[2] ? resolve(process.argv[2]) : defaultPath;

if (!existsSync(dataPath)) {
  console.error(`Error: File not found: ${dataPath}`);
  process.exit(1);
}

let data;
try {
  data = JSON.parse(readFileSync(dataPath, 'utf8'));
} catch (e) {
  console.error(`Error: Invalid JSON in ${dataPath}`);
  console.error(e.message);
  process.exit(1);
}

const errors = [];
const warnings = [];

// Check poll metadata
if (!data.poll) {
  errors.push('Missing "poll" object');
} else {
  if (!data.poll.slug) errors.push('Missing poll.slug');
  if (!data.poll.title) errors.push('Missing poll.title');
  if (!data.poll.year || !Number.isInteger(data.poll.year)) errors.push('Invalid or missing poll.year');
}

// Check categories
if (!Array.isArray(data.categories)) {
  errors.push('Missing or invalid "categories" array');
} else {
  const slugs = new Set();
  const slugPattern = /^[a-z0-9-]+$/;

  data.categories.forEach((cat, i) => {
    const prefix = `Category ${i + 1}`;

    // Check slug
    if (!cat.slug) {
      errors.push(`${prefix}: Missing slug`);
    } else if (!slugPattern.test(cat.slug)) {
      errors.push(`${prefix}: Invalid slug "${cat.slug}" (must be lowercase letters, numbers, hyphens only)`);
    } else if (slugs.has(cat.slug)) {
      errors.push(`${prefix}: Duplicate slug "${cat.slug}"`);
    } else {
      slugs.add(cat.slug);
    }

    // Check title
    if (!cat.title) {
      errors.push(`${prefix}: Missing title`);
    }

    // Check gold
    if (!cat.gold) {
      errors.push(`${prefix}: Missing gold`);
    } else {
      if (!Array.isArray(cat.gold.names) || cat.gold.names.length === 0) {
        errors.push(`${prefix}: Gold must have non-empty names array`);
      }
      if (!Number.isInteger(cat.gold.votes) || cat.gold.votes < 1) {
        errors.push(`${prefix}: Gold votes must be positive integer`);
      }
    }

    // Check silver (can be object with names/votes, object with tie/votes, "singles", or null)
    if (cat.silver !== null && cat.silver !== 'singles') {
      if (typeof cat.silver === 'object') {
        if (cat.silver.tie) {
          if (!Number.isInteger(cat.silver.tie) || cat.silver.tie < 2) {
            errors.push(`${prefix}: Silver tie must be integer >= 2`);
          }
          if (!Number.isInteger(cat.silver.votes) || cat.silver.votes < 1) {
            errors.push(`${prefix}: Silver tie votes must be positive integer`);
          }
        } else if (cat.silver.names) {
          if (!Array.isArray(cat.silver.names) || cat.silver.names.length === 0) {
            errors.push(`${prefix}: Silver names must be non-empty array`);
          }
          if (!Number.isInteger(cat.silver.votes) || cat.silver.votes < 1) {
            errors.push(`${prefix}: Silver votes must be positive integer`);
          }
        } else {
          errors.push(`${prefix}: Silver must have names or tie property`);
        }
      } else {
        errors.push(`${prefix}: Invalid silver format`);
      }
    }

    // Check bronze (same rules as silver)
    if (cat.bronze !== null && cat.bronze !== 'singles') {
      if (typeof cat.bronze === 'object') {
        if (cat.bronze.tie) {
          if (!Number.isInteger(cat.bronze.tie) || cat.bronze.tie < 2) {
            errors.push(`${prefix}: Bronze tie must be integer >= 2`);
          }
          if (!Number.isInteger(cat.bronze.votes) || cat.bronze.votes < 1) {
            errors.push(`${prefix}: Bronze tie votes must be positive integer`);
          }
        } else if (cat.bronze.names) {
          if (!Array.isArray(cat.bronze.names) || cat.bronze.names.length === 0) {
            errors.push(`${prefix}: Bronze names must be non-empty array`);
          }
          if (!Number.isInteger(cat.bronze.votes) || cat.bronze.votes < 1) {
            errors.push(`${prefix}: Bronze votes must be positive integer`);
          }
        } else {
          errors.push(`${prefix}: Bronze must have names or tie property`);
        }
      } else {
        errors.push(`${prefix}: Invalid bronze format`);
      }
    }
  });

  // Stats
  console.log(`\nValidating: ${dataPath}`);
  console.log(`Categories: ${data.categories.length}`);
  console.log(`Unique slugs: ${slugs.size}`);
}

// Output results
if (warnings.length > 0) {
  console.log('\nWarnings:');
  warnings.forEach(w => console.log(`  - ${w}`));
}

if (errors.length > 0) {
  console.log('\nErrors:');
  errors.forEach(e => console.log(`  - ${e}`));
  console.log(`\n${errors.length} error(s) found.`);
  process.exit(1);
}

console.log('\nValidation passed!');
process.exit(0);
