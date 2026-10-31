/**
 * Cap Algorithm for Poll Results
 *
 * Applies a "gold cap" to prevent any single person from winning too many categories.
 * When someone exceeds the cap, their wins are redistributed to runners-up or marked as "kept"
 * if no eligible runner-up exists.
 */

export interface Nominee {
  id: string;
  name: string;
  votes: number;
}

export interface RawAward {
  gold: Nominee[];
  silver: Nominee[];
  bronze: Nominee[];
}

export interface FinalAward {
  gold: Nominee[];
  silver: Nominee[];
  bronze: Nominee[];
  reason?: string;
}

export interface CategoryResult {
  categoryId: string;
  title: string;
  position: number;
  raw: RawAward;
  final: FinalAward;
  changed: boolean;
  kept: boolean;
}

export interface CapSettings {
  goldCap: number;
  minVotesForAward: number;
  capFallback: 'keep_winner' | 'no_award';
  tieRule: 'share_gold';
}

export interface CategoryInput {
  categoryId: string;
  title: string;
  position: number;
  nominees: Array<{ id: string; name: string; votes: number }>;
}

interface RankedCategory extends CategoryInput {
  groups: Nominee[][];
  margin: number;
  rawVotes: number;
}

/**
 * Ranks nominees into groups by vote count
 * Each group contains nominees with the same vote count (ties)
 */
function rankIntoGroups(nominees: Nominee[]): Nominee[][] {
  const sorted = [...nominees].sort((a, b) => b.votes - a.votes);
  const groups: Nominee[][] = [];
  let currentVotes = -1;

  for (const n of sorted) {
    if (n.votes !== currentVotes) {
      groups.push([]);
      currentVotes = n.votes;
    }
    groups[groups.length - 1].push(n);
  }

  return groups;
}

/**
 * Extracts gold/silver/bronze from ranked groups
 */
function extractAwards(groups: Nominee[][]): RawAward {
  return {
    gold: groups[0] || [],
    silver: groups[1] || [],
    bronze: groups[2] || [],
  };
}

/**
 * Apply the gold cap algorithm to poll results
 *
 * Algorithm:
 * 1. Rank each category's nominees into groups (ties share a group)
 * 2. Skip categories where top votes < minVotesForAward
 * 3. Sort categories by margin (biggest gap between 1st and 2nd), then by raw votes
 * 4. Process in order: find first eligible group (all members under cap)
 * 5. If no eligible group, apply fallback (keep_winner or no_award)
 *
 * @param categories - Array of categories with their nominees and vote counts
 * @param settings - Cap settings
 * @returns Array of category results with raw and final awards
 */
export function applyCap(
  categories: CategoryInput[],
  settings: CapSettings
): CategoryResult[] {
  // 1. Rank into groups per category
  const ranked: RankedCategory[] = categories.map((cat) => {
    const groups = rankIntoGroups(cat.nominees);
    const margin =
      groups.length > 1
        ? groups[0][0].votes - groups[1][0].votes
        : groups[0]?.[0]?.votes ?? 0;

    return {
      ...cat,
      groups,
      margin,
      rawVotes: groups[0]?.[0]?.votes ?? 0,
    };
  });

  // 3. Sort by margin (biggest first), then by raw votes (tiebreaker)
  const ordered = [...ranked].sort(
    (a, b) => b.margin - a.margin || b.rawVotes - a.rawVotes
  );

  const goldCounts: Record<string, number> = {};
  const keptCounts: Record<string, number> = {};
  const results: CategoryResult[] = [];

  for (const cat of ordered) {
    const rawAward = extractAwards(cat.groups);

    // 2. Skip under minimum votes
    if ((cat.groups[0]?.[0]?.votes ?? 0) < settings.minVotesForAward) {
      results.push({
        categoryId: cat.categoryId,
        title: cat.title,
        position: cat.position,
        raw: rawAward,
        final: {
          gold: [],
          silver: [],
          bronze: [],
          reason: 'Under minimum votes',
        },
        changed: true,
        kept: false,
      });
      continue;
    }

    // 4. Find eligible group (all members under cap)
    let awarded: Nominee[] | null = null;
    let awardedLevel = 0;

    for (let i = 0; i < cat.groups.length; i++) {
      const group = cat.groups[i];
      const allUnderCap = group.every(
        (n) => (goldCounts[n.id] || 0) < settings.goldCap
      );
      if (allUnderCap) {
        awarded = group;
        awardedLevel = i;
        break;
      }
    }

    // 5. Apply fallback if no eligible group
    let kept = false;
    if (!awarded && cat.groups[0]) {
      if (settings.capFallback === 'keep_winner') {
        awarded = cat.groups[0];
        kept = true;
      }
      // 'no_award' fallback: awarded stays null
    }

    // Update counts
    if (awarded) {
      for (const n of awarded) {
        if (kept) {
          keptCounts[n.id] = (keptCounts[n.id] || 0) + 1;
        } else {
          goldCounts[n.id] = (goldCounts[n.id] || 0) + 1;
        }
      }
    }

    // Build final award
    let finalAward: FinalAward;
    if (!awarded) {
      // No award given
      finalAward = {
        gold: [],
        silver: rawAward.gold, // Original winners become silver
        bronze: rawAward.silver,
        reason: 'No eligible winner (cap applied)',
      };
    } else if (awardedLevel === 0) {
      // Normal case: first group wins
      finalAward = {
        gold: awarded,
        silver: rawAward.silver,
        bronze: rawAward.bronze,
        reason: kept ? 'Kept: no eligible runner-up' : undefined,
      };
    } else {
      // Cap applied: lower group wins
      finalAward = {
        gold: awarded,
        silver: cat.groups[0] || [], // Original winners become silver
        bronze: cat.groups[1] || [],
        reason: `Cap applied: runner-up from group ${awardedLevel + 1} wins`,
      };
    }

    results.push({
      categoryId: cat.categoryId,
      title: cat.title,
      position: cat.position,
      raw: rawAward,
      final: finalAward,
      changed: awardedLevel > 0 || kept || !awarded,
      kept,
    });
  }

  // Re-sort by original position for output
  return results.sort((a, b) => a.position - b.position);
}

