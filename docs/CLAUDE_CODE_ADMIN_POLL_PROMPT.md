# Admin side of the poll system

Build the admin tools for the monthly poll. Read these first, they define the system this admin runs:
- docs/CLAUDE_CODE_VOTING_PROMPT.md (phases, hard gates, anonymity, cap rules, tables)
- docs/CLAUDE_CODE_POLLS_PAGE_PROMPT.md and docs/CLAUDE_CODE_RULES_PAGE_PROMPT.md

Mockup to match: `design/admin/index.html` (open it, use the "poll phase" dropdown at the top to see every state). It's preview only. Copy its layout, fields and behavior, but build it with the real admin page's code and real data.

## Where it goes
Add a third tab, **Polls**, to the existing `admin/index.html` (Invites | Members | Polls). Reuse the page's existing tokens, `.tabs`, `.card`, `.field`, `.btn`, `.list`/`.row`, `.tag`, `.msg`. Don't restyle anything that already exists. No animations for now, leave hooks.

Admin only. Check the role on the server (RLS and RPC), not just by hiding the tab.

## Screens
1. **Polls list.** All polls with a phase tag, "Open" button, "Create a poll" card.
2. **New poll.** Title, one line, 5 dates (joining + ideas open, ideas close, joining closes, voting opens, voting closes), and the poll's rules: votes per person per ballot (3), golds per person (3), votes needed for an award (2), ideas per member (3), awards min/max (12/20), people needed to run (10), fallback when cap can't move a gold (keep winner or no award). Saves as a draft. Nothing opens until admin says so. Show the plain "what happens" list on the side.
3. **Overview** (inside a poll). Phase stepper, 4 stat tiles, a "Next step" card with a gate checklist and one big button whose label changes by phase, the schedule, and a "Careful" card (reopen voting while closed, cancel poll).
4. **People.** Who joined, search, remove (only before the list locks), reminder to members who haven't joined. After joining closes: locked banner, nobody can join or leave.
5. **Ideas.** Submitted ideas, most upvotes first. Accept, edit, merge (upvotes add), decline (ask for a reason). Auto-flag ideas that name a member and likely duplicates. Side card shows accepted count vs min/max. Read only once voting opens. Red count badge on the tab for ideas waiting.
6. **Ballot.** The accepted awards in order, move up/down, edit, remove. Check card (count within min/max, titles are moments not people). "See it as a member" preview. Locked once voting opens. Members see people shuffled per voter, admin only controls award order.
7. **Voting.** Turnout only (ballots in, joined but not voted, ballots per day). No counts per person or award, for anyone, admin included. Reminder button emails only joined members who haven't voted.
8. **Results.** Only after voting closes. Shows the golds-rule changes (what had the most votes vs who was awarded, "kept" case flagged), and a captions editor. It reads and writes the same shape as `poll/halloween-2026/captions.json` (`defaults` for winner and personal cards, `highlights` keyed by member slug with a `title` and `caption`, `categories` for per-award captions). Start from that file for halloween, and store captions per poll in the database from here on. Empty means use the default. Also share card examples, and a publish box with 3 required checkboxes. Publish builds the results page data and share cards.
9. **Emails.** The 5 poll emails with send time, audience, on/off, edit text. Each sends once.
10. **Log.** Every admin action and phase change with who and when. Votes are never logged.

## Rules that must hold (enforce in the database, not just the UI)
- Voting can't open until joining is closed and the list is locked. `voting_open_at >= join_close_at`. Reject the date save if not, with the plain message in the mockup. Opening voting early is blocked while joining is still open. "Close joining now" is the way through.
- Needs at least the "people needed to run" joined before voting opens.
- Ballot and idea changes are blocked once voting is open.
- No tally, count or per-award number is readable by anyone while voting is open. The tally RPC only works when the poll is closed, and only for admin.
- Results are visible to members only after Publish. Publish needs all 3 checkboxes (send them to the RPC) and is final.
- Reopen voting is allowed only while closed and unpublished, and is logged.
- Past dates are locked. Future dates editable if the gate still holds.
- Admin can't see who voted for what. Voting stores a ballot token, not a member id. Turnout comes from the separate "has voted" table.
- Every admin action writes to the audit log.
- Phase changes also happen on schedule (a cron or scheduled function checks the dates), same checks as the button.

## Fit the real site
Use the real tables and RPCs from the voting prompt. If something the mockup shows isn't in the schema yet (emails table, captions, audit log), add a migration. Show me the migration SQL before running it.

## Acceptance
- Every phase in the mockup dropdown matches what the real admin shows, buttons enabled/disabled the same.
- Try to open voting with joining still open: blocked in UI and by the DB.
- Try to read counts during voting as admin: nothing comes back.
- Publish with an unchecked box: blocked.
- Non-admin account can't load or call any of it.
- Works at 390px with no sideways scroll, and at desktop.
- Existing Invites and Members tabs behave the same as before.
