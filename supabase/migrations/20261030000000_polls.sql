-- The Feral Collective: Monthly Poll System
-- Run this in the Supabase SQL Editor or via `supabase db push`
-- This migration is idempotent (safe to run multiple times)

-- ============================================================================
-- TABLES
-- ============================================================================

-- polls table: main poll configuration
CREATE TABLE IF NOT EXISTS public.polls (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  slug text UNIQUE NOT NULL,
  title text NOT NULL,
  topic text,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'ideas_open', 'curating', 'voting_open', 'closed', 'published')),
  join_open_at timestamptz,
  join_close_at timestamptz,
  ideas_close_at timestamptz,
  voting_open_at timestamptz,
  voting_close_at timestamptz,
  published_at timestamptz,
  settings jsonb NOT NULL DEFAULT '{
    "votes_per_person_per_ballot": 3,
    "gold_cap": 3,
    "min_votes_for_award": 2,
    "max_categories": 20,
    "min_categories": 12,
    "min_participants": 10,
    "ideas_per_member": 3,
    "cap_fallback": "keep_winner",
    "tie_rule": "share_gold"
  }'::jsonb,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),

  -- Gate 1: voting_open_at must be >= join_close_at
  CONSTRAINT voting_after_join_close
    CHECK (voting_open_at IS NULL OR join_close_at IS NULL OR voting_open_at >= join_close_at)
);

-- poll_participants: opt-in joining
CREATE TABLE IF NOT EXISTS public.poll_participants (
  poll_id uuid REFERENCES public.polls(id) ON DELETE CASCADE,
  member_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at timestamptz DEFAULT now(),
  locked boolean DEFAULT false,
  PRIMARY KEY (poll_id, member_id)
);

-- ideas: suggestions from members
CREATE TABLE IF NOT EXISTS public.ideas (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  poll_id uuid REFERENCES public.polls(id) ON DELETE CASCADE NOT NULL,
  author_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  text text NOT NULL CHECK (char_length(text) <= 90),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined', 'merged')),
  decline_reason text,
  merged_into uuid REFERENCES public.ideas(id),
  flagged boolean DEFAULT false,
  flag_reason text,
  created_at timestamptz DEFAULT now()
);

-- idea_upvotes: community votes for ideas
CREATE TABLE IF NOT EXISTS public.idea_upvotes (
  idea_id uuid REFERENCES public.ideas(id) ON DELETE CASCADE,
  member_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (idea_id, member_id)
);

-- categories: created from accepted ideas when voting opens
CREATE TABLE IF NOT EXISTS public.categories (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  poll_id uuid REFERENCES public.polls(id) ON DELETE CASCADE NOT NULL,
  idea_id uuid REFERENCES public.ideas(id),
  title text NOT NULL,
  position int NOT NULL
);

-- ballots_cast: records THAT someone voted (no link to votes)
CREATE TABLE IF NOT EXISTS public.ballots_cast (
  poll_id uuid REFERENCES public.polls(id) ON DELETE CASCADE,
  member_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  cast_at timestamptz DEFAULT now(),
  PRIMARY KEY (poll_id, member_id)
);

-- votes: ANONYMOUS - no member_id, only ballot_token
CREATE TABLE IF NOT EXISTS public.votes (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  poll_id uuid REFERENCES public.polls(id) ON DELETE CASCADE NOT NULL,
  category_id uuid REFERENCES public.categories(id) ON DELETE CASCADE NOT NULL,
  ballot_token uuid NOT NULL,
  nominee_id uuid REFERENCES auth.users(id) ON DELETE SET NULL NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS votes_token_idx ON public.votes(ballot_token);
CREATE INDEX IF NOT EXISTS votes_category_idx ON public.votes(category_id);
CREATE INDEX IF NOT EXISTS votes_poll_idx ON public.votes(poll_id);

-- results: computed on close, frozen on publish
CREATE TABLE IF NOT EXISTS public.results (
  poll_id uuid REFERENCES public.polls(id) ON DELETE CASCADE,
  category_id uuid REFERENCES public.categories(id) ON DELETE CASCADE,
  raw jsonb NOT NULL,
  final jsonb,
  reason text,
  PRIMARY KEY (poll_id, category_id)
);

-- audit_log: track admin actions
CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  action text NOT NULL,
  target_type text,
  target_id uuid,
  details jsonb,
  created_at timestamptz DEFAULT now()
);

-- share_opt_outs: members who opt out of being shown in results
CREATE TABLE IF NOT EXISTS public.share_opt_outs (
  poll_id uuid REFERENCES public.polls(id) ON DELETE CASCADE,
  member_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (poll_id, member_id)
);