/**
 * Generate summary statistics for cap application
 */
export function getCapSummary(
  results: CategoryResult[],
  settings: CapSettings
): {
  totalCategories: number;
  awardsGiven: number;
  capApplied: number;
  kept: number;
  noAward: number;
  goldCounts: Record<string, number>;
  memberNames: Record<string, string>;
} {
  const goldCounts: Record<string, number> = {};
  const memberNames: Record<string, string> = {};
  let awardsGiven = 0;
  let capApplied = 0;
  let kept = 0;
  let noAward = 0;

  for (const result of results) {
    if (result.final.gold.length > 0) {
      awardsGiven++;
      for (const winner of result.final.gold) {
        goldCounts[winner.id] = (goldCounts[winner.id] || 0) + 1;
        memberNames[winner.id] = winner.name;
      }
    } else {
      noAward++;
    }

    if (result.changed && result.final.gold.length > 0) {
      if (result.kept) {
        kept++;
      } else {
        capApplied++;
      }
    }
  }

  return {
    totalCategories: results.length,
    awardsGiven,
    capApplied,
    kept,
    noAward,
    goldCounts,
    memberNames,
  };
}

/**
 * Convert tally from database format to CategoryInput format
 */
export function tallyToCategories(
  tally: Array<{
    category_id: string;
    title: string;
    position: number;
    nominees: Array<{
      nominee_id: string;
      display_name: string;
      handle: string;
      votes: number;
    }>;
  }>
): CategoryInput[] {
  return tally.map((cat) => ({
    categoryId: cat.category_id,
    title: cat.title,
    position: cat.position,
    nominees: cat.nominees.map((n) => ({
      id: n.nominee_id,
      name: n.display_name || n.handle,
      votes: n.votes,
    })),
  }));
}

/**
 * Convert CategoryResult to data.json format for publishing
 */
export function resultsToDataJson(
  results: CategoryResult[],
  pollSlug: string,
  pollTitle: string,
  pollYear: number
): {
  poll: { slug: string; title: string; year: number };
  categories: Array<{
    slug: string;
    title: string;
    gold: { names: string[]; votes: number } | null;
    silver:
      | { names: string[]; votes: number }
      | { tie: number; votes: number }
      | 'singles'
      | null;
    bronze:
      | { names: string[]; votes: number }
      | { tie: number; votes: number }
      | 'singles'
      | null;
  }>;
} {
  const categories = results.map((r) => {
    // Generate slug from title
    const slug = r.title
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');

    // Format gold
    const gold =
      r.final.gold.length > 0
        ? {
            names: r.final.gold.map((n) => n.name),
            votes: r.final.gold[0].votes,
          }
        : null;

    // Format silver
    let silver:
      | { names: string[]; votes: number }
      | { tie: number; votes: number }
      | 'singles'
      | null = null;
    if (r.final.silver.length > 0) {
      const silverVotes = r.final.silver[0].votes;
      if (r.final.silver.length > 3 && silverVotes === 1) {
        silver = { tie: r.final.silver.length, votes: 1 };
      } else {
        silver = {
          names: r.final.silver.map((n) => n.name),
          votes: silverVotes,
        };
      }
    }

    // Format bronze
    let bronze:
      | { names: string[]; votes: number }
      | { tie: number; votes: number }
      | 'singles'
      | null = null;
    if (r.final.bronze.length > 0) {
      const bronzeVotes = r.final.bronze[0].votes;
      if (r.final.bronze.length > 3 && bronzeVotes === 1) {
        bronze = { tie: r.final.bronze.length, votes: 1 };
      } else {
        bronze = {
          names: r.final.bronze.map((n) => n.name),
          votes: bronzeVotes,
        };
      }
    }

    return { slug, title: r.title, gold, silver, bronze };
  });

  return {
    poll: { slug: pollSlug, title: pollTitle, year: pollYear },
    categories,
  };
}
