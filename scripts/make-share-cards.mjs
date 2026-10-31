#!/usr/bin/env node
/**
 * Generate share cards for Halloween Horror Movie Poll
 * Usage: node scripts/make-share-cards.mjs
 *
 * Generates:
 * - Winner cards (per category): c-<slug>-{story,feed,og}.png
 * - Personal cards (per gold winner): p-<slug>-{story,feed,og}.png
 * - Highlight cards (3 special): h-<slug>-story.png
 * - OG preview pages: c/<slug>/index.html, p/<slug>/index.html
 * - manifest.json
 */

import { chromium } from 'playwright';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const POLL_DIR = resolve(__dirname, '../poll/halloween-2026');
const SHARE_DIR = resolve(POLL_DIR, 'share');
const SITE_URL = 'https://entertheferal.com/poll/halloween-2026';

// Sizes
const SIZES = {
  story: { w: 1080, h: 1920 },
  feed: { w: 1080, h: 1350 },
  og: { w: 1200, h: 630 }
};

// Load data
const data = JSON.parse(readFileSync(resolve(POLL_DIR, 'data.json'), 'utf8'));
const captions = JSON.parse(readFileSync(resolve(POLL_DIR, 'captions.json'), 'utf8'));

// Slugify helper
const slugify = s => s.toLowerCase().replace(/['']/g,'').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');

// Build stats for personal cards
const stats = {};
data.categories.forEach(cat => {
  if (!cat.gold?.names) return;
  cat.gold.names.forEach(name => {
    if (!stats[name]) stats[name] = { name, golds: [], silver: 0, bronze: 0 };
    stats[name].golds.push({ title: cat.title, votes: cat.gold.votes });
  });
  if (cat.silver?.names) cat.silver.names.forEach(n => { if (!stats[n]) stats[n] = { name: n, golds: [], silver: 0, bronze: 0 }; stats[n].silver++; });
  if (cat.bronze?.names) cat.bronze.names.forEach(n => { if (!stats[n]) stats[n] = { name: n, golds: [], silver: 0, bronze: 0 }; stats[n].bronze++; });
});

// Get gold winners for personal cards
const goldWinners = Object.values(stats).filter(p => p.golds.length > 0);

// Highlights
const HIGHLIGHTS = [
  { slug: 'ed-d-mame', name: 'Ed D. Mame', title: 'Most golds won', caption: captions.highlights['ed-d-mame'].caption },
  { slug: 'heather', name: 'Heather', title: 'Biggest landslide', caption: captions.highlights.heather.caption },
  { slug: 'emmi', name: 'Emmi', title: 'Adopts every stray', caption: captions.highlights.emmi.caption }
];

