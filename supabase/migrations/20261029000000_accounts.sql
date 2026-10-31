-- The Feral Collective: Accounts, Invite Codes, Profiles
-- Run this in the Supabase SQL Editor or via `supabase db push`
-- This migration is idempotent (safe to run multiple times)

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Check if current user is an admin
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND is_admin = true AND is_active = true
  );
$$;

-- Generate an unambiguous invite code (no 0/O/1/I/L)
CREATE OR REPLACE FUNCTION public.generate_invite_code()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  chars text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  result text := 'FERAL-';
  i int;
BEGIN
  FOR i IN 1..4 LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  END LOOP;
  result := result || '-';
  FOR i IN 1..4 LOOP
    result := result || substr(chars, floor(random() * length(chars) + 1)::int, 1);
  END LOOP;
  RETURN result;
END;
$$;

-- ============================================================================
-- TABLES
-- ============================================================================

-- Invite codes table
CREATE TABLE IF NOT EXISTS public.invite_codes (
  code text PRIMARY KEY,
  note text,
  created_by uuid REFERENCES auth.users ON DELETE SET NULL,
  max_uses int NOT NULL DEFAULT 1,
  uses int NOT NULL DEFAULT 0,
  expires_at timestamptz,
  revoked boolean NOT NULL DEFAULT false,
  grant_roles text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Invite redemptions audit trail
CREATE TABLE IF NOT EXISTS public.invite_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL REFERENCES public.invite_codes(code) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users ON DELETE SET NULL,
  redeemed_at timestamptz NOT NULL DEFAULT now()
);

-- Profiles table
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users ON DELETE CASCADE,
  handle text UNIQUE NOT NULL,
  display_name text,
  bio text,
  socials jsonb DEFAULT '{}',
  roles text[] DEFAULT '{}',
  is_admin boolean DEFAULT false,
  is_active boolean DEFAULT true,
  joined_at timestamptz DEFAULT now(),
  handle_changed_at timestamptz,
  -- Privacy consent
  privacy_policy_version text,
  privacy_accepted_at timestamptz,
  -- Avatar fields
  avatar_type text DEFAULT 'initial' CHECK (avatar_type IN ('initial', 'icon', 'photo')),
  avatar_icon text CHECK (avatar_icon IS NULL OR avatar_icon IN ('arrow', 'asterisk', 'burst-wide', 'burst', 'cloud', 'excl', 'ring', 'star', 'stars', 'zig')),
  avatar_bg text DEFAULT 'ink' CHECK (avatar_bg IN ('ink', 'paper', 'red')),
  avatar_path text,
  avatar_updated_at timestamptz,
  -- Cover
  cover_key text DEFAULT 'loop' CHECK (cover_key IN ('bold', 'drip', 'loop', 'orange', 'red')),
  -- Handle constraints
  CONSTRAINT handle_format CHECK (
    handle ~ '^[a-z0-9_.]{3,20}$'
  ),
  CONSTRAINT display_name_length CHECK (
    display_name IS NULL OR char_length(display_name) <= 24
  ),
  CONSTRAINT bio_length CHECK (
    bio IS NULL OR char_length(bio) <= 280
  )
);

-- Index for faster handle lookups
CREATE INDEX IF NOT EXISTS idx_profiles_handle ON public.profiles(handle);
CREATE INDEX IF NOT EXISTS idx_profiles_is_active ON public.profiles(is_active) WHERE is_active = true;

-- ============================================================================
-- TRIGGER: Validate invite code BEFORE user creation
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_invite_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  invite_code text;
  code_record record;
  handle_val text;
