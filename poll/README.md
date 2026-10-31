# Poll System

This directory contains the full monthly poll system for the Feral Collective.

## Overview

The poll system supports a complete cycle:
1. **Join** - Members opt in to participate
2. **Ideas** - Participants suggest award categories
3. **Curate** - Admins review and accept ideas
4. **Vote** - Participants vote anonymously
5. **Close** - Admin closes voting and reviews results
6. **Publish** - Results go live with share cards

## Structure

```
poll/
├── index.html              # Poll hub page (this month + past polls)
├── polls.json              # Computed index of all published polls
├── hub-data.js             # Data access module for hub page
├── rules-data.js           # Poll settings for rules page
├── art/                    # Shared texture assets
├── icons/                  # Hand-drawn digit images (n0-n9.webp)
├── join/index.html         # Join the current poll
├── ideas/index.html        # Submit and upvote ideas
├── vote/index.html         # Voting interface
├── rules/index.html        # How the poll works (public)
├── template/
│   └── results.js          # Shared results rendering utilities
├── halloween-2026/         # Example poll instance
│   ├── index.html          # Responsive results page
│   ├── data.json           # Source of truth for results
│   ├── captions.json       # Share card captions
│   ├── art/                # Texture assets
│   ├── icons/              # Hand-drawn digit images
│   ├── share/              # Generated share cards (PNGs)
│   ├── c/<slug>/           # Category OG preview pages
│   └── p/<slug>/           # Personal OG pages
└── README.md

admin/
└── poll/
    ├── curate/index.html   # Accept/decline ideas, open voting
    └── close/index.html    # Close voting, preview & publish results

js/
├── poll.js                 # Poll frontend utilities

scripts/
├── lib/
│   └── cap-algorithm.ts    # Gold cap algorithm
├── validate-poll.mjs       # Validate data.json
└── make-share-cards.mjs    # Generate share card PNGs

supabase/
└── migrations/
    └── 20261030000000_polls.sql  # Database schema
```

## Database Tables

- **polls** - Poll configuration and status
- **poll_participants** - Who joined each poll
- **ideas** - Submitted category suggestions
- **idea_upvotes** - Community votes for ideas
- **categories** - Final ballot categories
- **ballots_cast** - Records that someone voted (not who they voted for)
- **votes** - Anonymous votes (no user link)
- **results** - Computed results after voting closes
- **audit_log** - Admin action history
- **share_opt_outs** - Members who opted out of share cards

## Three Hard Gates

The system enforces three critical gates:

1. **Voting cannot start until joining is closed and locked**
   - Prevents late joins during voting

2. **No results visible while voting is open**
   - No tallies, no counts, nothing - true anonymity

3. **Results public only after admin publishes**
   - Admin reviews cap effects before going live

## Cap Algorithm

To prevent one person from winning everything:

- Each person can win at most N gold medals (default: 3)
- Categories are processed by "margin" (biggest gap between 1st and 2nd)
- If winner is at cap, runner-up wins instead
- If no eligible runner-up, original winner is "kept" (marked specially)

See `scripts/lib/cap-algorithm.ts` for the implementation.

## Poll Lifecycle

### 1. Create Poll (Admin)

```sql
SELECT create_poll('november-2026', 'November Awards', 'Topic description');
```

Or via admin dashboard.

### 2. Open for Ideas

Admin transitions: `draft` → `ideas_open`

Members can:
- Join at `/poll/join/`
- Submit ideas at `/poll/ideas/`
- Upvote other ideas

### 3. Curate Ideas

Admin transitions: `ideas_open` → `curating`

At `/admin/poll/curate/`:
- Review ideas sorted by upvotes
- Accept, decline, or merge ideas
- Set joining deadline
- Categories are created from accepted ideas

### 4. Open Voting

Admin transitions: `curating` → `voting_open`

Requirements:
- Join window must be closed
- Minimum categories met (default: 12)
- Minimum participants met (default: 10)

All participants are locked. At `/poll/vote/`:
- Pick one person per category
- Can't vote for yourself
- Same person max N times (default: 3)
- Votes are completely anonymous

### 5. Close Voting

Admin transitions: `voting_open` → `closed`

At `/admin/poll/close/`:
- View raw tallies (admin only)
- See cap algorithm effects
- Preview final results
- Can reopen if needed

### 6. Publish Results

Admin transitions: `closed` → `published`

- Results become visible to everyone
- data.json is generated for the results page
- Share cards can be generated

## Settings

Default poll settings (can be customized per poll):

