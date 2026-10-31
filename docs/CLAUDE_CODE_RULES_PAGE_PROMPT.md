# Claude Code prompt: the poll rules page

Paste everything below the line into Claude Code, run from the root of `~/Developer/feral`.

---

## Goal

Build the poll rules page at `/poll/rules/`. Match the design exactly:

- `design/rules/page.html` is the real design. `design/rules/index.html` is only a preview wrapper with a phone/desktop toggle. Do not ship the wrapper. Open it in a browser first.
- Copy is final: lowercase, short, plain, like a person wrote it. No em dashes. Copy the exact wording. Do not "improve" it.

Read the repo first and reuse what exists: the Halloween results page (`poll/halloween-2026/index.html`) for the top bar, footer, `.wrap`, hand-drawn digits and brush art; `fonts/` for self-hosted ED Fairville and IBM Plex Mono (check how Archivo is loaded on the results page and do the same, no Google Fonts requests); and the shared site navigation if it exists (see `docs/CLAUDE_CODE_POLLS_PAGE_PROMPT.md`).

## The page, top to bottom

1. **Hero** (black, brush art): "how the poll works", huge "the rules", the line "short version: you join, you vote, nobody hogs the awards.", and jump links to each section.
2. **How it works:** a timeline, not cards. Six steps with the hand-drawn digits 1 to 6 sitting on a line with a red diamond at each step: we pick a theme, you join if you want in, you send ideas, we pick the list, you vote, results go up. Each has a small red date label, and the step titles are set in ED Fairville (blackletter), not Archivo. On desktop it runs left to right across the page. Under about 900px it becomes a vertical timeline with the line down the left.
3. **Fair play:** a boxed list of full-width rows, like a rulebook, so it looks nothing like the timeline above. Each row has a big hand-drawn number on the left and the rule on the right: 0 votes for yourself, 3 same person max, 3 golds per person (this row is black), 2 votes to win. On phone the number shrinks and stays on the left.
4. **Anonymous:** black band, "nobody sees who voted for who." with four short points, including the honest one: if you clear your browser you can't edit your ballot anymore, but your votes still count.
5. **Everybody gets a turn:** the golds rule, with the example diagram (an example person keeps 3 golds, the other 2 go to the next person in line) and "ties share the gold." The diagram uses a made-up person ("alex"). Do not use a real member's name.
6. **Joining is your choice:** two cards, "if you join" and "if you don't".
7. **Questions:** accordion (`details/summary`): can i change my votes, can i vote for myself, can i pick the same person for everything, what if an award only gets a couple of votes, who picks the awards, what happens to my info (links to the privacy policy).
8. **Call to action:** "ready to play?" with a button to `/poll/`, then the black footer.

## Numbers and dates come from the poll settings

The mockup shows demo values. Never hard-code them. Pull these from the current poll's settings and dates so the page can never disagree with how the system actually works:

- votes per person per ballot (3), golds per person (3), minimum votes for an award (2), max awards (20), joining closes, ideas close, voting opens and closes.
- The big hand-drawn digit cards render whatever number the setting holds (support any number of digits; digit images are `icons/n0.webp` to `icons/n9.webp`).
- Sentences that contain a number (for example "nobody wins more than 3 golds in a month", "an award needs at least 2 votes", "20 awards max") build from the same settings.
- When there is no current poll, show the default settings and hide the dates ("dates are posted when the next poll opens").
- Put this behind one small data function, like the polls page does, so it can switch from a config file to the database later without touching the page.
- The example diagram's numbers should follow the golds-per-person setting (it shows a person keeping N and passing the extras on).

Keep the rule text consistent with `docs/CLAUDE_CODE_VOTING_PROMPT.md`. If the voting system's rules change, this page is what members read, so flag any mismatch you find.

## Fit the real site

- Same fonts, 2px ink borders, square corners, mono labels, blackletter headings and spacing as the rest of the site. Where the mockup and the live site disagree, the live site wins. Tell me the differences.
- Phone under about 760px: single column, wrapped link chips in the hero, cards stacked. Desktop: the grids from the mockup. Test at 390px, 768px and 1280px.
- Add the page to the shared site navigation if it exists, and link to it from the polls page ("read the rules"), the join screen, and the ballot ("anonymous. you can't vote for yourself...").
- Self-hosted assets only, no third-party requests, headers consistent with `vercel.json`.
- Public page is fine: it contains no member data. Do not add `noindex` unless the rest of the poll pages have it and I say so.
- Accessibility: one `h1`, logical heading order, real links and buttons, the accordion works by keyboard and is announced correctly, focus-visible rings, each hand-drawn digit group has a text alternative (a screen reader must read "3", not nothing), the example diagram has a text description, contrast AA, `scroll-behavior` and any motion respect `prefers-reduced-motion`.
- No animations in this build.

## Acceptance checklist (run it and report)

1. The page matches the mockup at 390px, 768px and 1280px. No horizontal scroll, no console errors.
2. Change a poll setting (golds per person to 2, votes to win to 4, add a third digit number) and show the page updates everywhere it appears, including the diagram and the FAQ text.
3. With no current poll, dates are hidden and defaults show.
4. Every jump link and the accordion work by keyboard and by tap.
5. Screenshots next to the polls page and the Halloween results page. Nothing looks out of place.
6. No third-party requests.

## Deliverables

`poll/rules/index.html`, the data function, nav and link changes, a short note in `poll/README.md`. In your final message: what you built, differences from the mockup, what's untested, and my open questions.

Show me a plan first. Small commits. Ask before deleting any existing file.