// CSS for cards
const cardCSS = `
@font-face{font-family:'ED Fairville';src:url(file://${resolve(POLL_DIR, '../../fonts/ED-Fairville-Regular.woff2')}) format('woff2')}
@font-face{font-family:Archivo;src:url(file://${resolve(POLL_DIR, '../../fonts/archivo-400.woff2')}) format('woff2');font-weight:400}
@font-face{font-family:Archivo;src:url(file://${resolve(POLL_DIR, '../../fonts/archivo-500.woff2')}) format('woff2');font-weight:500}
@font-face{font-family:Archivo;src:url(file://${resolve(POLL_DIR, '../../fonts/archivo-600.woff2')}) format('woff2');font-weight:600}
@font-face{font-family:Archivo;src:url(file://${resolve(POLL_DIR, '../../fonts/archivo-700.woff2')}) format('woff2');font-weight:700}
@font-face{font-family:Archivo;src:url(file://${resolve(POLL_DIR, '../../fonts/archivo-800.woff2')}) format('woff2');font-weight:800}
@font-face{font-family:'IBM Plex Mono';src:url(file://${resolve(POLL_DIR, '../../fonts/ibm-plex-mono-400.woff2')}) format('woff2');font-weight:400}
@font-face{font-family:'IBM Plex Mono';src:url(file://${resolve(POLL_DIR, '../../fonts/ibm-plex-mono-500.woff2')}) format('woff2');font-weight:500}
:root{--paper:#f6f5f1;--ink:#0b0b0b;--soft:#4a4944;--red:#b3201a;--redi:#ff7a6e}
*{box-sizing:border-box;margin:0;padding:0}
body{margin:0;padding:0}
.card{position:relative;overflow:hidden;background:var(--paper);color:var(--ink);font-family:'IBM Plex Mono',monospace}
.card.ink{background:var(--ink);color:var(--paper)}
.card::after{content:"";position:absolute;inset:0;background:url(file://${resolve(POLL_DIR, 'art/grain.webp')});opacity:.08;mix-blend-mode:multiply;pointer-events:none}
.card.ink::after{opacity:.03}
.art{position:absolute;pointer-events:none;mix-blend-mode:multiply}
.ink .art{filter:invert(1);mix-blend-mode:screen}
.a1{right:-16%;top:7%;height:36%;opacity:1;transform:rotate(8deg)}
.story .a1{top:auto;bottom:20%;right:-14%;height:42%}
.feed .a1{top:auto;bottom:11%;right:-16%;height:46%}
.og .a1{right:-10%;top:5%;height:80%}
.a2{left:-5%;top:2%;height:28%;opacity:.4;transform:rotate(-8deg) scaleX(-1)}
.story .a2{left:-3%;top:4%;height:24%}
.feed .a2{left:-5%;top:3%;height:28%}
.og .a2{left:-3%;top:2%;height:40%}
.in{position:relative;z-index:2;height:100%;display:flex;flex-direction:column}
.story .in{padding:180px 84px 400px}
.feed .in{padding:100px 84px 120px}
.og .in{padding:60px 70px;flex-direction:row;align-items:center;gap:50px}
.sp{flex:1}
.eye{display:flex;align-items:center;gap:18px;font-size:28px;letter-spacing:.16em;text-transform:uppercase}
.og .eye{font-size:20px;gap:12px}
.eye i{width:20px;height:20px;background:var(--red);transform:rotate(45deg)}.ink .eye i{background:var(--redi)}
.og .eye i{width:14px;height:14px}
.cat{font:700 54px/1.1 Archivo,sans-serif;margin-bottom:14px;max-width:760px}
.feed .cat,.og .cat{font-size:46px}
.nm{font-family:'ED Fairville',Georgia,serif;font-weight:400;line-height:.92;letter-spacing:-.01em}
.story .nm{font-size:280px}
.feed .nm{font-size:220px}
.og .nm{font-size:140px}
.nm.sm{font-size:180px}.feed .nm.sm{font-size:150px}.og .nm.sm{font-size:100px}
.nm.xs{font-size:140px}.feed .nm.xs{font-size:110px}.og .nm.xs{font-size:80px}
.ul{width:520px;margin:6px 0 26px;mix-blend-mode:multiply;display:block}
.og .ul{width:300px;margin:6px 0 16px}
.vt{display:flex;align-items:flex-end;gap:22px;margin:28px 0 20px}
.og .vt{margin:16px 0 12px;gap:14px}
.vt span{font-size:32px;letter-spacing:.14em;text-transform:uppercase;padding-bottom:14px}
.og .vt span{font-size:22px;padding-bottom:8px}
.d{mix-blend-mode:multiply;display:block;height:280px}.feed .d{height:210px}.og .d{height:100px}
.ink .d{filter:invert(1);mix-blend-mode:screen}
.j{font:600 44px/1.2 Archivo,sans-serif;margin:8px 0 0;max-width:840px}
.feed .j,.og .j{font-size:38px;max-width:600px}
.og .j{font-size:26px;max-width:420px}
.lst{list-style:none;margin:14px 0 24px;display:grid;gap:12px;font:600 38px/1.2 Archivo,sans-serif}
.feed .lst{font-size:32px}
.og .lst{font-size:22px;gap:8px}
.lst li{display:flex;gap:20px;align-items:baseline;border-top:2px solid var(--ink);padding-top:12px}
.og .lst li{gap:12px;padding-top:8px}
.lst b{font:500 26px 'IBM Plex Mono',monospace;color:var(--red)}
.og .lst b{font-size:18px}
.ft{display:flex;justify-content:space-between;align-items:center;font-size:26px;letter-spacing:.12em;text-transform:uppercase;border-top:2px solid currentColor;padding-top:22px;margin-top:auto}
.og .ft{font-size:18px;padding-top:14px}
.left{display:flex;flex-direction:column;flex:1}
.right{flex:0 0 auto;text-align:right}
`;

// Generate digit images HTML
function digs(n, h = 280) {
  return String(n).split('').map(d =>
    `<img class="d" style="height:${h}px" src="file://${resolve(POLL_DIR, `icons/n${d}.webp`)}" alt="">`
  ).join('');
}

