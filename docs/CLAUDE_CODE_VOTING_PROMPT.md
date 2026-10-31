# Claude Code prompt: monthly community poll (join, ideas, vote, fair results)

Paste everything below the line into Claude Code, run from the root of `~/Developer/feral`.

---

## What you are building

The full monthly poll system for The Feral Collective, about 50+ members: members opt in to a poll, suggest award ideas, an admin picks the final list, members vote anonymously, the admin closes voting, then publishes results. Results appear on a results page that looks exactly like the Halloween one. Fairness is a core feature.

Before writing anything, read the repo. A lot already exists, so reuse it instead of rebuilding:
- `poll/halloween-2026/` : the finished Halloween results page (`index.html`, `data.json`, `captions.json`, `share/` cards, `c/` and `p/` link pages) and `poll/README.md`. This is the template for every future results page.
- `js/auth.js`, `js/supabase-config.js`, `supabase/`, `login/`, `join/`, `settings/`, `u/`, `admin/` : accounts, invite-only signup, profiles, roles. Reuse the auth guard, the profile table and the admin role.
- `docs/CLAUDE_CODE_ACCOUNTS_PROMPT.md` and `docs/CLAUDE_CODE_RESULTS_PROMPT.md` : earlier prompts with the conventions (Supabase, RLS, security-definer RPCs, privacy, headers). Follow them.
- `scripts/` and `package.json` : the share-card generator and its conventions.

Mockup to match: `design/voting/index.html` (open it in a browser). It has member screens (Join, Ideas, Ballot with the member picker, Review, Rules) and admin screens (Curate ideas, Close and publish). Plain-language copy in the mockup is final: lowercase, short, direct, written like a person. No em dashes, no filler. Copy the exact wording. Do not "improve" it.

Do not change the Halloween poll's data, page or share cards. It stays as a finished archive.

## The three hard gates (these are rules, enforce them in the database, not just the UI)

1. **Voting cannot start until joining is closed.** `voting_open_at` must be later than or equal to `join_close_at` (database constraint). The "open voting" action fails unless joining is closed. When joining closes, the list of participants is frozen (`poll_participants.locked = true`) and nobody can join or leave after that. The admin can close joining early with a button. Nominee lists for the ballot are built only from the frozen list.
2. **No results before voting closes.** While the poll is `voting_open`, nobody (members or admins) can see any tally or count. The tally RPC must raise an error unless the poll is `closed` (voting window ended or the admin closed it). The results tables must not be readable by members until the poll is `published`.
3. **Results are public only when the admin publishes.** Closing voting does not publish. After close, the admin sees a private preview, then confirms and publishes. Publishing is what makes results visible to members and builds the results page and share cards.

Write tests that try to break each gate with direct API calls (anon key, a normal member, an admin).

## The cycle (state machine)

`draft` → `ideas_open` → `curating` → `voting_open` → `closed` → `published`

- Joining and ideas can overlap: both open at `ideas_open`. Joining ends at `join_close_at` (or when the admin closes it). Ideas end at `ideas_close_at`. Only members who joined can submit ideas.
- `curating`: admin accepts, edits, merges, declines ideas.
- `voting_open`: allowed only when joining is closed and locked, and the ballot has enough categories (default minimum 12) and enough participants (setting, default 10). Ballot categories are created from accepted ideas.
- `closed`: voting window ended. Admin previews the tally with the cap applied.
- `published`: results are visible, the results page and share cards are built.
- Allow reopening voting from `closed` before publish. Log it.

Transitions happen only through RPCs that check the rules, and are all written to an `audit_log` (who, what, when). Never rely only on the UI.

## Data model (Supabase / Postgres)

All tables have RLS on. Write migrations in `supabase/migrations/`.

