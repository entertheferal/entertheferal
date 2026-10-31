# Claude Code prompt: Halloween poll results pages + share cards

Paste everything below the line into Claude Code, run from the root of `~/Developer/feral`.

---

## Goal

Build the public results experience for our first community poll (the Halloween Horror Movie Poll) on the existing Feral Collective static site (deployed on Vercel), plus a share system so members can post their results to social media. Everything is built from ONE data file, so the same code can power future polls.

Mockups to match are already in the repo. Open them in a browser and copy the look exactly (ED Fairville blackletter, black ink on paper, hand-drawn digits and brush art, no gradients, no rounded-corner SaaS look):

- `design/results/index.html` : desktop results page
- `design/results/app.html` : phone, app-style results page (Moments / Categories / Find me tabs, bottom sheets, carousel)
- `design/share/index.html` : the three share-card designs in Story and Feed sizes
- `design/share/png/*.png` : exported examples of the six cards
- `design/share/build.py` + `cards.css` : how the mockup cards were laid out (CSS is the source of truth for the card look)
- Shared assets: `design/results/art/`, `design/results/icons/` (hand-drawn digits n0 to n9, underline, star), `fonts/ED-Fairville-Regular.woff2`

Do not redesign. If something in the mockup is ambiguous, match the mockup and tell me.

## Decisions already made (do not reopen)

- No leaderboard and no podium ranking. It felt like a popularity contest.
- Do not show "the next best got N" lines.
- Tone is funny, never ranking people. No "3rd place" language on anything shareable.
- Only three highlight cards have jokes (Most golds: Ed D. Mame, the 13-vote landslide: Heather, Adopts every stray: Emmi). Keep the exact copy from the mockups.
- Hero tagline: "You all voted and honestly, nobody's wrong. Here's who survives the horror movie and who gets us all killed."
- The "Sleeps through the possession" category was removed. 27 categories.
- Stats, highlight cards, and the find-a-name feature are computed from the data, never hard-coded.

## 1. Data

Create `poll/halloween-2026/data.json` as the single source of truth, converted from the `D` array in `design/results/tpl.html` (if that template is not in the repo, read the array out of `design/results/index.html`).

```json
{
  "poll": { "slug": "halloween-2026", "title": "Halloween Horror Movie Poll", "year": 2026 },
  "categories": [
    { "slug": "takes-charge-in-a-panic", "title": "Takes charge in a panic",
      "gold": { "names": ["Heather"], "votes": 13 },
      "silver": { "names": ["Cpt. Sparky"], "votes": 2 },
      "bronze": null }
  ],
  "optOut": []
}
```

- silver/bronze can also be a tie with no names (`{ "tie": 12, "votes": 1 }`), or the string "singles", or null. Keep that behaviour from the mockup.
- Generate each category `slug` from the title (lowercase, strip punctuation and curly quotes, hyphens).
- `optOut` is a list of names that must not appear on any share card or link-preview image (see section 5).
- Write a small validator script (`scripts/validate-poll.mjs`) that fails on: duplicate slugs, a gold with no names, votes that are not positive integers, an opted-out name missing from the data.

## 2. Results pages

- `/poll/halloween-2026/` serves ONE responsive page that matches `design/results/index.html` on desktop and `design/results/app.html` on a phone (use a width breakpoint, around 760px; do not UA-sniff). Both layouts render from data.json in the browser with vanilla JS. No framework, no build step for the page itself.
- Phone layout: tabs (Moments, Categories, Find me), swipeable highlight carousel with scroll-snap, bottom sheets with swipe-to-dismiss, sticky header, safe-area insets, `prefers-reduced-motion` respected.
- Desktop: hero, stats strip, big-moment cards, full category table, find-a-name dropdown that highlights the categories a person appears in.
- Accessibility: real buttons, focus-visible rings, sheets trap focus and close on Escape, all hand-drawn digit images get real text alternatives (screen readers must read "13", not nothing), colour contrast at least AA on text.
- Self-host the font and any other fonts. No Google Fonts requests (privacy: they leak visitor IPs).
- Add `<meta name="robots" content="noindex">` for now, because the pages name members. Make this one constant I can flip later.

## 3. Share cards (generated images)

Make a script `scripts/make-share-cards.mjs` (Node + Playwright, which is fine as a dev dependency) that renders PNGs from the same data, using the card HTML/CSS from `design/share/` as the template (port `build.py` to JS; keep `cards.css` and the three card types):

1. **Winner card** (one per category): category title, winner name(s) in ED Fairville, vote count in hand-drawn digits, a short one-line caption, footer with "The Feral Collective" and the site URL. For ties with several gold winners, show all names and drop the vote line to "tied".
2. **Personal card** (one per person who appears as a gold winner): "In the movie, I am", the name, number of golds, up to 4 category names won (if more, show the first 4 and "+N more"). One-line caption.
3. **Highlight card** (dark version): only for the three highlight people from the page. Use the exact joke copy.

