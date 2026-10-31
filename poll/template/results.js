/**
 * Poll Results Template Utilities
 *
 * Shared functions for rendering poll results pages.
 * Import and use in any poll's index.html.
 */

// Escape HTML
export function esc(str) {
  if (str == null) return '';
  return String(str).replace(/[&<>"']/g, c => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
  }[c]));
}

// Generate digit images (hand-drawn style)
export function digits(n, basePath = 'icons/') {
  const str = String(n);
  const imgs = str.split('').map(d =>
    `<img src="${basePath}n${d}.webp" alt="" aria-hidden="true">`
  ).join('');
  return `<span class="sr">${n}</span>${imgs}`;
}

// Pad number with leading zero
export function pad(n) {
  return (n < 10 ? '0' : '') + n;
}

// Generate slug from title
export function slugify(s) {
  return s.toLowerCase()
    .replace(/['']/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

// Build stats from categories data
export function buildStats(categories) {
  const stats = {};

  const getOrCreate = (name) => {
    if (!stats[name]) {
      stats[name] = { name, solo: 0, shared: 0, silver: 0, bronze: 0 };
    }
    return stats[name];
  };

  categories.forEach(cat => {
    if (!cat.gold?.names) return;

    // Gold winners
    cat.gold.names.forEach(name => {
      const p = getOrCreate(name);
      if (cat.gold.names.length > 1) {
        p.shared++;
      } else {
        p.solo++;
      }
    });

    // Silver
    if (cat.silver?.names) {
      cat.silver.names.forEach(name => getOrCreate(name).silver++);
    }

    // Bronze
    if (cat.bronze?.names) {
      cat.bronze.names.forEach(name => getOrCreate(name).bronze++);
    }
  });

  // Calculate totals
  const people = Object.values(stats).map(p => {
    p.gold = p.solo + p.shared;
    p.total = p.gold + p.silver + p.bronze;
    return p;
  });

  return {
    stats,
    people,
    winners: people.filter(p => p.gold > 0).length,
    podium: people.length,
    byGold: people.slice().sort((a, b) =>
      b.gold - a.gold || b.solo - a.solo || b.total - a.total || a.name.localeCompare(b.name)
    ),
    byName: people.slice().sort((a, b) => a.name.localeCompare(b.name))
  };
}

// Find landslide categories (single winner with many votes)
export function findLandslides(categories, minVotes = 10) {
  return categories
    .map((cat, index) => ({
      category: cat,
      index,
      votes: cat.gold?.votes || 0,
      isSolo: cat.gold?.names?.length === 1,
      margin: cat.gold?.names?.length === 1
        ? (cat.gold.votes - (cat.silver?.votes || 0))
        : 0
    }))
    .filter(x => x.isSolo && x.votes >= minVotes)
    .sort((a, b) => b.votes - a.votes);
}

// Render place (silver/bronze) HTML
export function renderPlace(label, data, highlightName = null) {
  if (!data || data === 'none') return '';

  if (data === 'singles') {
    return `<div class="place note">
      <span class="label">${label}</span>
      <span>Everyone else got 1 vote.</span>
    </div>`;
  }

  if (data.tie) {
    return `<div class="place">
      <span class="label">${label}</span>
      <span><b>${data.tie}-way tie</b> <span class="votes">&middot; ${data.votes} vote each</span></span>
    </div>`;
  }

  if (data.names) {
    const names = data.names.map(n =>
      highlightName === n ? `<mark>${esc(n)}</mark>` : esc(n)
    ).join(', ');
    const voteText = data.names.length > 1 ? ' each' : '';

    return `<div class="place">
      <span class="label">${label}</span>
      <span><b>${names}</b> <span class="votes">&middot; ${data.votes}${voteText}</span></span>
    </div>`;
  }

  return '';
}

// Render a category card
export function renderCategoryCard(category, index, options = {}) {
  const {
    highlightName = null,
    showLandslide = true,
    iconPath = 'icons/'
  } = options;

  const gold = category.gold.names;
  const sizeClass = gold.length === 1 ? 's1' : gold.length <= 3 ? 's2' : 's3';
  const isTie = gold.length > 1;
  const isLandslide = showLandslide && gold.length === 1 && category.gold.votes >= 10;

  const isHighlighted = highlightName && (
    gold.includes(highlightName) ||
    category.silver?.names?.includes(highlightName) ||
    category.bronze?.names?.includes(highlightName)
  );

  const goldNames = gold.map(n => {
    const escaped = highlightName === n ? `<mark>${esc(n)}</mark>` : esc(n);
    return `<span class="winner-name">${escaped}</span>`;
  }).join('');

  return `
    <article class="category-card ${highlightName ? (isHighlighted ? 'highlighted' : 'dimmed') : ''}"
             data-index="${index}"
             data-slug="${category.slug}">
      ${isLandslide ? '<span class="landslide-stamp">landslide</span>' : ''}
      <div class="card-header">
        <span class="card-number">No. ${pad(index + 1)}</span>
      </div>
      <h3 class="card-title">${esc(category.title)}</h3>
      <div class="gold-winner ${sizeClass}">
        <div class="winner-info">
          <span class="place-label">1st${isTie ? ` <em class="tie-badge">${gold.length}-way tie</em>` : ''}</span>
          <div class="winner-names">${goldNames}</div>
        </div>
        <div class="vote-count">
          <span class="vote-digits">${digits(category.gold.votes, iconPath)}</span>
          <small>${isTie ? 'votes each' : 'votes'}</small>
        </div>
      </div>
      ${renderPlace('2nd', category.silver, highlightName)}
      ${renderPlace('3rd', category.bronze, highlightName)}
    </article>
  `;
}

// Render person summary
export function renderPersonSummary(personStats, categories, iconPath = 'icons/') {
  const placements = [];

  categories.forEach((cat, index) => {
    const place = cat.gold?.names?.includes(personStats.name) ? 'gold' :
                  cat.silver?.names?.includes(personStats.name) ? 'silver' :
                  cat.bronze?.names?.includes(personStats.name) ? 'bronze' : null;
    if (place) {
      placements.push({ category: cat, index, place });
    }
  });

  return `
    <div class="person-summary">
      <h2 class="person-name">${esc(personStats.name)}</h2>
      <div class="medal-counts">
        <div class="medal-count">
          <span class="medal-digits">${digits(personStats.gold, iconPath)}</span>
          <small>1st</small>
        </div>
        <div class="medal-count">
          <span class="medal-digits">${digits(personStats.silver, iconPath)}</span>
          <small>2nd</small>
        </div>
        <div class="medal-count">
          <span class="medal-digits">${digits(personStats.bronze, iconPath)}</span>
          <small>3rd</small>
        </div>
      </div>
      <div class="person-categories">
        ${placements.map(p => `
          <div class="person-category" data-index="${p.index}">
            <span class="category-title">${esc(p.category.title)}</span>
            <span class="place-chip ${p.place}">${p.place === 'gold' ? '1st' : p.place === 'silver' ? '2nd' : '3rd'}</span>
          </div>
        `).join('')}
      </div>
    </div>
  `;
}

// Render dropdown for filtering by person
export function renderPersonDropdown(people, containerId = 'person-filter') {
  const sorted = people.slice().sort((a, b) => a.name.localeCompare(b.name));

  return `
    <div class="filter-controls" id="${containerId}">
      <label for="person-select">Find someone:</label>
      <select id="person-select">
        <option value="">Everyone</option>
        ${sorted.map(p => `<option value="${esc(p.name)}">${esc(p.name)}</option>`).join('')}
      </select>
      <button type="button" id="clear-filter" hidden>Clear</button>
    </div>
  `;
}

// Generate share card URL (for external share card generation)
export function getShareCardUrl(pollSlug, type, slug) {
  // type: 'c' for category, 'p' for person, 'h' for highlight
  return `/poll/${pollSlug}/share/${type}-${slug}-og.png`;
}

// Format data for data.json output
export function formatDataJson(pollSlug, pollTitle, pollYear, categories) {
  return {
    poll: {
      slug: pollSlug,
      title: pollTitle,
      year: pollYear
    },
    categories: categories.map(cat => ({
      slug: cat.slug || slugify(cat.title),
      title: cat.title,
      gold: cat.gold,
      silver: cat.silver || null,
      bronze: cat.bronze || null
    }))
  };
}