- `polls`: id, slug, title, topic, status, join_open_at, join_close_at, ideas_close_at, voting_open_at, voting_close_at, settings jsonb, published_at. Settings: `votes_per_person_per_ballot` (3), `gold_cap` (3), `min_votes_for_award` (2), `max_categories` (20), `min_categories` (12), `min_participants` (10), `ideas_per_member` (3), `cap_fallback` ('keep_winner' | 'no_award'), `tie_rule` ('share_gold').
- `poll_participants`: poll_id, member_id, joined_at, locked (unique pair). Polls are opt in. Nobody is added automatically.
- `ideas`: id, poll_id, author_id, text (90 chars max), status ('pending'|'accepted'|'declined'|'merged'), decline_reason, merged_into, flagged, flag_reason, created_at. Authors see their own statuses; other members never see authors. Admins do.
- `idea_upvotes`: idea_id, member_id (unique).
- `categories`: id, poll_id, idea_id, title, position.
- `ballots_cast`: poll_id, member_id (unique). Records only that someone voted.
- `votes`: id, poll_id, category_id, ballot_token (random uuid), nominee_id. **No member_id on this table.**
- `results`: poll_id, category_id, raw jsonb, final jsonb, reason text. Readable by members only when the poll is `published`.
- `audit_log`.
- Image opt-out list (members can ask to be left off shared images even after joining): reuse what the results prompt created, or add `share_opt_outs`.

## Anonymity (do this carefully)

- A member's ballot is stored under a random `ballot_token`, not their id. Only the member's browser knows the token (IndexedDB/localStorage) so they can edit until voting closes.
- `submit_ballot(poll_id, picks, previous_token)` runs in one transaction: checks the poll is `voting_open`, checks the member joined and is active, enforces the per-ballot limits, replaces votes under `previous_token` (if valid), inserts the new votes under a new token, upserts `ballots_cast`, returns the token.
- Lost token (new device, cleared browser): the member cannot edit their ballot. That is the price of real anonymity. They see "you voted" with no edit button and can never vote twice (`ballots_cast` blocks it). Offer an optional "download my ballot key" file at submit time to restore editing elsewhere. Do not weaken anonymity to solve this. Explain the choice back to me before building.
- No admin RPC or view may return `votes` joined to a member. Admin tally RPC returns aggregates only.
- Never log vote contents anywhere.
- Say honestly in `poll/README.md` and on the rules page what anonymity does and does not guarantee.

## Rules enforced server-side (the UI mirrors them, the database is the authority)

1. You cannot vote for yourself.
2. You cannot name the same nominee in more than `votes_per_person_per_ballot` categories on one ballot.
3. Only members who joined this poll can submit ideas, upvote, vote, or be a nominee.
4. One ballot per member per poll, editable until `voting_close_at`.
5. Skipping a category is allowed. Partial ballots are valid.
6. Ideas: `ideas_per_member` each, 90 characters, only while ideas are open.
7. One upvote per member per idea, none on your own.
8. A category with fewer than `min_votes_for_award` total votes is not awarded.
9. Rate limits on idea and ballot submission.

## Screens (match the mockup; screen names are the mockup's tabs)

**Member:** Join the poll, Submit ideas, Ballot, Review and submit, Rules.
- Join: two cards explain what joining and not joining means, an "i'm in" button, live count, leave allowed until joining closes.
- Gate: members who haven't joined see "join to vote" / "join to suggest ideas" on those screens. Enforce server-side too.
- Ideas: "Most likely to…" prompt, 90 chars, advisory server-side check that flags ideas containing another member's name or handle (first-name tokens over 2 chars, case-insensitive). The member list must not be shipped to the browser for this. Warn the author, flag it for the admin.
- Ballot: one card per category. Phone: bottom sheet with search and the member list. Desktop: two columns, the picker always open on the right, auto-advance to the next unanswered category. Member lists show only participants who joined, shuffled with a stable seed per voter and category. Never show counts while voting. Disabled rows say why ("that's you", "used 3/3"). Progress bar, skip, review, submit, edit until close.
- Accessibility: sheet traps focus and closes on Escape, labelled search, disabled rows explain themselves to screen readers, visuals have text alternatives, keyboard-only voting works.

**Admin:** Curate ideas and Close and publish. Admin role checked server-side.
- Curate: ideas sorted by upvotes, author, flag reasons, similar-idea hints (suggest merges, never auto-merge). Accept, edit (audit-logged), merge (adds upvotes), decline with reason. Live count vs `max_categories`, checklist, joining window and voting window settings, "close joining now" button, "open voting" disabled until all gates pass (record any override in the audit log).
- Close and publish: turnout (joined / active members, ballots / joined), settings, the raw tally and the cap-adjusted result side by side, who the cap affected, three confirmation checkboxes, then Publish.