-- Additional indexes for performance
CREATE INDEX IF NOT EXISTS idx_ideas_poll_id ON public.ideas(poll_id);
CREATE INDEX IF NOT EXISTS idx_ideas_author_id ON public.ideas(author_id);
CREATE INDEX IF NOT EXISTS idx_categories_poll_id ON public.categories(poll_id);
CREATE INDEX IF NOT EXISTS idx_poll_participants_poll_id ON public.poll_participants(poll_id);
CREATE INDEX IF NOT EXISTS idx_polls_status ON public.polls(status);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poll_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ideas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.idea_upvotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ballots_cast ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.results ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.share_opt_outs ENABLE ROW LEVEL SECURITY;

-- Drop existing policies (idempotent)
DROP POLICY IF EXISTS "Polls readable by all" ON public.polls;
DROP POLICY IF EXISTS "Polls writable by admin" ON public.polls;
DROP POLICY IF EXISTS "Participants readable" ON public.poll_participants;
DROP POLICY IF EXISTS "Join own" ON public.poll_participants;
DROP POLICY IF EXISTS "Leave own before lock" ON public.poll_participants;
DROP POLICY IF EXISTS "Ideas select" ON public.ideas;
DROP POLICY IF EXISTS "Upvotes select" ON public.idea_upvotes;
DROP POLICY IF EXISTS "Upvote own" ON public.idea_upvotes;
DROP POLICY IF EXISTS "Remove own upvote" ON public.idea_upvotes;
DROP POLICY IF EXISTS "Categories readable" ON public.categories;
DROP POLICY IF EXISTS "Own ballot status" ON public.ballots_cast;
DROP POLICY IF EXISTS "Votes no direct access" ON public.votes;
DROP POLICY IF EXISTS "Results readable when published" ON public.results;
DROP POLICY IF EXISTS "Audit admin only" ON public.audit_log;
DROP POLICY IF EXISTS "Share opt-outs readable" ON public.share_opt_outs;
DROP POLICY IF EXISTS "Opt out own" ON public.share_opt_outs;
DROP POLICY IF EXISTS "Remove own opt-out" ON public.share_opt_outs;

-- polls: anyone can read, admin can write
CREATE POLICY "Polls readable by all" ON public.polls
  FOR SELECT USING (true);

CREATE POLICY "Polls writable by admin" ON public.polls
  FOR ALL USING (public.is_admin());

-- poll_participants: members see all, can join/leave own
CREATE POLICY "Participants readable" ON public.poll_participants
  FOR SELECT USING (true);

CREATE POLICY "Join own" ON public.poll_participants
  FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Leave own before lock" ON public.poll_participants
  FOR DELETE USING (member_id = auth.uid() AND NOT locked);

-- ideas: everyone can see text, authors see own status details, admins see all
CREATE POLICY "Ideas select" ON public.ideas
  FOR SELECT USING (true);

-- idea_upvotes: see all, manage own
CREATE POLICY "Upvotes select" ON public.idea_upvotes
  FOR SELECT USING (true);

CREATE POLICY "Upvote own" ON public.idea_upvotes
  FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Remove own upvote" ON public.idea_upvotes
  FOR DELETE USING (member_id = auth.uid());

-- categories: readable when voting or later
CREATE POLICY "Categories readable" ON public.categories
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.polls
      WHERE id = poll_id AND status IN ('voting_open', 'closed', 'published')
    )
  );

-- Admin can manage categories
CREATE POLICY "Categories admin" ON public.categories
  FOR ALL USING (public.is_admin());

-- ballots_cast: member sees own only
CREATE POLICY "Own ballot status" ON public.ballots_cast
  FOR SELECT USING (member_id = auth.uid());

-- Admin can see ballots_cast to know turnout
CREATE POLICY "Admin ballot status" ON public.ballots_cast
  FOR SELECT USING (public.is_admin());

-- votes: NO DIRECT ACCESS - always via RPC for anonymity
CREATE POLICY "Votes no direct access" ON public.votes
  FOR SELECT USING (false);

-- results: readable only when published (Gate 2 & 3)
CREATE POLICY "Results readable when published" ON public.results
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.polls
      WHERE id = poll_id AND status = 'published'
    )
  );

-- Admin can manage results
CREATE POLICY "Results admin" ON public.results
  FOR ALL USING (public.is_admin());

-- audit_log: admin only
CREATE POLICY "Audit admin only" ON public.audit_log
  FOR SELECT USING (public.is_admin());

-- share_opt_outs: manage own
CREATE POLICY "Share opt-outs readable" ON public.share_opt_outs
  FOR SELECT USING (member_id = auth.uid() OR public.is_admin());