Sizes for every card: Story `1080x1920` and Feed `1080x1350`. Output to `poll/halloween-2026/share/`, file names `c-<category-slug>-story.png`, `c-<category-slug>-feed.png`, `p-<person-slug>-story.png`, and so on, plus an `og` size `1200x630` for link previews (simple landscape version of the same look).

Rules:
- Keep text inside Instagram Story safe zones: nothing important in the top 250px or bottom 340px of the 1920 canvas.
- Long names and long category titles must never overflow. Auto-shrink the font in steps, with a minimum size, and fail the script loudly if text still does not fit. Test with the longest names and titles in the data.
- Captions come from a small `captions.json` (a default per card type, overridable per category). Keep them plain and funny, not corporate. Write defaults for the winner card in the style of: "Thirteen of you saw the chaos and said 'her.' Brave." Do not invent claims about real people; captions describe the vote, not their character.
- Skip any card for an opted-out name. Do not generate a file at all.
- Optimise the PNGs (keep each under about 600KB) and write `share/manifest.json` listing every card with its paths and sizes.
- The script is idempotent and can be re-run after data changes. Add an npm script `npm run share-cards`.
- Commit the generated PNGs, so Vercel just serves static files.
- Footer URL comes from one config constant. Currently the mockup says `yoursite.com/poll`. Ask me for the real domain, or leave a clearly marked TODO.

## 4. Share buttons on the page

- Each category sheet, each highlight card, and each person view in "Find me" gets a **Share** button.
- On phones: use the Web Share API with the image file (`navigator.canShare({files})`) so it opens the native share sheet with the Story image. Fall back to sharing just the link, then to "Save image" (download) and "Copy link". Detect support properly; never assume it works.
- Let the person pick Story or Feed in a small two-option toggle, default Story on phones and Feed on desktop.
- Desktop: "Save image" and "Copy link" only.
- The button must work with no JavaScript framework, and never fail silently: show a short plain message ("Couldn't open sharing, saved the image instead").
- Add Plausible-style, privacy-friendly event hooks (no-op functions) for share clicks, but do NOT add any tracking script.

## 5. Link previews (Open Graph) and opt-out

Link previews need a real URL per thing shared, so generate small static pages:

- `/poll/halloween-2026/c/<category-slug>/` and `/poll/halloween-2026/p/<person-slug>/`
- Each has proper `og:title`, `og:description`, `og:image` (the 1200x630 card), `twitter:card=summary_large_image`, a canonical URL, and then redirects humans to the main results page with the right sheet/person opened (`/poll/halloween-2026/#c=<slug>` or `#p=<slug>`; support those hashes on the main page, opening the sheet or person view on load).
- Generate these pages with the same script, not by hand.
- Opted-out people: no personal page, no personal card, and their name is replaced by "a member" in any generated OG text. They still appear on the main results page unless I say otherwise (flag this for me).
- Add a short, human note near the Share button and in the footer: "Don't want your name on shared images? Message an admin and we'll take it off." Put the contact method behind one config constant.

## 6. Privacy and security

- Self-hosted fonts, no third-party requests from these pages. Check the network tab.
- Add or extend security headers in `vercel.json` (CSP that allows only self for scripts, styles, images, fonts; `X-Content-Type-Options`, `Referrer-Policy: strict-origin-when-cross-origin`). Do not break the existing pages: test them.
- These pages contain members' names (and display names). Keep them `noindex` until I decide, and mention in your final message that this should be covered in the privacy policy (I am writing it from the accounts prompt) and that shared images are public once someone posts them.
- No emails, no user IDs, no vote-level data (who voted for whom) anywhere in the output. Only aggregated results.

## 7. Acceptance checklist (run it and report)

1. `npm run share-cards` produces every file in the manifest and exits 0; the script exits non-zero if a name overflows.
2. Open the main results page at 390px and 1280px wide: no horizontal scroll, no console errors, matches the mockups side by side.
3. Pick the longest category title and longest name: the card text fits on Story and Feed.
4. Web Share works in at least one real mobile browser I can test; otherwise say clearly it is untested.
5. `#c=<slug>` and `#p=<slug>` deep links open the right view.
6. Pasting a category URL into a link-preview checker (or `curl` the page) shows the right OG tags and image.
7. Opted-out name produces no card and no personal page.
8. Network tab shows zero third-party requests.
9. Lighthouse accessibility score of 95+ on both layouts.

## Deliverables

- The pages, scripts, generated cards, and `vercel.json` changes.
- A `poll/README.md` explaining how to add the next poll (copy data.json, edit, run the script).
- A final message listing: what you built, anything that deviates from the mockups, what is untested, and the questions you still need answered (real domain, opt-out contact method, whether the results page should become members-only later).

Work in small commits and show me the plan before you start building. Ask me before deleting any existing file.