## Fairness: the gold cap (one pure, tested function)

1. Rank nominees per category into groups (gold, silver, bronze). Ties form a group.
2. Skip categories under `min_votes_for_award`.
3. Process categories by margin (gold votes minus next best), biggest first, so landslides lock before close races.
4. Award gold to the highest-ranked group where every member is under `gold_cap`. Co-golds count one each.
5. If no group is eligible, apply `cap_fallback`: `keep_winner` awards the original winner anyway and records it as "kept", counted separately; `no_award` leaves it unawarded.
6. Store `raw`, `final`, and a human-readable `reason` per changed category.

Write it as one TypeScript function with unit tests, including one using `poll/halloween-2026/data.json`. Tell me how often "kept" fires on the Halloween data (small communities often have thin runner-up votes, so it fires a lot).

## Results output (this is where it must match Halloween)

When the admin publishes:
1. Freeze `results`, set `status = published`.
2. Produce results data in **exactly the same shape as `poll/halloween-2026/data.json`** so the same page template renders it, with the same hero, stats, highlight cards, category list, find-a-name, phone and desktop layouts, share buttons, and link-preview pages (`c/` and `p/`).
3. Make that page template reusable: `poll/<slug>/` for any poll, reading its own data. Do not copy-paste the Halloween page; extract the shared template and have Halloween keep working unchanged.
4. Run the share-card generator for the new poll (Story and Feed sizes, and the link-preview size), only for members who joined and have not opted out of shared images.
5. The "highlight" jokes come from `captions.json` for that poll. Provide an admin text field for them at publish time, with sensible defaults, so I can write my own.
6. Before publish the results page for that slug must return nothing to non-admins (a "results aren't up yet" page).

Propose how publish triggers the static build (for example a Vercel deploy hook plus a GitHub Action running `npm run share-cards`, or runtime reads of a public published-results endpoint). Show me the plan and the tradeoffs before building that part.

## Rules page, joining and privacy

- Build the Rules page from `design/rules/page.html` (full visual design) using `docs/CLAUDE_CODE_RULES_PAGE_PROMPT.md`. Numbers and dates come from poll settings so the page can never disagree with the system. Publish the rules before joining opens.
- Build the admin side from `design/admin/index.html` using `docs/CLAUDE_CODE_ADMIN_POLL_PROMPT.md`. It is a new Polls tab in `admin/index.html`.
- Joining is explicit consent to be named in that poll's results and shared images. A member can still ask an admin to be taken off shared images later.
- Votes are anonymous. Ideas show the author only to admins.
- Update the account export RPC and account deletion: export their ideas, upvotes, participation and ballots_cast; on delete, remove their ideas, upvotes, participation and `ballots_cast` row, leave anonymous `votes` (no personal data). In published past polls their name becomes "a former member" unless I say otherwise (flag this for me).
- Update the privacy policy draft to cover polls, anonymous votes and share images. Tell me to have it lawyer-reviewed.
- No third-party requests, self-hosted fonts, headers consistent with `vercel.json`.

## Notifications