// Winner card HTML
function winnerCard(cat, size) {
  const isOG = size === 'og';
  const isStory = size === 'story';
  const names = cat.gold.names.join(cat.gold.names.length > 2 ? ', ' : ' & ');
  const nmClass = names.length > 12 ? (names.length > 20 ? 'xs' : 'sm') : '';
  const digH = isOG ? 100 : (isStory ? 280 : 210);
  const caption = captions.categories[cat.slug]?.caption || captions.defaults.winner;

  return `<!DOCTYPE html><html><head><style>${cardCSS}</style></head><body>
<div class="card ${size}" style="width:${SIZES[size].w}px;height:${SIZES[size].h}px">
  <img class="art a1" src="file://${resolve(POLL_DIR, 'art/red.webp')}" alt="">
  <div class="in">
    ${isOG ? '<div class="left">' : ''}
    <div class="eye"><i></i>Halloween Horror Movie Poll</div>
    ${isOG ? '' : '<div class="sp"></div>'}
    <div class="cat">${escHtml(cat.title)}</div>
    <div class="nm ${nmClass}">${escHtml(names)}</div>
    <img class="ul" src="file://${resolve(POLL_DIR, 'icons/underline.webp')}" alt="">
    <div class="vt">${digs(cat.gold.votes, digH)}<span>votes</span></div>
    <p class="j">${escHtml(caption)}</p>
    ${isOG ? '' : '<div class="sp"></div>'}
    <div class="ft"><span>The Feral Collective</span><span>entertheferal.com</span></div>
    ${isOG ? '</div>' : ''}
  </div>
</div>
</body></html>`;
}

// Personal card HTML
function personalCard(person, size) {
  const isOG = size === 'og';
  const isStory = size === 'story';
  const p = stats[person];
  const nmClass = person.length > 12 ? (person.length > 20 ? 'xs' : 'sm') : '';
  const digH = isOG ? 100 : (isStory ? 280 : 200);
  // Sort wins by votes (highest first)
  const wins = [...p.golds].sort((a, b) => b.votes - a.votes);
  const caption = 'In the movie, I am...';

  return `<!DOCTYPE html><html><head><style>${cardCSS}</style></head><body>
<div class="card ${size}" style="width:${SIZES[size].w}px;height:${SIZES[size].h}px">
  <img class="art a1" src="file://${resolve(POLL_DIR, 'art/drip.webp')}" alt="">
  <img class="art a2" src="file://${resolve(POLL_DIR, 'art/loop.webp')}" alt="">
  <div class="in">
    ${isOG ? '<div class="left">' : ''}
    <div class="eye"><i></i>My horror movie results</div>
    ${isOG ? '' : '<div class="sp"></div>'}
    <div class="cat">${escHtml(caption)}</div>
    <div class="nm ${nmClass}">${escHtml(person)}</div>
    <div class="vt">${digs(p.golds.length, digH)}<span>golds</span></div>
    <ul class="lst">${wins.map((w, i) => `<li><b>${i + 1}</b>${escHtml(w.title)}</li>`).join('')}</ul>
    ${isOG ? '' : '<div class="sp"></div>'}
    <div class="ft"><span>The Feral Collective</span><span>entertheferal.com</span></div>
    ${isOG ? '</div>' : ''}
  </div>
</div>
</body></html>`;
}

// Highlight card HTML (dark theme, story only)
function highlightCard(h) {
  const p = stats[h.name];
  const digH = 300;

  return `<!DOCTYPE html><html><head><style>${cardCSS}</style></head><body>
<div class="card ink story" style="width:${SIZES.story.w}px;height:${SIZES.story.h}px">
  <img class="art a1" src="file://${resolve(POLL_DIR, 'art/loop.webp')}" alt="">
  <div class="in">
    <div class="eye"><i></i>${escHtml(h.title)}</div>
    <div class="sp"></div>
    <div class="nm">${escHtml(h.name)}</div>
    <div class="vt">${digs(p.golds.length, digH)}<span>golds</span></div>
    <p class="j">${escHtml(h.caption)}</p>
    <div class="sp"></div>
    <div class="ft"><span>The Feral Collective</span><span>entertheferal.com</span></div>
  </div>
</div>
</body></html>`;
}

