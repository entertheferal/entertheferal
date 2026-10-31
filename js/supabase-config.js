// Shared Supabase configuration for The Feral Collective
// This file is loaded by all pages that need Supabase access

window.FERAL = window.FERAL || {};
window.FERAL.SUPABASE_URL = 'https://nsxyiehkiktmzldqpoww.supabase.co';
window.FERAL.SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5zeHlpZWhraWt0bXpsZHFwb3d3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyMjk5MDgsImV4cCI6MjEwODgwNTkwOH0.Sq-SmLqlswYue-p20Ioc1ljIm39MR30YIXgdnY7d3lw';

// Privacy policy version - increment when policy changes materially
window.FERAL.PRIVACY_POLICY_VERSION = '2026-10-29-v1';

// Minimum age requirement (configurable by Heather)
window.FERAL.MIN_AGE = 18;

// Reserved handles that cannot be registered
window.FERAL.RESERVED_HANDLES = [
  'admin', 'mod', 'feral', 'support', 'me', 'null', 'undefined', 'api',
  'login', 'join', 'u', 'user', 'users', 'profile', 'profiles', 'settings',
  'calendar', 'events', 'privacy', 'terms', 'guidelines', 'help', 'about',
  'home', 'index', 'static', 'assets', 'images', 'js', 'css', 'fonts'
];

// Avatar icon allowlist (must match database check constraint)
window.FERAL.AVATAR_ICONS = [
  'arrow', 'asterisk', 'burst-wide', 'burst', 'cloud',
  'excl', 'ring', 'star', 'stars', 'zig'
];

// Cover allowlist (must match database check constraint)
window.FERAL.COVER_KEYS = ['bold', 'drip', 'loop', 'orange', 'red'];

// Social platform config
window.FERAL.SOCIALS = {
  instagram: { label: 'Instagram', url: 'https://instagram.com/' },
  tiktok: { label: 'TikTok', url: 'https://tiktok.com/@' },
  youtube: { label: 'YouTube', url: 'https://youtube.com/@' },
  discord: { label: 'Discord', url: null },
  site: { label: 'Website', url: null }
};