```json
{
  "votes_per_person_per_ballot": 3,
  "gold_cap": 3,
  "min_votes_for_award": 2,
  "max_categories": 20,
  "min_categories": 12,
  "min_participants": 10,
  "ideas_per_member": 3,
  "cap_fallback": "keep_winner",
  "tie_rule": "share_gold"
}
```

## Anonymous Voting

Votes are truly anonymous:

- The `votes` table has `ballot_token` but no `member_id`
- `ballots_cast` records THAT you voted, not HOW
- No query can link a member to their votes
- RLS blocks all direct access to votes table

Members get a `ballot_token` to edit their vote. If they lose it, they can't edit.

## Data Export & Delete

The system supports GDPR/CCPA:

**Export includes:**
- Poll participation
- Ideas submitted
- Upvotes given
- Dates ballots were cast (not content)

**Delete removes:**
- All ideas
- All upvotes
- Participation records
- Ballot records
- Published results: `nominee_id` becomes NULL ("a former member")

## Scripts

### Validate poll data

```bash
npm run validate-poll                    # Default: halloween-2026
npm run validate-poll path/to/data.json  # Custom path
```

### Generate share cards

```bash
npm run share-cards                      # Default poll
npm run share-cards --poll=november-2026 # Specific poll
```

Requires Playwright. Install with:
```bash
npm install
npx playwright install chromium
```

## Data Format

### data.json

```json
{
  "poll": {
    "slug": "november-2026",
    "title": "November Awards",
    "year": 2026
  },
  "categories": [
    {
      "slug": "category-slug",
      "title": "Category Title",
      "gold": { "names": ["Winner"], "votes": 10 },
      "silver": { "names": ["Second"], "votes": 5 },
      "bronze": { "names": ["Third"], "votes": 3 }
    }
  ]
}
```

### Silver/Bronze formats

- Named winners: `{ "names": ["Name1", "Name2"], "votes": N }`
- Tie: `{ "tie": 12, "votes": 1 }` (12-way tie, 1 vote each)
- Everyone else: `"singles"` (everyone got 1 vote)
- No result: `null`

## Privacy Notes

- Member names appear on results page and in share cards
- Share cards are public images once posted to social media
- Members can opt out of share cards after results publish
- Votes are anonymous - even admins can't see who voted for whom

## Hub Page

The `/poll/` landing page shows:

**This Month section:**
- Current poll with phase-appropriate UI
- Progress tracker (Join → Ideas → Voting → Results)
- Member status card (not joined, joined, voted)
- Action button based on state and login status

**Past Polls section:**
- Grid of published polls
- Hand-drawn digits showing awards count and gold winners
- "See results" links

### Data Access

The hub page uses `hub-data.js` to abstract data access:

```javascript
// Get current poll (or null if between polls)
const poll = await FeralPollHub.getCurrentPoll();

// Get all published polls with stats
const polls = await FeralPollHub.getPastPolls();

// Get phase key for state machine
const phase = FeralPollHub.getPhaseKey(poll.status);
// Returns: 'open', 'curating', 'voting', 'closed', 'results', 'none'
```

Today this reads `polls.json`. Later it can switch to Supabase.

### Build the Polls Index

After publishing a poll or updating metadata:

```bash
npm run polls-index
```

This reads each poll's `data.json` and computes:
- `awards`: number of categories
- `peopleWithGold`: number of unique gold winners

To add a new poll to the index, add its metadata to `scripts/build-polls-index.mjs`:

```javascript
const POLL_META = {
  'halloween-2026': {
    month: 'oct 2026',
    line: 'who survives the horror movie and who gets us all killed.',
    art: 'loop'
  },
  'november-2026': {
    month: 'nov 2026',
    line: 'theme description here.',
    art: 'drip'  // loop, drip, bold, or red
  }
};
```

### Mobile Layout

On phones (<760px), the page shows a two-tab bottom bar:
- "This month" tab
- "Past polls" tab

On desktop, both sections appear on one page.

## Rules Page

The `/poll/rules/` page explains how the poll works. It's a public page with no member data.

### Dynamic Numbers

All numbers come from poll settings via `rules-data.js`:

```javascript
var S = FeralRulesData.getSettings();
// S.votes_per_person_per_ballot = 3
// S.gold_cap = 3
// S.min_votes_for_award = 2
// S.max_categories = 20
```

When there's no active poll, defaults are shown and dates are hidden.

### Sections

1. **Hero** - Jump links to each section
2. **How it works** - 6-step timeline with dates
3. **Fair play** - Rulebook rows with hand-drawn digits
4. **Anonymous** - Black band explaining vote privacy
5. **Everybody gets a turn** - Gold cap with example diagram
6. **Joining is your choice** - Two cards (if you join / if you don't)
7. **Questions** - Accordion FAQ
8. **CTA** - Link to the polls hub