CREATE POLICY "Opt out own" ON public.share_opt_outs
  FOR INSERT WITH CHECK (member_id = auth.uid());

CREATE POLICY "Remove own opt-out" ON public.share_opt_outs
  FOR DELETE USING (member_id = auth.uid());

-- ============================================================================
-- RPC FUNCTIONS
-- ============================================================================

-- Get the current active poll
CREATE OR REPLACE FUNCTION public.get_current_poll()
RETURNS public.polls
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT *
  FROM public.polls
  WHERE status NOT IN ('draft', 'published')
  ORDER BY created_at DESC
  LIMIT 1;
$$;

-- Get poll by slug
CREATE OR REPLACE FUNCTION public.get_poll_by_slug(p_slug text)
RETURNS public.polls
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT *
  FROM public.polls
  WHERE slug = p_slug
  LIMIT 1;
$$;

-- Join a poll
CREATE OR REPLACE FUNCTION public.join_poll(p_poll_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_member_id uuid;
BEGIN
  v_member_id := auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  -- Check poll is accepting joins
  IF v_poll.status NOT IN ('ideas_open', 'curating') THEN
    RAISE EXCEPTION 'This poll is not accepting new participants';
  END IF;

  -- Check join window
  IF v_poll.join_open_at IS NOT NULL AND v_poll.join_open_at > now() THEN
    RAISE EXCEPTION 'Joining has not opened yet';
  END IF;
  IF v_poll.join_close_at IS NOT NULL AND v_poll.join_close_at < now() THEN
    RAISE EXCEPTION 'Joining has closed';
  END IF;

  -- Check if already joined
  IF EXISTS (
    SELECT 1 FROM public.poll_participants
    WHERE poll_id = p_poll_id AND member_id = v_member_id
  ) THEN
    RAISE EXCEPTION 'You have already joined this poll';
  END IF;

  -- Join
  INSERT INTO public.poll_participants (poll_id, member_id)
  VALUES (p_poll_id, v_member_id);

  RETURN true;
END;
$$;

-- Leave a poll (before voting starts)
CREATE OR REPLACE FUNCTION public.leave_poll(p_poll_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_participant record;
  v_member_id uuid;
BEGIN
  v_member_id := auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_participant
  FROM public.poll_participants
  WHERE poll_id = p_poll_id AND member_id = v_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You are not in this poll';
  END IF;

  IF v_participant.locked THEN
    RAISE EXCEPTION 'Voting has started - you cannot leave now';
  END IF;

  -- Delete participation and related data
  DELETE FROM public.idea_upvotes
  WHERE member_id = v_member_id
    AND idea_id IN (SELECT id FROM public.ideas WHERE poll_id = p_poll_id);

  DELETE FROM public.ideas
  WHERE poll_id = p_poll_id AND author_id = v_member_id;

  DELETE FROM public.poll_participants
  WHERE poll_id = p_poll_id AND member_id = v_member_id;

  RETURN true;
END;
$$;

-- Submit an idea
CREATE OR REPLACE FUNCTION public.submit_idea(p_poll_id uuid, p_text text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_member_id uuid;
  v_idea_count int;
  v_max_ideas int;
  v_new_id uuid;
BEGIN
  v_member_id := auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  -- Check status
  IF v_poll.status != 'ideas_open' THEN
    RAISE EXCEPTION 'Ideas are not being accepted';
  END IF;

  -- Check ideas window
  IF v_poll.ideas_close_at IS NOT NULL AND v_poll.ideas_close_at < now() THEN
    RAISE EXCEPTION 'Idea submission has closed';
  END IF;

  -- Check participation
  IF NOT EXISTS (
    SELECT 1 FROM public.poll_participants
    WHERE poll_id = p_poll_id AND member_id = v_member_id
  ) THEN
    RAISE EXCEPTION 'You must join the poll to submit ideas';
  END IF;

  -- Check idea limit
  v_max_ideas := COALESCE((v_poll.settings->>'ideas_per_member')::int, 3);
  SELECT COUNT(*) INTO v_idea_count
  FROM public.ideas
  WHERE poll_id = p_poll_id AND author_id = v_member_id;

  IF v_idea_count >= v_max_ideas THEN
    RAISE EXCEPTION 'You have reached the maximum number of ideas (%)' , v_max_ideas;
  END IF;

  -- Validate text length
  IF char_length(TRIM(p_text)) < 10 THEN
    RAISE EXCEPTION 'Idea must be at least 10 characters';
  END IF;
  IF char_length(p_text) > 90 THEN
    RAISE EXCEPTION 'Idea must be 90 characters or less';
  END IF;

  -- Insert idea
  INSERT INTO public.ideas (poll_id, author_id, text)
  VALUES (p_poll_id, v_member_id, TRIM(p_text))
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

-- Toggle upvote on an idea
CREATE OR REPLACE FUNCTION public.toggle_idea_upvote(p_idea_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_idea record;
  v_poll record;
  v_member_id uuid;
  v_exists boolean;
BEGIN
  v_member_id := auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_idea FROM public.ideas WHERE id = p_idea_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Idea not found';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = v_idea.poll_id;

  -- Check status
  IF v_poll.status != 'ideas_open' THEN
    RAISE EXCEPTION 'Upvoting is closed';
  END IF;

  -- Check participation
  IF NOT EXISTS (
    SELECT 1 FROM public.poll_participants
    WHERE poll_id = v_idea.poll_id AND member_id = v_member_id
  ) THEN
    RAISE EXCEPTION 'You must join the poll to upvote ideas';
  END IF;

  -- Toggle upvote
  SELECT EXISTS (
    SELECT 1 FROM public.idea_upvotes
    WHERE idea_id = p_idea_id AND member_id = v_member_id
  ) INTO v_exists;

  IF v_exists THEN
    DELETE FROM public.idea_upvotes
    WHERE idea_id = p_idea_id AND member_id = v_member_id;
    RETURN false; -- upvote removed
  ELSE
    INSERT INTO public.idea_upvotes (idea_id, member_id)
    VALUES (p_idea_id, v_member_id);
    RETURN true; -- upvote added
  END IF;
END;
$$;

-- Get ideas with upvote counts (for display)
CREATE OR REPLACE FUNCTION public.get_poll_ideas(p_poll_id uuid)
RETURNS TABLE (
  id uuid,
  text text,
  status text,
  upvote_count bigint,
  user_upvoted boolean,
  is_own boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_member_id uuid;
BEGIN
  v_member_id := auth.uid();

  RETURN QUERY
  SELECT
    i.id,
    i.text,
    i.status,
    COALESCE(u.cnt, 0) AS upvote_count,
    EXISTS (
      SELECT 1 FROM public.idea_upvotes iu
      WHERE iu.idea_id = i.id AND iu.member_id = v_member_id
    ) AS user_upvoted,
    (i.author_id = v_member_id) AS is_own,
    i.created_at
  FROM public.ideas i
  LEFT JOIN (
    SELECT idea_id, COUNT(*) as cnt
    FROM public.idea_upvotes
    GROUP BY idea_id
  ) u ON u.idea_id = i.id
  WHERE i.poll_id = p_poll_id
  ORDER BY COALESCE(u.cnt, 0) DESC, i.created_at ASC;
END;
$$;

-- Get ideas with full details for admin curation
CREATE OR REPLACE FUNCTION public.get_poll_ideas_admin(p_poll_id uuid)
RETURNS TABLE (
  id uuid,
  text text,
  status text,
  decline_reason text,
  merged_into uuid,
  flagged boolean,
  flag_reason text,
  author_id uuid,
  author_handle text,
  author_name text,
  upvote_count bigint,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  RETURN QUERY
  SELECT
    i.id,
    i.text,
    i.status,
    i.decline_reason,
    i.merged_into,
    i.flagged,
    i.flag_reason,
    i.author_id,
    p.handle AS author_handle,
    p.display_name AS author_name,
    COALESCE(u.cnt, 0) AS upvote_count,
    i.created_at
  FROM public.ideas i
  LEFT JOIN public.profiles p ON p.id = i.author_id
  LEFT JOIN (
    SELECT idea_id, COUNT(*) as cnt
    FROM public.idea_upvotes
    GROUP BY idea_id
  ) u ON u.idea_id = i.id
  WHERE i.poll_id = p_poll_id
  ORDER BY COALESCE(u.cnt, 0) DESC, i.created_at ASC;
END;
$$;

-- Admin: Update idea status
CREATE OR REPLACE FUNCTION public.update_idea_status(
  p_idea_id uuid,
  p_status text,
  p_reason text DEFAULT NULL,
  p_merged_into uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  IF p_status NOT IN ('pending', 'accepted', 'declined', 'merged') THEN
    RAISE EXCEPTION 'Invalid status';
  END IF;

  UPDATE public.ideas
  SET
    status = p_status,
    decline_reason = CASE WHEN p_status = 'declined' THEN p_reason ELSE decline_reason END,
    merged_into = CASE WHEN p_status = 'merged' THEN p_merged_into ELSE merged_into END
  WHERE id = p_idea_id;

  -- Log action
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'update_idea_status', 'idea', p_idea_id,
    jsonb_build_object('status', p_status, 'reason', p_reason));

  RETURN FOUND;
END;
$$;

-- Admin: Create category from idea
CREATE OR REPLACE FUNCTION public.create_category(
  p_poll_id uuid,
  p_idea_id uuid,
  p_title text,
  p_position int
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  INSERT INTO public.categories (poll_id, idea_id, title, position)
  VALUES (p_poll_id, p_idea_id, p_title, p_position)
  RETURNING id INTO v_new_id;

  -- Mark idea as accepted if linked
  IF p_idea_id IS NOT NULL THEN
    UPDATE public.ideas SET status = 'accepted' WHERE id = p_idea_id;
  END IF;

  RETURN v_new_id;
END;
$$;

-- Admin: Transition poll status (enforces state machine and gates)
CREATE OR REPLACE FUNCTION public.transition_poll_status(p_poll_id uuid, p_new_status text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_cat_count int;
  v_part_count int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  -- Validate transition
  CASE v_poll.status
    WHEN 'draft' THEN
      IF p_new_status != 'ideas_open' THEN
        RAISE EXCEPTION 'From draft, can only move to ideas_open';
      END IF;
    WHEN 'ideas_open' THEN
      IF p_new_status != 'curating' THEN
        RAISE EXCEPTION 'From ideas_open, can only move to curating';
      END IF;
    WHEN 'curating' THEN
      IF p_new_status != 'voting_open' THEN
        RAISE EXCEPTION 'From curating, can only move to voting_open';
      END IF;
      -- Gate 1: Check join is closed
      IF v_poll.join_close_at IS NOT NULL AND v_poll.join_close_at > now() THEN
        RAISE EXCEPTION 'Joining must be closed before voting opens';
      END IF;
      -- Lock all participants
      UPDATE public.poll_participants SET locked = true WHERE poll_id = p_poll_id;
      -- Check minimums
      SELECT COUNT(*) INTO v_cat_count FROM public.categories WHERE poll_id = p_poll_id;
      SELECT COUNT(*) INTO v_part_count FROM public.poll_participants WHERE poll_id = p_poll_id;
      IF v_cat_count < COALESCE((v_poll.settings->>'min_categories')::int, 12) THEN
        RAISE EXCEPTION 'Need at least % categories', COALESCE((v_poll.settings->>'min_categories')::int, 12);
      END IF;
      IF v_part_count < COALESCE((v_poll.settings->>'min_participants')::int, 10) THEN
        RAISE EXCEPTION 'Need at least % participants', COALESCE((v_poll.settings->>'min_participants')::int, 10);
      END IF;
    WHEN 'voting_open' THEN
      IF p_new_status != 'closed' THEN
        RAISE EXCEPTION 'From voting_open, can only move to closed';
      END IF;
    WHEN 'closed' THEN
      IF p_new_status NOT IN ('voting_open', 'published') THEN
        RAISE EXCEPTION 'From closed, can move to voting_open (reopen) or published';
      END IF;
    WHEN 'published' THEN
      RAISE EXCEPTION 'Cannot transition from published';
  END CASE;

  -- Apply transition
  UPDATE public.polls
  SET
    status = p_new_status,
    voting_open_at = CASE WHEN p_new_status = 'voting_open' THEN now() ELSE voting_open_at END,
    voting_close_at = CASE WHEN p_new_status = 'closed' THEN now() ELSE voting_close_at END,
    published_at = CASE WHEN p_new_status = 'published' THEN now() ELSE published_at END,
    updated_at = now()
  WHERE id = p_poll_id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'transition_status', 'poll', p_poll_id,
    jsonb_build_object('from', v_poll.status, 'to', p_new_status));
END;
$$;

-- Submit ballot (anonymous voting)
-- picks format: [{"category_id": uuid, "nominee_id": uuid}, ...]
-- Returns new ballot_token
CREATE OR REPLACE FUNCTION public.submit_ballot(
  p_poll_id uuid,
  p_picks jsonb,
  p_previous_token uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_new_token uuid;
  v_member_id uuid;
  v_pick record;
  v_nominee_counts jsonb;
  v_limit int;
  v_category_ids uuid[];
  v_seen_categories uuid[];
BEGIN
  v_member_id := auth.uid();
  IF v_member_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  -- Gate 2: Check voting is open
  IF v_poll.status != 'voting_open' THEN
    RAISE EXCEPTION 'Voting is not open';
  END IF;

  -- Check member is participant
  IF NOT EXISTS (
    SELECT 1 FROM public.poll_participants
    WHERE poll_id = p_poll_id AND member_id = v_member_id AND locked = true
  ) THEN
    RAISE EXCEPTION 'You must be a locked participant to vote';
  END IF;

  -- Check not already voted (unless editing with valid token)
  IF EXISTS (
    SELECT 1 FROM public.ballots_cast
    WHERE poll_id = p_poll_id AND member_id = v_member_id
  ) AND p_previous_token IS NULL THEN
    RAISE EXCEPTION 'You have already voted. Use your ballot key to edit.';
  END IF;

  -- Validate previous token if editing
  IF p_previous_token IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.votes
      WHERE poll_id = p_poll_id AND ballot_token = p_previous_token
    ) THEN
      RAISE EXCEPTION 'Invalid ballot token';
    END IF;
  END IF;

  v_limit := COALESCE((v_poll.settings->>'votes_per_person_per_ballot')::int, 3);
  v_nominee_counts := '{}'::jsonb;
  v_seen_categories := '{}';

  -- Get valid category IDs for this poll
  SELECT array_agg(id) INTO v_category_ids FROM public.categories WHERE poll_id = p_poll_id;

  -- Validate picks
  FOR v_pick IN
    SELECT * FROM jsonb_to_recordset(p_picks) AS x(category_id uuid, nominee_id uuid)
  LOOP
    -- Check category belongs to this poll
    IF NOT (v_pick.category_id = ANY(v_category_ids)) THEN
      RAISE EXCEPTION 'Invalid category';
    END IF;

    -- Check no duplicate categories
    IF v_pick.category_id = ANY(v_seen_categories) THEN
      RAISE EXCEPTION 'Duplicate category in ballot';
    END IF;
    v_seen_categories := array_append(v_seen_categories, v_pick.category_id);

    -- Rule 1: Cannot vote for self
    IF v_pick.nominee_id = v_member_id THEN
      RAISE EXCEPTION 'You cannot vote for yourself';
    END IF;

    -- Check nominee is participant
    IF NOT EXISTS (
      SELECT 1 FROM public.poll_participants
      WHERE poll_id = p_poll_id AND member_id = v_pick.nominee_id AND locked = true
    ) THEN
      RAISE EXCEPTION 'Nominee is not in this poll';
    END IF;

    -- Rule 2: Track nominee counts for per-ballot limit
    v_nominee_counts := jsonb_set(
      v_nominee_counts,
      ARRAY[v_pick.nominee_id::text],
      to_jsonb(COALESCE((v_nominee_counts->>v_pick.nominee_id::text)::int, 0) + 1)
    );

    IF (v_nominee_counts->>v_pick.nominee_id::text)::int > v_limit THEN
      RAISE EXCEPTION 'Cannot pick the same person more than % times per ballot', v_limit;
    END IF;
  END LOOP;

  -- Delete old votes if editing
  IF p_previous_token IS NOT NULL THEN
    DELETE FROM public.votes WHERE ballot_token = p_previous_token AND poll_id = p_poll_id;
  END IF;

  -- Generate new token
  v_new_token := gen_random_uuid();

  -- Insert votes
  INSERT INTO public.votes (poll_id, category_id, ballot_token, nominee_id)
  SELECT p_poll_id, (x->>'category_id')::uuid, v_new_token, (x->>'nominee_id')::uuid
  FROM jsonb_array_elements(p_picks) x;

  -- Upsert ballots_cast
  INSERT INTO public.ballots_cast (poll_id, member_id, cast_at)
  VALUES (p_poll_id, v_member_id, now())
  ON CONFLICT (poll_id, member_id) DO UPDATE SET cast_at = now();

  RETURN v_new_token;
END;
$$;

-- Get tally (Admin only, aggregates only)
-- Gate 2: Only works when poll is closed or published
CREATE OR REPLACE FUNCTION public.get_poll_tally(p_poll_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_poll record;
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;

  -- Gate 2: No tally while voting
  IF v_poll.status NOT IN ('closed', 'published') THEN
    RAISE EXCEPTION 'Cannot view tally while voting is open';
  END IF;

  -- Return aggregates grouped by category and nominee
  SELECT jsonb_agg(cat_data ORDER BY cat_data->>'position') INTO v_result
  FROM (
    SELECT
      jsonb_build_object(
        'category_id', c.id,
        'title', c.title,
        'position', c.position,
        'nominees', COALESCE(
          (
            SELECT jsonb_agg(
              jsonb_build_object(
                'nominee_id', v.nominee_id,
                'display_name', COALESCE(p.display_name, p.handle),
                'handle', p.handle,
                'votes', v.vote_count
              ) ORDER BY v.vote_count DESC, p.handle
            )
            FROM (
              SELECT nominee_id, COUNT(*) as vote_count
              FROM public.votes
              WHERE poll_id = p_poll_id AND category_id = c.id
              GROUP BY nominee_id
            ) v
            JOIN public.profiles p ON p.id = v.nominee_id
          ),
          '[]'::jsonb
        )
      ) AS cat_data
    FROM public.categories c
    WHERE c.poll_id = p_poll_id
  ) sub;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- Get poll stats
CREATE OR REPLACE FUNCTION public.get_poll_stats(p_poll_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_poll record;
  v_participant_count int;
  v_ballots_cast int;
  v_idea_count int;
  v_category_count int;
BEGIN
  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  SELECT COUNT(*) INTO v_participant_count
  FROM public.poll_participants WHERE poll_id = p_poll_id;

  SELECT COUNT(*) INTO v_ballots_cast
  FROM public.ballots_cast WHERE poll_id = p_poll_id;

  SELECT COUNT(*) INTO v_idea_count
  FROM public.ideas WHERE poll_id = p_poll_id;

  SELECT COUNT(*) INTO v_category_count
  FROM public.categories WHERE poll_id = p_poll_id;

  RETURN jsonb_build_object(
    'participants', v_participant_count,
    'ballots_cast', v_ballots_cast,
    'turnout_pct', CASE WHEN v_participant_count > 0
      THEN ROUND((v_ballots_cast::numeric / v_participant_count) * 100, 1)
      ELSE 0
    END,
    'ideas', v_idea_count,
    'categories', v_category_count
  );
END;
$$;

-- Get participants list (with profiles)
CREATE OR REPLACE FUNCTION public.get_poll_participants(p_poll_id uuid)
RETURNS TABLE (
  member_id uuid,
  handle text,
  display_name text,
  avatar_type text,
  avatar_icon text,
  avatar_bg text,
  avatar_path text,
  joined_at timestamptz,
  locked boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT
    pp.member_id,
    p.handle,
    p.display_name,
    p.avatar_type,
    p.avatar_icon,
    p.avatar_bg,
    p.avatar_path,
    pp.joined_at,
    pp.locked
  FROM public.poll_participants pp
  JOIN public.profiles p ON p.id = pp.member_id
  WHERE pp.poll_id = p_poll_id AND p.is_active = true
  ORDER BY pp.joined_at;
END;
$$;

-- Check if current user has voted
CREATE OR REPLACE FUNCTION public.has_voted(p_poll_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.ballots_cast
    WHERE poll_id = p_poll_id AND member_id = auth.uid()
  );
$$;

-- Check if current user is participant
CREATE OR REPLACE FUNCTION public.is_participant(p_poll_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.poll_participants
    WHERE poll_id = p_poll_id AND member_id = auth.uid()
  );
$$;

-- Admin: Create a new poll
CREATE OR REPLACE FUNCTION public.create_poll(
  p_slug text,
  p_title text,
  p_topic text DEFAULT NULL,
  p_settings jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_new_id uuid;
  v_default_settings jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  -- Validate slug format
  IF p_slug !~ '^[a-z0-9-]+$' THEN
    RAISE EXCEPTION 'Slug must be lowercase letters, numbers, and hyphens only';
  END IF;

  v_default_settings := '{
    "votes_per_person_per_ballot": 3,
    "gold_cap": 3,
    "min_votes_for_award": 2,
    "max_categories": 20,
    "min_categories": 12,
    "min_participants": 10,
    "ideas_per_member": 3,
    "cap_fallback": "keep_winner",
    "tie_rule": "share_gold"
  }'::jsonb;

  INSERT INTO public.polls (slug, title, topic, settings)
  VALUES (
    p_slug,
    p_title,
    p_topic,
    COALESCE(p_settings, v_default_settings)
  )
  RETURNING id INTO v_new_id;

  -- Log action
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'create_poll', 'poll', v_new_id,
    jsonb_build_object('slug', p_slug, 'title', p_title));

  RETURN v_new_id;
END;
$$;

-- Admin: Update poll settings
CREATE OR REPLACE FUNCTION public.update_poll(
  p_poll_id uuid,
  p_title text DEFAULT NULL,
  p_topic text DEFAULT NULL,
  p_join_open_at timestamptz DEFAULT NULL,
  p_join_close_at timestamptz DEFAULT NULL,
  p_ideas_close_at timestamptz DEFAULT NULL,
  p_settings jsonb DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  -- Only allow updates before voting starts
  IF v_poll.status IN ('voting_open', 'closed', 'published') THEN
    RAISE EXCEPTION 'Cannot modify poll after voting has started';
  END IF;

  UPDATE public.polls
  SET
    title = COALESCE(p_title, title),
    topic = COALESCE(p_topic, topic),
    join_open_at = COALESCE(p_join_open_at, join_open_at),
    join_close_at = COALESCE(p_join_close_at, join_close_at),
    ideas_close_at = COALESCE(p_ideas_close_at, ideas_close_at),
    settings = COALESCE(p_settings, settings),
    updated_at = now()
  WHERE id = p_poll_id;

  RETURN true;
END;
$$;

-- Admin: Save results
CREATE OR REPLACE FUNCTION public.save_results(
  p_poll_id uuid,
  p_results jsonb
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_result record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
  IF v_poll.status NOT IN ('closed', 'published') THEN
    RAISE EXCEPTION 'Poll must be closed to save results';
  END IF;

  -- Upsert results
  FOR v_result IN
    SELECT * FROM jsonb_to_recordset(p_results)
      AS x(category_id uuid, raw jsonb, final jsonb, reason text)
  LOOP
    INSERT INTO public.results (poll_id, category_id, raw, final, reason)
    VALUES (p_poll_id, v_result.category_id, v_result.raw, v_result.final, v_result.reason)
    ON CONFLICT (poll_id, category_id) DO UPDATE
    SET raw = v_result.raw, final = v_result.final, reason = v_result.reason;
  END LOOP;

  RETURN true;
END;
$$;

-- ============================================================================
-- UPDATE EXISTING FUNCTIONS FOR POLL DATA EXPORT/DELETE
-- ============================================================================

-- Extend export_my_data to include poll data
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
  poll_participation jsonb;
  ideas_data jsonb;
  upvotes_data jsonb;
  ballots_data jsonb;
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
  FROM public.invite_redemptions ir
  WHERE ir.user_id = user_id
  LIMIT 1;

  -- Get poll participation
  SELECT jsonb_agg(jsonb_build_object(
    'poll_slug', p.slug,
    'joined_at', pp.joined_at,
    'locked', pp.locked
  )) INTO poll_participation
  FROM public.poll_participants pp
  JOIN public.polls p ON p.id = pp.poll_id
  WHERE pp.member_id = user_id;

  -- Get ideas submitted
  SELECT jsonb_agg(jsonb_build_object(
    'poll_slug', p.slug,
    'text', i.text,
    'status', i.status,
    'created_at', i.created_at
  )) INTO ideas_data
  FROM public.ideas i
  JOIN public.polls p ON p.id = i.poll_id
  WHERE i.author_id = user_id;

  -- Get upvotes given
  SELECT jsonb_agg(jsonb_build_object(
    'idea_text', i.text,
    'poll_slug', p.slug,
    'created_at', iu.created_at
  )) INTO upvotes_data
  FROM public.idea_upvotes iu
  JOIN public.ideas i ON i.id = iu.idea_id
  JOIN public.polls p ON p.id = i.poll_id
  WHERE iu.member_id = user_id;

  -- Get ballots cast dates (not content - that's anonymous)
  SELECT jsonb_agg(jsonb_build_object(
    'poll_slug', p.slug,
    'cast_at', bc.cast_at
  )) INTO ballots_data
  FROM public.ballots_cast bc
  JOIN public.polls p ON p.id = bc.poll_id
  WHERE bc.member_id = user_id;

  result := jsonb_build_object(
    'exported_at', now(),
    'email', user_email,
    'profile', profile_data,
    'invite_code_used', invite_used,
    'poll_participation', poll_participation,
    'ideas_submitted', ideas_data,
    'idea_upvotes', upvotes_data,
    'ballots_cast', ballots_data
  );

  RETURN result;
END;
$$;

-- Extend delete_my_account to handle poll data
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

  -- Delete poll-related data
  DELETE FROM public.ideas WHERE author_id = user_id;
  DELETE FROM public.idea_upvotes WHERE member_id = user_id;
  DELETE FROM public.poll_participants WHERE member_id = user_id;
  DELETE FROM public.ballots_cast WHERE member_id = user_id;
  DELETE FROM public.share_opt_outs WHERE member_id = user_id;
  -- Note: votes table has no member_id (anonymous)
  -- Published results: nominee_id ON DELETE SET NULL - display becomes "a former member"

  -- Delete from auth.users (profiles will cascade)
  DELETE FROM auth.users WHERE id = user_id;

  RETURN true;
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.get_current_poll() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_by_slug(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_poll(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_poll(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_idea(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_idea_upvote(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_ideas(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_ideas_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_idea_status(uuid, text, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_category(uuid, uuid, text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transition_poll_status(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_ballot(uuid, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_tally(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_participants(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_voted(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_participant(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_poll(text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_poll(uuid, text, text, timestamptz, timestamptz, timestamptz, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_results(uuid, jsonb) TO authenticated;
