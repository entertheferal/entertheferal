# Feral Collective Calendar

Events calendar powered by Supabase for storage and authentication.

## Supabase Setup

### 1. Create Tables

Run this SQL in your Supabase SQL Editor:

```sql
-- Events table
create table public.events (
  id uuid default gen_random_uuid() primary key,
  type text not null check (type in ('event', 'workout', 'deadline', 'challenge')),
  label text,
  title text not null,
  starts_at timestamptz not null,
  ends_at timestamptz,
  location jsonb,
  about text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Editors table (emails allowed to manage events)
create table public.editors (
  email text primary key
);

-- Enable RLS
alter table public.events enable row level security;
alter table public.editors enable row level security;

-- Anyone can read events
create policy "Events are viewable by everyone"
  on public.events for select
  using (true);

-- Only editors can insert
create policy "Editors can insert events"
  on public.events for insert
  with check (
    auth.email() in (select email from public.editors)
  );

-- Only editors can update
create policy "Editors can update events"
  on public.events for update
  using (auth.email() in (select email from public.editors));

-- Only editors can delete
create policy "Editors can delete events"
  on public.events for delete
  using (auth.email() in (select email from public.editors));

-- Editors table: anyone can read (for auth check), only service role can modify
create policy "Editors readable by authenticated"
  on public.editors for select
  using (true);

-- Auto-update updated_at
create or replace function update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger events_updated_at
  before update on public.events
  for each row execute function update_updated_at();
```

### 2. Add Editors

Insert editor emails directly in Supabase Table Editor or SQL:

```sql
insert into public.editors (email) values ('you@example.com');
```

### 3. Enable Email Auth

In Supabase Dashboard:
1. Go to **Authentication → Providers**
2. Ensure **Email** is enabled
3. Under **Email Templates → Magic Link**, customize if desired
4. In **URL Configuration**, add your site URL to allowed redirect URLs

### 4. Configuration

Edit `config.js` with your Supabase project URL and anon key:

```js
window.FERAL = {
  SUPABASE_URL: 'https://YOUR_PROJECT.supabase.co',
  SUPABASE_ANON_KEY: 'YOUR_ANON_KEY'
};
```

## Deployment

This is a static site. Deploy to any static host:

### Vercel
```bash
cd calendar
npx vercel --prod
```

### Netlify
```bash
netlify deploy --prod --dir=.
```

### GitHub Pages
Push to a repo and enable Pages in Settings.

### Manual
Upload `index.html`, `config.js`, `events.json` (fallback), and `icons/` to any web server.

## How It Works

- **Public visitors** see all events in their local timezone
- **Editors** click "Editor sign in" in the footer, enter their email, and receive a magic link
- After signing in, if their email is in `public.editors`, they see "Manage events"
- Events are fetched from Supabase; if that fails, falls back to `events.json`

## Local Development

```bash
cd calendar
python3 -m http.server 8080
# Open http://localhost:8080
```

Note: Magic link emails won't work locally unless you configure Supabase redirect URLs to include `http://localhost:8080`.
