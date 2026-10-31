# Poll System

This directory contains community polls for the Feral Collective.

## Structure

```
poll/
├── halloween-2026/          # Poll instance
│   ├── index.html           # Responsive results page
│   ├── data.json            # Source of truth for results
│   ├── captions.json        # Share card captions
│   ├── art/                 # Texture assets
│   ├── icons/               # Hand-drawn digit images
│   ├── share/               # Generated share cards (PNGs)
│   │   ├── c-*.png          # Category winner cards
│   │   ├── p-*.png          # Personal result cards
│   │   ├── h-*.png          # Highlight cards
│   │   └── manifest.json    # Generated card manifest
│   ├── c/<slug>/index.html  # OG preview pages (generated)
│   └── p/<slug>/index.html  # Personal OG pages (generated)
└── README.md
```

## Adding a New Poll

1. **Copy the template**
   ```bash
   cp -r poll/halloween-2026 poll/your-poll-slug
   ```

2. **Edit data.json**
   - Update `poll.slug`, `poll.title`, `poll.year`
   - Replace `categories` with your poll results
   - Slug format: lowercase, no punctuation, hyphens for spaces

3. **Edit captions.json**
   - Update `highlights` with your special mentions
   - Add any category-specific captions

4. **Update index.html**
   - Update embedded `DATA` constant (or load from data.json)
   - Update `HIGHLIGHTS` array
   - Update title, meta tags, canonical URL

5. **Copy assets**
   - Place textures in `art/`
   - Place digit images in `icons/`

6. **Generate share cards**
   ```bash
   npm run share-cards
   ```

7. **Validate data**
   ```bash
   npm run validate-poll poll/your-poll-slug/data.json
   ```

## Data Format

### data.json

```json
{
  "poll": {
    "slug": "halloween-2026",
    "title": "Halloween Horror Movie Poll",
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

## Scripts

### Validate poll data
```bash
npm run validate-poll                    # Default: poll/halloween-2026/data.json
npm run validate-poll path/to/data.json  # Custom path
```

### Generate share cards
```bash
npm run share-cards
```

Requires Playwright. Install with:
```bash
npm install
npx playwright install chromium
```

## Indexing

The results page has `noindex` by default. To enable search indexing:

1. Edit `index.html`
2. Change `<meta name="robots" content="noindex,nofollow">` to `<meta name="robots" content="index,follow">`
3. Optionally update the `NOINDEX` constant in the script

## Privacy Notes

- Member names appear on results page and in share cards
- Share cards are public images once posted to social media
- Consider updating privacy policy when launching new polls
