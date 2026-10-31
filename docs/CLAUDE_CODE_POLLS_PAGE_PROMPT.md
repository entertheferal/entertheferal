# Claude Code prompt: the polls page (this month + past polls)

Paste everything below the line into Claude Code, run from the root of `~/Developer/feral`.

---

## Goal

Build the polls landing page at `/poll/`. It shows this month's poll (with where it's at and what the member should do next) and a history of past polls. Match the design exactly:

- `design/polls/page.html` is the real design. `design/polls/index.html` is only a preview wrapper with demo buttons (device, poll phase, member status, history length). Do not ship those buttons or the wrapper. Open the wrapper in a browser and click through every state before you start.
- Page copy is final: lowercase, short, plain, like a person wrote it. No em dashes. Copy the exact wording. Do not "improve" it.

Read the repo first and reuse what exists:
- `poll/halloween-2026/` : the finished results page, `data.json`, share cards. Its header (top `.bar` with the "the Feral Collective" mark and a pill), bottom `.tabbar`, black footer with brush art, 1120px `.wrap`, hand-drawn digits and brush art are the pattern to follow.
- `js/auth.js`, `supabase/`, `login/`, `join/`, `settings/`, `calendar/` : auth, profiles, nav, buttons and form styles.
- `docs/CLAUDE_CODE_VOTING_PROMPT.md` : the voting system this page will sit on top of (not built yet, see below).
- `fonts/` : self-hosted ED Fairville and IBM Plex Mono. Check how Archivo is loaded on the results page and do the same. No Google Fonts requests.

## What the page shows

**This month (black hero, matches the mockup):**
- Pill with the current phase, the poll title in blackletter, one-line subtitle, a four-step tracker (Join, Ideas, Voting, Results) with dates and the current step highlighted, and one primary button.
- A white "your status" card beside it (stacked below on phone) with the member's status and, while joining is open, a bar and the count "35 of 54 members are in".
- Phases: `open` (joining and ideas open), `curating` (picking the final list), `voting`, `closed` (votes in, results not up yet), `results` (results are up), `none` (between polls, "we'll email you when joining opens").
- Member states: not joined, joined, voted (and signed out, see below).
- Buttons by state (copy from the mockup):
  - open + not joined: "i'm in" and "read the rules". open + joined: "suggest an idea" and "read the rules".
  - curating: "read the rules".
  - voting + joined: "vote now". voting + voted: "edit my votes". voting + not joined: no vote button, status says "joining closed" and "you can read the results when they're up".
  - closed: "read the rules".
  - results: "see results" (links to that poll's results page).
  - none: "read the rules".
- A member who has not joined must never see a vote button, and the server must also refuse them (see the voting prompt).
- Signed-out visitors: show the page, but replace the status card with a short "log in to join" card and no vote or join buttons. The poll page itself is for members only if the voting prompt says results are members-only. Ask me before deciding. Default: signed-out visitors are sent to login.
- A thin strip under the hero: "anonymous votes", "nobody wins more than 3 golds", "you have to join to play", and a "read the rules" link.

**Past polls:**
- A grid of cards, newest first, 2 columns on desktop and 1 on phone. Each card: month, title in blackletter, one line, hand-drawn digits for number of awards and number of people who got a gold, brush art, a "see results" button linking to that poll's results page, and a line for members who took part ("you won 4 golds", or "you were in this one").
- Never rank people on these cards. No leaderboard.
- Empty state: "more polls will show up here as we run them."
- Only polls with status `published` appear.
- The Halloween poll is the first entry. Its numbers (27 awards, 20 people got a gold) come from `poll/halloween-2026/data.json`. Compute them, never type them in. The two other cards in the mockup ("Road Trip Chaos", "Group Project") are made-up samples so I could see a longer list. Do not create them.
- "You won N golds" and "you were in this one" are computed per member. For Halloween, derive them from the published data using the member's display name as it appears there. If a member can't be matched, show nothing. Don't guess.

**Layout:**
- Phone (under about 760px): the app shell, with the sticky top bar and a two-tab bottom bar (This month, Past polls). Respect safe areas.
- Desktop: both sections on one page. Footer: the black footer with the line from the mockup.
- Keep the poll phase and dates readable at a glance on every screen size.

## Data: build it so it works before the voting system exists

The voting system is a separate, bigger build. This page must work now with only the Halloween poll, and switch over to live data later without a rewrite.

1. Create `poll/polls.json` as the index of polls: for each poll `slug`, `title`, `month`, `line`, `status` (`published` for Halloween), `resultsUrl`, `art` (one of the brush images), and for published polls `awards` and `peopleWithGold` computed by a small script from that poll's `data.json` (add `npm run polls-index`). Halloween is the only entry.
2. Add one optional `current` block in the same file for this month's poll: `slug`, `title`, `subtitle`, `status` (one of the six phases), `joinClosesAt`, `ideasCloseAt`, `votingOpensAt`, `votingClosesAt`, `joinedCount`, `memberCount`. Leave it out when there is no current poll, which shows the "between polls" state.
3. Put all the page's data access behind ONE small module (for example `poll/hub-data.js` with `getHubData()` and `getMyStatus()`). Today it reads `polls.json` and the signed-in profile. When the voting system exists, only this module changes, to read polls, dates, participant counts and the member's join/vote status from Supabase. No page code should know where the data comes from.
4. `getMyStatus()` returns `out`, `in` or `voted` for the current poll. Until the voting system exists, return `out` for everyone and show the real "i'm in" button as disabled with a "joining opens soon" note, OR hide the status card. Ask me which I prefer, and default to the disabled button.
5. Phase text and dates are derived from the data. Never hard-code "nov 7", "35 of 54", or "holiday chaos". Those are demo values.

## Fit the real site

- Same fonts, 2px ink borders, square corners, mono labels, blackletter headings, buttons and spacing as the rest of the site. Where the mockup and the live site disagree, the live site wins. Tell me the differences.
- Add `/poll/` to the site navigation next to the calendar.
- Self-hosted assets only, no third-party requests, headers consistent with `vercel.json`.
- `noindex` while the pages name members.
- Accessibility: real links and buttons, focus-visible rings, tabs use correct roles and keyboard support, the progress bar has a text equivalent ("35 of 54 members are in"), hand-drawn digit images have real text alternatives (a screen reader must read "27 awards", not nothing), colour contrast AA, respects `prefers-reduced-motion`.
- No animations in this build.

## Acceptance checklist (run it and report)

1. Preview every phase and every member state against the mockup. The right button and status card show every time, and a not-joined member never sees a vote button.
2. Halloween appears in past polls with correct computed numbers. Adding a second published entry to `polls.json` makes a second card appear with no code changes.
3. With no `current` block, the page shows the "between polls" state.
4. 390px, 768px, 1280px screenshots next to the Halloween results page and the calendar. Nothing looks out of place. No horizontal scroll, no console errors.
5. Both bottom tabs work on phone, including keyboard use and screen reader names.
6. `npm run polls-index` is idempotent and fails loudly on a bad `data.json`.
7. No third-party requests in the network tab.

## Deliverables

`poll/index.html` (the hub), `poll/hub-data.js`, `poll/polls.json`, the index script, nav change, a short section added to `poll/README.md` explaining how to add a new poll to the history and how to set the current poll. In your final message: what you built, differences from the mockup, what's untested, and my open questions (signed-out behaviour, what "i'm in" does before the voting system is built).

Show me a plan first. Small commits. Ask before deleting any existing file.