BEGIN
  -- Extract invite code from metadata
  invite_code := UPPER(TRIM(COALESCE(NEW.raw_user_meta_data->>'invite_code', '')));

  -- Skip validation for users created via dashboard/admin API (no invite_code in metadata)
  -- This allows bootstrapping the first admin
  IF invite_code = '' THEN
    RETURN NEW;
  END IF;

  -- Normalize: accept with or without FERAL- prefix
  IF invite_code !~ '^FERAL-' THEN
    invite_code := 'FERAL-' || invite_code;
  END IF;

  -- Atomically validate and consume the invite code
  UPDATE public.invite_codes
  SET uses = uses + 1
  WHERE code = invite_code
    AND NOT revoked
    AND uses < max_uses
    AND (expires_at IS NULL OR expires_at > now())
  RETURNING * INTO code_record;

  IF code_record IS NULL THEN
    RAISE EXCEPTION 'invalid_invite' USING HINT = 'The invite code is invalid, has been used, or has expired.';
  END IF;

  -- Record the redemption
  INSERT INTO public.invite_redemptions (code, user_id)
  VALUES (invite_code, NEW.id);

  -- Validate handle early (will be created in after trigger, but check now)
  handle_val := LOWER(TRIM(COALESCE(NEW.raw_user_meta_data->>'handle', '')));
  IF handle_val = '' THEN
    RAISE EXCEPTION 'handle_required' USING HINT = 'A handle is required.';
  END IF;
  IF handle_val !~ '^[a-z0-9_.]{3,20}$' THEN
    RAISE EXCEPTION 'handle_invalid' USING HINT = 'Handle must be 3-20 characters: lowercase letters, numbers, dots, underscores.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE handle = handle_val) THEN
    RAISE EXCEPTION 'handle_taken' USING HINT = 'That handle is already taken.';
  END IF;

  -- Store grant_roles in metadata for after trigger
  NEW.raw_user_meta_data := NEW.raw_user_meta_data || jsonb_build_object('_grant_roles', code_record.grant_roles);

  RETURN NEW;
END;
$$;

-- Drop existing trigger if it exists, then create
DROP TRIGGER IF EXISTS on_auth_user_validate_invite ON auth.users;
CREATE TRIGGER on_auth_user_validate_invite
  BEFORE INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_invite_code();

-- ============================================================================
-- TRIGGER: Create profile AFTER user creation
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_profile_for_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  handle_val text;
  display_name_val text;
  grant_roles_val text[];
