# Supabase Migrations

This folder contains database migrations for The Feral Collective.

## Running Migrations

### Option 1: SQL Editor (Recommended for initial setup)

1. Open your Supabase project dashboard
2. Go to SQL Editor
3. Copy the contents of each migration file
4. Run in order (by timestamp prefix)

### Option 2: Supabase CLI

```bash
# Install CLI if needed
npm install -g supabase

# Link to your project
supabase link --project-ref YOUR_PROJECT_REF

# Push migrations
supabase db push
```

## Migration Files

| File | Description |
|------|-------------|
| `20261029000000_accounts.sql` | Accounts, invite codes, profiles, privacy features |

## After Running Migrations

1. **Create avatars storage bucket** (Dashboard > Storage):
   - Name: `avatars`
   - Public: No
   - File size limit: 300KB
   - Allowed MIME types: `image/webp`

2. **Add storage policies** (Dashboard > Storage > avatars > Policies):
   ```sql
   -- Read access for authenticated users
   CREATE POLICY "Members can view avatars"
   ON storage.objects FOR SELECT
   TO authenticated
   USING (bucket_id = 'avatars');

   -- Write access for own folder only
   CREATE POLICY "Users can manage own avatar"
   ON storage.objects FOR ALL
   TO authenticated
   USING (
     bucket_id = 'avatars' AND
     (storage.foldername(name))[1] = auth.uid()::text
   )
   WITH CHECK (
     bucket_id = 'avatars' AND
     (storage.foldername(name))[1] = auth.uid()::text
   );
   ```

3. **Bootstrap first admin** (see docs/ACCOUNTS.md)

## Notes

- Migrations are idempotent (safe to run multiple times)
- Uses `CREATE OR REPLACE` and `DROP ... IF EXISTS` patterns
- RLS is enabled on all tables