// OG preview page HTML
function ogPage(type, slug, title, description, imageUrl, redirectUrl) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escHtml(title)} | Halloween Horror Movie Poll</title>
<meta property="og:title" content="${escHtml(title)}">
<meta property="og:description" content="${escHtml(description)}">
<meta property="og:image" content="${imageUrl}">
<meta property="og:type" content="website">
<meta property="og:url" content="${SITE_URL}/${type}/${slug}/">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${escHtml(title)}">
<meta name="twitter:description" content="${escHtml(description)}">
<meta name="twitter:image" content="${imageUrl}">
<link rel="canonical" href="${SITE_URL}/${type}/${slug}/">
<meta http-equiv="refresh" content="0;url=${redirectUrl}">
<style>body{font-family:system-ui;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#f6f5f1}a{color:#b3201a}</style>
</head>
<body>
<p>Redirecting to <a href="${redirectUrl}">poll results</a>...</p>
</body>
</html>`;
}

function escHtml(s) {
  return String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
}

async function main() {
  console.log('Generating share cards...\n');

  // Ensure directories exist
  mkdirSync(SHARE_DIR, { recursive: true });

  const manifest = { generated: new Date().toISOString(), cards: [] };
  let errorCount = 0;

  // Launch browser
  const browser = await chromium.launch();
  const context = await browser.newContext({ deviceScaleFactor: 1 });

  async function capture(html, filename, width, height) {
    const page = await context.newPage();
    await page.setViewportSize({ width, height });
    await page.setContent(html, { waitUntil: 'networkidle' });

    // Wait for fonts
    await page.waitForTimeout(500);

    const path = resolve(SHARE_DIR, filename);
    await page.screenshot({ path, type: 'png' });
    await page.close();

    console.log(`  ${filename}`);
    return filename;
  }

  // Generate winner cards (per category)
  console.log('Winner cards:');
  for (const cat of data.categories) {
    for (const size of ['story', 'feed', 'og']) {
      const filename = `c-${cat.slug}-${size}.png`;
      try {
        await capture(winnerCard(cat, size), filename, SIZES[size].w, SIZES[size].h);
        manifest.cards.push({ type: 'winner', slug: cat.slug, size, file: filename });
      } catch (e) {
        console.error(`  ERROR: ${filename}: ${e.message}`);
        errorCount++;
      }
    }

    // Generate OG preview page
    const ogDir = resolve(POLL_DIR, 'c', cat.slug);
    mkdirSync(ogDir, { recursive: true });
    const ogHtml = ogPage(
      'c',
      cat.slug,
      cat.title,
      `${cat.gold.names.join(', ')} won with ${cat.gold.votes} votes`,
      `${SITE_URL}/share/c-${cat.slug}-og.png`,
      `/poll/halloween-2026/#c=${cat.slug}`
    );
    writeFileSync(resolve(ogDir, 'index.html'), ogHtml);
  }

  // Generate personal cards (per gold winner)
  console.log('\nPersonal cards:');
  for (const person of goldWinners) {
    const slug = slugify(person.name);
    for (const size of ['story', 'feed', 'og']) {
      const filename = `p-${slug}-${size}.png`;
      try {
        await capture(personalCard(person.name, size), filename, SIZES[size].w, SIZES[size].h);
        manifest.cards.push({ type: 'personal', slug, name: person.name, size, file: filename });
      } catch (e) {
        console.error(`  ERROR: ${filename}: ${e.message}`);
        errorCount++;
      }
    }

    // Generate OG preview page
    const ogDir = resolve(POLL_DIR, 'p', slug);
    mkdirSync(ogDir, { recursive: true });
    const p = stats[person.name];
    const ogHtml = ogPage(
      'p',
      slug,
      `${person.name}'s Horror Movie Results`,
      `${p.golds.length} gold${p.golds.length === 1 ? '' : 's'}, ${p.silver} silver${p.silver === 1 ? '' : 's'}, ${p.bronze} bronze${p.bronze === 1 ? '' : 's'}`,
      `${SITE_URL}/share/p-${slug}-og.png`,
      `/poll/halloween-2026/#p=${slug}`
    );
    writeFileSync(resolve(ogDir, 'index.html'), ogHtml);
  }

  // Generate highlight cards (story only)
  console.log('\nHighlight cards:');
  for (const h of HIGHLIGHTS) {
    const filename = `h-${h.slug}-story.png`;
    try {
      await capture(highlightCard(h), filename, SIZES.story.w, SIZES.story.h);
      manifest.cards.push({ type: 'highlight', slug: h.slug, name: h.name, file: filename });
    } catch (e) {
      console.error(`  ERROR: ${filename}: ${e.message}`);
      errorCount++;
    }
  }

  await browser.close();

  // Write manifest
  writeFileSync(resolve(SHARE_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2));
  console.log('\nManifest written.');

  // Summary
  console.log(`\nGenerated ${manifest.cards.length} cards.`);
  if (errorCount > 0) {
    console.error(`${errorCount} error(s) occurred.`);
    process.exit(1);
  }

  console.log('Done!');
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