BEGIN
  -- Extract from metadata
  handle_val := LOWER(TRIM(COALESCE(NEW.raw_user_meta_data->>'handle', '')));
  display_name_val := TRIM(COALESCE(NEW.raw_user_meta_data->>'display_name', ''));

  -- Get grant_roles from metadata (set by before trigger)
  IF NEW.raw_user_meta_data ? '_grant_roles' THEN
    SELECT array_agg(elem::text)
    INTO grant_roles_val
    FROM jsonb_array_elements_text(NEW.raw_user_meta_data->'_grant_roles') AS elem;
  ELSE
    grant_roles_val := '{}';
  END IF;

  -- Skip if no handle (user created via dashboard without invite flow)
  IF handle_val = '' THEN
    RETURN NEW;
  END IF;

  -- Create the profile
  INSERT INTO public.profiles (
    id,
    handle,
    display_name,
    roles,
    joined_at
  ) VALUES (
    NEW.id,
    handle_val,
    NULLIF(display_name_val, ''),
    COALESCE(grant_roles_val, '{}'),
    now()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_create_profile ON auth.users;
CREATE TRIGGER on_auth_user_create_profile
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.create_profile_for_user();

-- ============================================================================
-- TRIGGER: Protect profile fields from unauthorized changes
-- ============================================================================

CREATE OR REPLACE FUNCTION public.protect_profile_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  is_admin_user boolean;
BEGIN
  -- Prevent changing id or joined_at
  IF OLD.id != NEW.id THEN
    RAISE EXCEPTION 'cannot_change_id';
  END IF;
  IF OLD.joined_at != NEW.joined_at THEN
    RAISE EXCEPTION 'cannot_change_joined_at';
  END IF;

  -- Check if current user is admin
  SELECT public.is_admin() INTO is_admin_user;

  -- Non-admins cannot change protected fields
  IF NOT is_admin_user THEN
    IF OLD.roles IS DISTINCT FROM NEW.roles THEN
      RAISE EXCEPTION 'only_admins_can_change_roles';
    END IF;
    IF OLD.is_admin IS DISTINCT FROM NEW.is_admin THEN
      RAISE EXCEPTION 'only_admins_can_change_admin_status';
    END IF;
    IF OLD.is_active IS DISTINCT FROM NEW.is_active THEN
      RAISE EXCEPTION 'only_admins_can_change_active_status';
    END IF;
  END IF;

  -- Handle change rate limit (30 days)
  IF OLD.handle != NEW.handle THEN
    IF OLD.handle_changed_at IS NOT NULL AND OLD.handle_changed_at > now() - interval '30 days' THEN
      RAISE EXCEPTION 'handle_change_rate_limited' USING HINT = 'You can only change your handle once every 30 days.';
    END IF;
    NEW.handle_changed_at := now();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_profile_update_protect ON public.profiles;
CREATE TRIGGER on_profile_update_protect
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_profile_fields();

-- ============================================================================
-- RPC: Check handle availability (anonymous)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_available(h text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  normalized text;
  reserved text[] := ARRAY[
    'admin', 'mod', 'feral', 'support', 'me', 'null', 'undefined', 'api',
    'login', 'join', 'u', 'user', 'users', 'profile', 'profiles', 'settings',
    'calendar', 'events', 'privacy', 'terms', 'guidelines', 'help', 'about',
    'home', 'index', 'static', 'assets', 'images', 'js', 'css', 'fonts'
  ];
BEGIN
  normalized := LOWER(TRIM(h));

  -- Check format
  IF normalized !~ '^[a-z0-9_.]{3,20}$' THEN
    RETURN false;
  END IF;

  -- Check reserved
  IF normalized = ANY(reserved) THEN
    RETURN false;
  END IF;

  -- Check if taken
  RETURN NOT EXISTS (SELECT 1 FROM public.profiles WHERE handle = normalized);
END;
$$;

-- ============================================================================
-- RPC: Create invite code (admin only)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_invite(
  note text DEFAULT NULL,
  max_uses int DEFAULT 1,
  expires_in_days int DEFAULT NULL,
  grant_roles text[] DEFAULT '{}'
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  new_code text;
  exp_at timestamptz;
BEGIN
  -- Check admin
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  -- Generate unique code
  LOOP
    new_code := public.generate_invite_code();
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.invite_codes WHERE code = new_code);
  END LOOP;

  -- Calculate expiry
  IF expires_in_days IS NOT NULL AND expires_in_days > 0 THEN
    exp_at := now() + (expires_in_days || ' days')::interval;
  END IF;

  INSERT INTO public.invite_codes (code, note, created_by, max_uses, expires_at, grant_roles)
  VALUES (new_code, note, auth.uid(), max_uses, exp_at, COALESCE(grant_roles, '{}'));

  RETURN new_code;
END;
$$;

-- ============================================================================
-- RPC: Revoke invite code (admin only)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.revoke_invite(invite_code text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  UPDATE public.invite_codes
  SET revoked = true
  WHERE code = UPPER(TRIM(invite_code));

  RETURN FOUND;
END;
$$;

-- ============================================================================
-- RPC: Set member roles (admin only)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.set_member_roles(target_user_id uuid, new_roles text[])
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  UPDATE public.profiles
  SET roles = COALESCE(new_roles, '{}')
  WHERE id = target_user_id;

  RETURN FOUND;
END;
$$;

-- ============================================================================
-- RPC: Set member active status (admin only)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.set_member_active(target_user_id uuid, active boolean)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  UPDATE public.profiles
  SET is_active = active
  WHERE id = target_user_id;

  RETURN FOUND;
END;
$$;

-- ============================================================================
-- RPC: Export my data (GDPR/CCPA data portability)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.export_my_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  user_id uuid;
  user_email text;
  profile_data jsonb;
  invite_used text;
  result jsonb;
BEGIN
  user_id := auth.uid();
  IF user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Get email from auth.users
  SELECT email INTO user_email FROM auth.users WHERE id = user_id;

  -- Get profile
  SELECT to_jsonb(p.*) INTO profile_data
  FROM public.profiles p
  WHERE p.id = user_id;

  -- Get invite code used (if any)
  SELECT code INTO invite_used
  FROM public.invite_redemptions
  WHERE user_id = user_id
  LIMIT 1;

  result := jsonb_build_object(
    'exported_at', now(),
    'email', user_email,
    'profile', profile_data,
    'invite_code_used', invite_used
  );

  RETURN result;
END;
$$;

-- ============================================================================
-- RPC: Delete my account (GDPR/CCPA right to erasure)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  user_id uuid;
  issued_at timestamptz;
  admin_count int;
BEGIN
  user_id := auth.uid();
  IF user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- Require recently authenticated session (within 10 minutes)
  issued_at := to_timestamp((auth.jwt()->>'iat')::bigint);
  IF issued_at < now() - interval '10 minutes' THEN
    RAISE EXCEPTION 'session_too_old' USING HINT = 'Please sign in again to delete your account.';
  END IF;

  -- Prevent deleting the last admin
  SELECT COUNT(*) INTO admin_count
  FROM public.profiles
  WHERE is_admin = true AND is_active = true AND id != user_id;

  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = user_id AND is_admin = true) AND admin_count = 0 THEN
    RAISE EXCEPTION 'cannot_delete_last_admin' USING HINT = 'You are the only admin. Assign another admin before deleting your account.';
  END IF;

  -- Delete from auth.users (profiles will cascade)
  DELETE FROM auth.users WHERE id = user_id;

  RETURN true;
END;
$$;

-- ============================================================================
-- RPC: Admin clear avatar
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_clear_avatar(target_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_required';
  END IF;

  UPDATE public.profiles
  SET
    avatar_type = 'initial',
    avatar_icon = NULL,
    avatar_path = NULL,
    avatar_updated_at = now()
  WHERE id = target_user_id;

  -- Note: The actual storage object must be deleted by the admin in the client
  -- before or after calling this, using storage.from('avatars').remove()

  RETURN FOUND;
END;
$$;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

-- Enable RLS
ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invite_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Drop existing policies (idempotent)
DROP POLICY IF EXISTS "Admins can view invite codes" ON public.invite_codes;
DROP POLICY IF EXISTS "Admins can view redemptions" ON public.invite_redemptions;
DROP POLICY IF EXISTS "Members can view active profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Admins can update any profile" ON public.profiles;

-- Invite codes: admin select only, no direct insert/update/delete (use RPCs)
CREATE POLICY "Admins can view invite codes"
  ON public.invite_codes FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- Invite redemptions: admin select only
CREATE POLICY "Admins can view redemptions"
  ON public.invite_redemptions FOR SELECT
  TO authenticated
  USING (public.is_admin());

-- Profiles: authenticated + active members can view all active profiles
CREATE POLICY "Members can view active profiles"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (
    -- User must be active themselves
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = auth.uid() AND p.is_active = true)
    -- And target must be active (or it's their own profile)
    AND (is_active = true OR id = auth.uid())
  );

-- Profiles: users can update their own profile
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Profiles: admins can update any profile (for roles, deactivation, etc.)
CREATE POLICY "Admins can update any profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- Grant execute on public functions
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_available(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_invite(text, int, int, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_invite(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_member_roles(uuid, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_member_active(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.export_my_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_clear_avatar(uuid) TO authenticated;

-- ============================================================================
-- EXISTING CALENDAR: Update editors and events policies for admins
-- ============================================================================

-- Allow admins to also edit events (in addition to editors)
DO $$
BEGIN
  -- Only run if events table exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'events' AND table_schema = 'public') THEN
    -- Drop and recreate policies to include admin check
    DROP POLICY IF EXISTS "Admins can manage events" ON public.events;

    CREATE POLICY "Admins can manage events"
      ON public.events
      FOR ALL
      TO authenticated
      USING (public.is_admin())
      WITH CHECK (public.is_admin());
  END IF;
END $$;
