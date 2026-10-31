# Feral Collective Accounts System

This document describes the accounts, authentication, and privacy features for The Feral Collective.

## Overview

- **Invite-only registration**: New users need a valid invite code
- **Passwordless auth**: 6-digit email codes via Supabase Auth
- **Member profiles**: Handle, display name, bio, socials, avatar, cover
- **Privacy-first**: GDPR/CCPA compliant with self-serve data export and deletion
- **Admin tools**: Create/revoke invites, manage members

## Setup

### Prerequisites

- Supabase project (same one as the calendar)
- Custom SMTP configured in Supabase (e.g., Resend)
- Vercel deployment

### 1. Run the migration

In the Supabase SQL Editor, paste and run:

```
supabase/migrations/20261029000000_accounts.sql
```

Or via CLI:
```bash
supabase db push
```

### 2. Configure Supabase Auth

1. **Authentication > URL Configuration**:
   - Set Site URL to your production domain
   - Add your domain and localhost to Redirect URLs

2. **Authentication > Email Templates**:
   - Edit "Confirm signup" template: replace link with `{{ .Token }}`
   - Edit "Magic Link" template: replace link with `{{ .Token }}`

3. **Storage > Create bucket**:
   - Name: `avatars`
   - Public: No
   - File size limit: 300KB
   - Allowed MIME types: `image/webp`

4. **Storage > avatars > Policies**:
   ```sql
   -- Allow authenticated users to read
   CREATE POLICY "Members can view avatars"
   ON storage.objects FOR SELECT
   TO authenticated
   USING (bucket_id = 'avatars');

   -- Allow users to manage their own folder
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

### 3. Bootstrap the first admin

1. Create a bootstrap invite code in the SQL Editor:
   ```sql
   INSERT INTO invite_codes (code, note, max_uses)
   VALUES ('FERAL-FOUNDER', 'bootstrap', 1);
   ```

2. Go to `/join` and sign up with that code

3. Grant yourself admin access:
   ```sql
   UPDATE profiles
   SET is_admin = true, roles = '{"Community manager"}'
   WHERE id = (SELECT id FROM auth.users WHERE email = 'your@email.com');
   ```

4. You can now access `/admin` to create more invite codes

## Pages

| Path | Description |
|------|-------------|
| `/join` | Signup with invite code |
| `/login` | Sign in for existing members |
| `/u/:handle` | Member profile (members-only) |
| `/admin` | Admin panel (admins only) |
| `/settings` | Account settings, data export, deletion |
| `/settings/profile` | Edit profile with live preview |
| `/privacy` | Privacy policy |
| `/guidelines` | Community guidelines |
| `/terms` | Terms of use |

## Database Schema

### Tables

- **invite_codes**: Invite codes with uses tracking
- **invite_redemptions**: Audit trail of code usage
- **profiles**: Member profiles, linked to auth.users

### Key Functions (RPCs)

- `handle_available(h)` - Check if handle is available (anon)
- `create_invite(...)` - Create invite code (admin)
- `revoke_invite(code)` - Revoke code (admin)
- `set_member_roles(...)` - Set member roles (admin)
- `set_member_active(...)` - Activate/deactivate member (admin)
- `export_my_data()` - Export all user data (authenticated)
- `delete_my_account()` - Delete account (authenticated, fresh session)
- `admin_clear_avatar(user_id)` - Clear member's avatar (admin)

## Authentication Flow

### Join (new user)
1. User enters invite code, email, handle, display name
2. Checks age + policy consent
3. `signInWithOtp({ email, shouldCreateUser: true, data: {...} })`
4. BEFORE INSERT trigger validates invite, consumes it
5. AFTER INSERT trigger creates profile
6. User enters 6-digit code from email
7. `verifyOtp({ email, token, type: 'email' })`
8. Redirect to profile

### Sign in (existing user)
1. User enters email
2. `signInWithOtp({ email, shouldCreateUser: false })`
3. User enters 6-digit code
4. `verifyOtp({ email, token, type: 'email' })`
5. Redirect to profile

## Privacy Features

### Data Export
- Settings > "Download my data"
- Returns JSON with email, profile, invite code used
- Includes signed URL to avatar if present

### Account Deletion
- Settings > "Delete my account"
- Requires fresh authentication (within 10 minutes)
- Requires typing handle to confirm
- Deletes auth.users row (profiles cascade)
- Clears avatar from storage
- Anonymizes invite_redemptions records
- Handle becomes available again

### Privacy Compliance
- GDPR: Right to access, rectify, erase, portability
- CCPA/CPRA: No selling/sharing of personal info
- LGPD, PIPEDA, UK GDPR: Similar rights supported
- Cookie consent: Not required (essential storage only)
- Photo EXIF: Stripped client-side before upload

## Privacy Checklist Before Launch

- [ ] Fill in [PLACEHOLDERS] in /privacy, /terms, /guidelines
- [ ] Have a lawyer review all three documents
- [ ] Sign Supabase data processing agreement
- [ ] Note Supabase project region for privacy policy
- [ ] Decide MIN_AGE value and update config
- [ ] Set BACKUP_RETENTION_DAYS in privacy policy
- [ ] Add privacy contact email
- [ ] Add legal entity name and address

## Security Features

- Row-level security on all tables
- No passwords (OTP only)
- No service_role key in frontend
- XSS protection (all user content escaped)
- Website links validated (https only)
- CSP headers configured
- Photo location data stripped
- Invite codes stripped from URL after prefill
- Rate limiting via Supabase

## Manual Steps (Supabase Dashboard)

1. Enable email auth with OTP
2. Configure SMTP provider
3. Edit email templates to show `{{ .Token }}`
4. Create avatars storage bucket with policies
5. Sign data processing agreement
6. Run migration
7. Bootstrap first admin

## Files

```
/js/supabase-config.js   - Shared config (URL, anon key)
/js/auth.js              - Auth utilities
/join/index.html         - Signup page
/login/index.html        - Login page
/u/index.html            - Profile page
/admin/index.html        - Admin panel
/settings/index.html     - Settings page
/settings/profile/index.html - Profile editor
/privacy/index.html      - Privacy policy
/guidelines/index.html   - Community guidelines
/terms/index.html        - Terms of use
/supabase/migrations/... - Database migration
```