Email via the existing SMTP: joining and ideas open, a reminder to join before joining closes, voting open, a reminder 24 hours before voting closes (only to members who joined and haven't voted), results published. Members can opt out of poll emails in settings. Scheduled job, idempotent, no duplicates.

## The polls hub page (current poll + history)

Build `/poll/` as the landing page for everything, matching `design/polls/page.html` (open `design/polls/index.html` to preview its states). `page.html` is the real design. `index.html` is only a preview wrapper with demo controls, so do not ship the controls.

- **This month** (black hero): the poll title in blackletter, a one-line subtitle, a pill with the current phase, a four-step tracker (Join, Ideas, Voting, Results) with dates and the current step highlighted, and one clear button that depends on where the poll is and where the member is. Beside it, a white "your status" card (not joined, joined, voted) with the live count of members who joined.
- Phases and what each shows: joining + ideas open, picking the final list, voting open, voting closed (results not up yet), results up, and between polls (no current poll, "we'll email you when joining opens"). All of this comes from the poll's status and dates in the database, never hard-coded. A member who has not joined must never see a "vote" button.
- A thin strip under the hero repeats the three fair-play rules and links to the rules page.
- **Past polls:** a grid of cards, newest first. Each card has the title in blackletter, the month, one line, hand-drawn digits for number of awards and number of people who got a gold, brush art, a "see results" button linking to that poll's results page, and a "you won N golds" or "you were in this one" line for members who took part. Do not rank people on these cards. Empty state: "more polls will show up here as we run them." Only polls with status `published` appear in history.
- Phone: app shell with a two-tab bottom bar (This month, Past polls) and the sticky top bar. Desktop: both sections on one page. Switch at about 760px.
- The Halloween poll is the first history entry. Its numbers (27 awards, 20 people got a gold) come from `poll/halloween-2026/data.json`, never typed in. The two other cards in the mockup are made-up samples so I could see a longer list, so do not create them.
- A member's "you won N golds" comes from the published results, only for polls where they joined.
- Add the hub to the shared site navigation (Home, Calendar, Polls, profile, settings). If the nav from `docs/CLAUDE_CODE_POLLS_PAGE_PROMPT.md` already exists, reuse it. If not, build it as described there.

## Fit the real site

The mockup has demo-only chrome that must NOT ship: the black "Monthly Poll" banner, the phase strip, the screen switcher, the Phone / Desktop toggle, the phone frame, the gray background, the "signed in as" note. Only the screens are the design.

- Build inside the existing shell. Phone: the app shell from the results page (top `.bar` with the "the Feral Collective" mark and a pill, bottom `.tabbar`, safe areas). Desktop: the wide layout from the mockup inside the normal site header and footer. One responsive page per screen, switching at about 860px.
- Routes like `/poll/join/`, `/poll/ideas/`, `/poll/vote/`, `/poll/rules/`, admin under `/admin/poll/`. Use the existing auth guard.
- Show the poll phase and dates in the pill or header area of each page.
- Colours, 2px ink borders, square corners, mono labels, blackletter headings, buttons and form fields must match the rest of the site. Where the mockup and live site disagree, the live site wins. Tell me the differences.
- Animations are NOT in this build. Leave hooks (a `data-state` attribute on the vote card and result items) and respect `prefers-reduced-motion`. I'll ask for animations separately.

## Acceptance checklist (run it and report)

1. Full cycle with test users: join, ideas, upvotes, curate, close joining, vote, edit, close voting, preview, publish.
2. Gates: cannot open voting before joining is closed; cannot join or leave after lock; cannot read any tally or count while voting is open (including as admin); cannot read results before publish; results page for an unpublished poll shows nothing.
3. Direct API calls cannot bypass: self-vote, per-ballot limit, voting outside the window, voting without joining.
4. No query returns a member linked to a vote, for any role. Tests prove it.
5. Cap function tests pass, including ties, all-capped fallback and the Halloween data.
6. A test poll published through the system renders on the same results template as Halloween, in phone and desktop layouts, with share cards and link-preview pages. Halloween itself is unchanged.
7. The polls hub shows the right button and status card for every phase and member state (not joined, joined, voted) and lists only published polls. 390px, 768px and 1280px screenshots of every page next to the Halloween results page and the calendar: nothing looks out of place. No horizontal scroll, no console errors.
8. Ballot with 54 test members: search is instant and works one-handed.
9. Keyboard-only voting works; Lighthouse accessibility 95+; reduced motion respected.
10. Export and delete handle the new tables.

## Deliverables

Migrations, RPCs, RLS policies, tests, pages, scheduled jobs, the reusable results template, an updated `poll/README.md` (how to run a poll end to end, how anonymity works and its limits).

In your final message list: what you built, deviations from the mockup, what is untested, and my open questions (lost-token tradeoff, "former member" naming, who the admins are, default dates for the cycle, publish/build approach).

Show me a plan first. Small commits. Ask before deleting any existing file.
