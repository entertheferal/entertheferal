# Claude Code prompt: accounts, invite-only registration, privacy, profiles

Paste or point Claude Code at this whole file. It has three parts that belong together, followed by the manual setup steps for the Supabase dashboard (those are for Heather, not Claude Code).

---

## PART 1: Accounts + INVITE-CODE-ONLY registration

Build user accounts and INVITE-CODE-ONLY registration for The Feral Collective site in ~/Developer/feral (static site on Vercel, no build step, Supabase backend). Read these first so you match the existing look and conventions:
- calendar/index.html (how Supabase is already used, config style, fonts, icons, paper/ink design tokens)
- design/profile/index.html (the approved profile design, desktop + phone)
- index.html, fonts/, images/

Add `design/` to a .vercelignore so the design mockups aren't deployed.

### Goal
Nobody can create an account without a valid invite code. Members get a profile page. Admins (Heather / "zzy") create and revoke invite codes. Awards and polls do NOT exist yet, so leave them out entirely (leave one HTML comment where the Awards section will go).

### Auth approach
Use Supabase Auth with email one-time 6-digit codes (not magic links, not passwords). Reasons: works on phones and in-app browsers, no password resets. Keep "Allow new users to sign up" ENABLED in Supabase; the gate is a database trigger, not the dashboard toggle.
- Join flow: signInWithOtp({ email, options: { shouldCreateUser: true, data: { invite_code, handle, display_name } } }), then a code-entry step with verifyOtp({ email, token, type: 'email' }).
- Sign-in flow (existing members): signInWithOtp({ email, options: { shouldCreateUser: false } }), then verifyOtp. Show a friendly message if the email has no account ("No account for that email. Need an invite code?").
- Never use or expose the service_role key. Only the anon key goes in the front end (put URL + anon key in one shared js/supabase-config.js; reuse the calendar's project if it already has one).

### Database (one idempotent migration file in supabase/migrations/, plus a README of how to run it)
1. invite_codes: code text primary key (uppercase), note text, created_by uuid references auth.users, max_uses int not null default 1, uses int not null default 0, expires_at timestamptz, revoked boolean not null default false, grant_roles text[] not null default '{}', created_at.
2. invite_redemptions: code, user_id, redeemed_at.
3. profiles: id uuid primary key references auth.users on delete cascade; handle text unique not null (lowercase, 3-20 chars, [a-z0-9_.], check constraint, plus a reserved list: admin, mod, feral, support, me, null, undefined, api, login, join, u, etc); display_name text (max 24); bio text (max 280); socials jsonb (keys: instagram, tiktok, youtube, discord, site; strip leading @, no URLs stored except site); roles text[] default '{}' (admin-assigned labels like 'Community manager'); is_admin boolean default false; is_active boolean default true; joined_at timestamptz default now().
4. BEFORE INSERT trigger on auth.users (security definer, set search_path = ''): read invite_code from new.raw_user_meta_data; reject (raise exception 'invalid_invite') unless the code exists, is not revoked, not expired, and uses < max_uses. Consume it atomically with a single UPDATE ... SET uses = uses + 1 WHERE code = ... AND uses < max_uses AND NOT revoked AND (expires_at IS NULL OR expires_at > now()) RETURNING, so two people can't both use a one-use code. Insert the invite_redemptions row. Normalize the code (trim, uppercase). Skip this check only for users created by the dashboard/admin API if that can be detected safely; otherwise document how to bootstrap.
5. AFTER INSERT trigger on auth.users: create the profiles row from metadata (handle, display_name), copying grant_roles from the invite. If the handle is taken or invalid, the whole signup must fail with a clear error.
6. RPC handle_available(h text) returns boolean (callable by anon) for live validation on the join form.
7. RPCs (security definer, admin only, check is_admin inside): create_invite(note, max_uses, expires_in_days, grant_roles) returns the code, generated server-side with gen_random_bytes using an unambiguous alphabet (no 0/O/1/I), formatted like FERAL-7K2Q-9XMD; revoke_invite(code); set_member_roles(user_id, roles); set_member_active(user_id, active).
8. RLS on everything. profiles: select only for authenticated members with is_active (profiles are members-only, NOT public); update only own row, and a trigger must stop non-admins from changing roles, is_admin, is_active, joined_at or id. invite_codes and invite_redemptions: admin select only, no direct insert/update/delete. Add an is_admin() helper function. Don't break the existing calendar `events` / `editors` policies; let admins also edit events.

### Pages (match the site design: paper background, ink, ED Fairville titles, Archivo body, IBM Plex Mono, hand-drawn icons from images/ or calendar/icons, ink band)
- /join (accepts ?code=FERAL-XXXX to prefill): invite code, email, handle (live availability check, debounced), display name, a required "I agree to the community guidelines and privacy policy" checkbox, then the 6-digit code step. Map database errors to friendly text ("That invite code isn't valid, has been used, or has expired.", "That handle is taken.").
- /login: email, then 6-digit code.
- /u/<handle>: the approved profile design from design/profile/index.html, real data. Include: cover, avatar, display name, @handle, Joined date, role tags, About (bio, with the empty state), Find me (only socials that are filled; empty state), and the owner-only "Edit profile" button. Desktop AND phone layouts as in the mockup. REMOVE for now: the stats row, the Awards section, the "Coming up" list, the star sticker. Signed-out visitors are redirected to /login. Unknown handle gets a friendly not-found.
- /admin (is_admin only, otherwise redirect): Invites tab (create with note / max uses / expiry / roles to grant, shows the code and a copy-able https://<site>/join?code=... link, list with uses/max, status active/used up/expired/revoked, revoke button) and Members tab (list, edit roles, deactivate/reactivate, clear avatar).
- Header on every page: the Feral wordmark, and when signed in a small menu (My profile, Calendar, Settings, Sign out); when signed out, "Sign in".
- Use a vercel.json rewrite so /u/:handle serves /u/index.html. Keep each page's JS in its own file under js/, use supabase-js from a pinned CDN version (jsdelivr) with a Subresource Integrity hash if feasible.

### Quality bars
- Mobile first: 16px inputs (no iOS zoom), 44px touch targets, visible focus, labels on every field, errors announced (aria-live), reduced-motion respected.
- Never put secrets in the repo. Escape all user content when rendering (bio, names) and only allow https:// for the website link.
- Lightweight test script (SQL or Playwright) proving: a user cannot sign up with no/invalid/expired/revoked/used-up code; a one-use code can't be redeemed twice in parallel; a normal member cannot read invite_codes, call create_invite, or change their own roles/is_admin; anonymous users cannot read profiles.
- Write docs/ACCOUNTS.md with the setup steps and how to bootstrap the first admin.
- Show a diff summary and the manual steps still needed in the Supabase dashboard.

---

## PART 2: Self-serve deletion, data export, privacy compliance (GDPR/UK GDPR, CCPA/CPRA, LGPD, PIPEDA and similar)

### Self-serve account deletion
- RPC delete_my_account() (security definer, set search_path = ''). It deletes the caller's row from auth.users (profiles cascades). It requires a RECENTLY authenticated session: reject unless auth.jwt()->>'iat' is within the last 10 minutes. The UI therefore sends a fresh 6-digit email code and verifies it right before the delete call, then also asks the user to type their @handle to confirm.
- Block deletion of the last remaining admin (raise a clear error).
- invite_redemptions.user_id must be ON DELETE SET NULL so the invite audit trail survives without personal data. invite_codes.created_by also SET NULL. NO table may keep email, handle, bio or socials after deletion.
- /settings (linked from the header menu): "Export my data", "Delete my account" (plain-language explanation of exactly what is deleted and what backups keep for up to N days), plus the email on file.
- After deletion: sign out, clear local storage, show a confirmation page; the handle becomes available again.
- Deletion is immediate and permanent. No soft-delete for user-initiated deletes (admin "deactivate" stays separate).

### Data export (access + portability)
- RPC export_my_data() returns one JSON object: auth email, profile fields, socials, roles, joined_at, invite code used (if any), avatar metadata plus a signed link to the photo, and any future tables via a clearly marked list so new features add themselves. Settings has a "Download my data" button that saves it as feral-data-<handle>.json.

### Correction + consent
- Members can edit all their profile fields at any time (rectification). Email change flow via supabase.auth.updateUser with re-verification.
- At join, the required checkbox links to the Privacy Policy and Community Guidelines. Store consent evidence in profiles: privacy_policy_version and accepted_at (versioned text, constant in code). If the policy version changes, show a re-accept prompt on next sign-in.
- Age gate: a required checkbox "I am at least [MIN_AGE] years old". MIN_AGE is a single config value (default 18; Heather will confirm). Do not collect date of birth.

### Data minimization + security
- Collect only: email, handle, display name, optional bio, socials, avatar. No phone, no real-name requirement, no location, no analytics, no tracking pixels, no ad tech.
- Profiles are members-only (RLS). Admin tooling must not export member emails in bulk to the browser; show email only on the member detail view.
- Do not log emails, codes or OTPs to the console. Strip invite codes from URLs after prefilling the join form (history.replaceState).
- Security headers in vercel.json: Content-Security-Policy (default-src 'self'; script-src 'self' plus the pinned supabase-js CDN; connect-src 'self' https://<project>.supabase.co; img-src 'self' data: blob: plus the Supabase storage host; font-src 'self'; frame-src only for services explicitly click-to-loaded), Referrer-Policy: strict-origin-when-cross-origin, X-Content-Type-Options: nosniff, Permissions-Policy that disables camera (except where the photo-capture feature needs it: use self), microphone, geolocation.

### Third-party loads (EU/UK ePrivacy + GDPR)
- Self-host fonts. Remove the Google Fonts <link> from every page (calendar included) and ship Archivo and IBM Plex Mono as local woff2 in fonts/ with @font-face (OFL-licensed; use @fontsource packages or the official releases). Loading Google Fonts from Google's servers sends visitors' IPs to Google and has been ruled a GDPR violation.
- The Spotify embed on the coming-soon page sets third-party cookies. Replace it with a click-to-load facade: a styled "Play Fade Away" button that only creates the iframe after the click, with one line saying "Loads Spotify, which may set cookies."
- Supabase stores the session in localStorage, which is strictly necessary for login. With no analytics or marketing cookies, no cookie banner is required; document this in the policy. If analytics are ever added they must be cookieless or consent-gated.

### Pages to create (match the site design; link from every footer)
- /privacy (Privacy Policy), /guidelines (Community Guidelines), /terms (short Terms of Use). Write real plain-English drafts, not lorem ipsum, with placeholders in [BRACKETS] for what Heather must supply: legal entity name and address, contact email for privacy requests, MIN_AGE, effective date, backup retention days. Add a visible TODO note that a lawyer should review before launch.
- The Privacy Policy covers, in this order, with headings and a short summary box at the top:
  1. Who we are and how to contact us (controller identity; privacy contact email; EU/UK representative placeholder if required).
  2. What we collect and why, as a table: data, purpose, lawful basis (contract / legitimate interests / consent), retention. Include profile photos (consent, optional) and note EXIF/location data is stripped.
  3. What we do NOT do: no selling or sharing of personal information (CCPA/CPRA statement), no advertising, no profiling, no automated decisions with legal effect.
  4. Who processes the data: Supabase (database, auth, storage), Vercel (hosting + request logs), [email provider e.g. Resend] (login code emails), Spotify only if the user clicks play. Mention data processing agreements and the regions used.
  5. International transfers (Standard Contractual Clauses / EU-US Data Privacy Framework where applicable).
  6. How long we keep data; backups purge within [N] days after deletion; invite audit records are anonymized.
  7. Your rights: access, export, correction, deletion, restriction, objection, withdrawing consent, complaining to a supervisory authority, plus California, Brazil (LGPD), Canada (PIPEDA), UK, Australia equivalents. Most rights are self-serve in Settings; the rest via the privacy email, answered within 30 days, no discrimination for exercising rights.
  8. Children: not for anyone under MIN_AGE; what we do if we learn a younger person joined (delete the account).
  9. Cookies and local storage (no tracking; one essential login item).
  10. Security measures (encryption in transit, access controls, row-level security) and a breach notification commitment (supervisory authority within 72 hours where required, affected members without undue delay).
  11. Changes to this policy (versioned, members notified by email for material changes).
  12. Date and version.
- Community Guidelines: short, in the brand voice. Respect, no harassment, no sharing others' private messages or info, invite codes are personal, profile pictures must be you, an icon or art and not someone else's photo or anything hateful or explicit, how to report someone, consequences (deactivation, avatar removal).
- Footer on every page: Privacy, Guidelines, Terms, and a mailto link to the privacy contact.

### Tests
- delete_my_account fails with a stale session and works with a fresh one; after deleting, no row anywhere references the user, the email can register again with a new invite, export_my_data matches the profile, the last admin can't delete themselves, and the CSP does not break login or the calendar.
- Update docs/ACCOUNTS.md with the deletion/export flows and a short "privacy checklist before launch".

---

## PART 3: Full profile editing, avatars and covers

### Edit profile (own profile only)
- A full-page editor at /settings/profile (also reachable from the "Edit profile" button on /u/<handle>) with a LIVE PREVIEW of the profile header that updates as they type. On phones, the preview sits above the form and the Save bar is sticky at the bottom.
- Editable: display name (max 24), bio (max 280, counter), avatar, cover, instagram, tiktok, youtube, discord, website (https only). Handle is editable at most once every 30 days, with the same live availability check as join; keep a handle_changed_at column and enforce it in a trigger. Old handle URLs may 404.
- Not editable by the member: roles, is_admin, is_active, joined_at (enforced in the DB, not just the UI).
- Unsaved-changes guard, inline validation, aria-live status ("Saved"), no data loss on a failed save.
- Email change lives in /settings (re-verified through Supabase), not in the profile editor.

### Avatar (the profile icon)
Add to profiles: avatar_type text check in ('initial','icon','photo') default 'initial', avatar_icon text, avatar_bg text check in ('ink','paper','red') default 'ink', avatar_path text, avatar_updated_at.
Three options in the picker, as tabs:
- Initial (default): the first letter of the display name in ED Fairville on the chosen background, exactly like the design in design/profile/index.html.
- Icon: one of the hand-drawn icons in design/profile/avatars/ (move them to images/avatars/; use an allowlist of keys validated by a DB check constraint) on the chosen background. Icons are black art, so invert them on the ink background and use multiply on the paper background.
- Photo: upload from camera roll or take a photo. Do all processing CLIENT-SIDE before upload: validate type (jpeg/png/webp/heic where the browser can decode it), crop to a square with a simple drag + zoom cropper, resize to 512x512, re-encode as WebP (about 0.85 quality, under 150 KB) by drawing to a canvas. The canvas re-encode strips EXIF including GPS location, which is a privacy requirement; say so in the UI ("We remove location data from your photo").
- Storage: a PRIVATE Supabase Storage bucket named avatars. Object path <user_id>/avatar.webp (fixed name, overwritten on change, cache-busted with avatar_updated_at). Storage RLS: members can read (authenticated), only the owner can insert/update/delete their own folder, enforced with (storage.foldername(name))[1] = auth.uid()::text, size limit 300 KB and allowed mime type image/webp on the bucket. Serve with createSignedUrls (batch where listing several people), never public URLs.
- Rendering: square with a 2px ink border to match the design; meaningful alt text (the display name) and an initial fallback if the image fails to load. Lazy-load and give images width/height to avoid layout shift.
- "Remove photo" button deletes the storage object and resets avatar_type.
- Admin moderation: RPC admin_clear_avatar(user_id) that also removes the storage object, from the Members tab.
- Account deletion must remove the avatar: the client first calls storage.from('avatars').remove([<uid>/avatar.webp]) and only then calls the delete RPC; also add an orphan sweep script in scripts/ that lists storage objects without a matching profile and removes them. Never rely on deleting storage.objects rows through SQL alone.

### Cover
- profiles.cover_key text with an allowlist check; options: the 5 ink-splash pieces in design/profile/covers/ (bold, drip, loop, red, orange). Move them to images/covers/. Show them as a row of thumbnails in the editor; selected state is a 2px ink border. Default 'loop'. No custom cover uploads for now.
- Render the chosen cover like the design (cropped, multiply blend, rotated as in the mockup); make sure each looks good at both desktop and phone widths, with per-cover positioning in a small config object if needed.

### Tests
- A member cannot write to another member's avatars folder, cannot change another profile, and cannot set an avatar_icon or cover_key outside the allowlist.
- Uploaded photo is square 512x512 WebP with no EXIF; oversize or non-image files are rejected with a friendly message.
- Handle change is blocked for 30 days after a change.
- After delete_my_account, the avatar object is gone and the profile 404s.
- Playwright screenshots of /settings/profile and /u/<handle> at 390px and 1280px for review; no horizontal overflow.

---

## MANUAL STEPS (Heather does these in Supabase; Claude Code cannot)
1. Use the same project as the calendar, or create one. Authentication > URL Configuration: set Site URL, add your domain and localhost to Redirect URLs.
2. Authentication > Email Templates: edit BOTH "Confirm signup" and "Magic Link" so the body shows {{ .Token }} (the 6-digit code) instead of a link.
3. Set up custom SMTP (Resend is easy). The built-in sender allows only a few emails an hour.
4. Optional: turn on CAPTCHA (Turnstile or hCaptcha) to slow down code guessing.
5. Sign the Supabase data processing agreement (Dashboard > Legal) and note which region the project is in for the policy.
6. Run the migration in the SQL editor, then bootstrap the first admin:

    insert into invite_codes (code, note, max_uses) values ('FERAL-FOUNDER', 'bootstrap', 1);
    -- join at /join with that code, then:
    update profiles set is_admin = true, roles = '{"Community manager"}'
    where id = (select id from auth.users where email = 'your@email.com');

7. Decide and fill in: legal entity name and address, privacy contact email, MIN_AGE, backup retention days. Have a lawyer review /privacy, /terms and /guidelines before launch.
