-- Admin Poll Management Extensions
-- This migration adds features needed for the admin poll management screens
-- Run after 20261030000000_polls.sql

-- ============================================================================
-- ADD CAPTIONS COLUMN TO POLLS
-- ============================================================================

-- Add captions column to store per-poll captions (same shape as captions.json)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'polls' AND column_name = 'captions'
  ) THEN
    ALTER TABLE public.polls ADD COLUMN captions jsonb DEFAULT '{
      "defaults": {"winner": "The people have spoken.", "personal": "In the movie, I am...", "highlight": ""},
      "highlights": {},
      "categories": {}
    }'::jsonb;
  END IF;
END $$;

-- ============================================================================
-- ADMIN RPC FUNCTIONS
-- ============================================================================

-- Close joining early (admin only)
-- Locks all participants and allows voting to start
CREATE OR REPLACE FUNCTION public.close_joining_early(p_poll_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_count int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  -- Can only close joining during ideas_open or curating
  IF v_poll.status NOT IN ('ideas_open', 'curating') THEN
    RAISE EXCEPTION 'Joining can only be closed during ideas_open or curating phases';
  END IF;

  -- Lock all participants
  UPDATE public.poll_participants
  SET locked = true
  WHERE poll_id = p_poll_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- Update join_close_at to now
  UPDATE public.polls
  SET
    join_close_at = now(),
    updated_at = now()
  WHERE id = p_poll_id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'close_joining_early', 'poll', p_poll_id,
    jsonb_build_object('participants_locked', v_count));

  RETURN true;
END;
$$;

-- Admin: Remove participant (before lock only)
CREATE OR REPLACE FUNCTION public.admin_remove_participant(p_poll_id uuid, p_member_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_participant record;
  v_handle text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_participant
  FROM public.poll_participants
  WHERE poll_id = p_poll_id AND member_id = p_member_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Participant not found';
  END IF;

  IF v_participant.locked THEN
    RAISE EXCEPTION 'Cannot remove participant after the list is locked';
  END IF;

  -- Get handle for logging
  SELECT handle INTO v_handle FROM public.profiles WHERE id = p_member_id;

  -- Delete their upvotes on ideas in this poll
  DELETE FROM public.idea_upvotes
  WHERE member_id = p_member_id
    AND idea_id IN (SELECT id FROM public.ideas WHERE poll_id = p_poll_id);

  -- Delete their ideas in this poll
  DELETE FROM public.ideas
  WHERE poll_id = p_poll_id AND author_id = p_member_id;

  -- Delete participation
  DELETE FROM public.poll_participants
  WHERE poll_id = p_poll_id AND member_id = p_member_id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'remove_participant', 'poll', p_poll_id,
    jsonb_build_object('member_id', p_member_id, 'handle', v_handle));

  RETURN true;
END;
$$;

-- Admin: Update idea text
CREATE OR REPLACE FUNCTION public.update_idea_text(p_idea_id uuid, p_new_text text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_idea record;
  v_poll record;
  v_old_text text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_idea FROM public.ideas WHERE id = p_idea_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Idea not found';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = v_idea.poll_id;

  -- Cannot edit once voting is open
  IF v_poll.status IN ('voting_open', 'closed', 'published') THEN
    RAISE EXCEPTION 'Cannot edit ideas after voting has started';
  END IF;

  v_old_text := v_idea.text;

  -- Validate text length
  IF char_length(TRIM(p_new_text)) < 10 THEN
    RAISE EXCEPTION 'Idea must be at least 10 characters';
  END IF;
  IF char_length(p_new_text) > 90 THEN
    RAISE EXCEPTION 'Idea must be 90 characters or less';
  END IF;

  UPDATE public.ideas
  SET text = TRIM(p_new_text)
  WHERE id = p_idea_id;

  -- Also update category title if this idea is the source
  UPDATE public.categories
  SET title = TRIM(p_new_text)
  WHERE idea_id = p_idea_id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'edit_idea_text', 'idea', p_idea_id,
    jsonb_build_object('old_text', v_old_text, 'new_text', p_new_text));

  RETURN true;
END;
$$;

-- Admin: Merge ideas (upvotes add)
CREATE OR REPLACE FUNCTION public.merge_ideas(p_source_id uuid, p_target_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_source record;
  v_target record;
  v_poll record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_source FROM public.ideas WHERE id = p_source_id;
  SELECT * INTO v_target FROM public.ideas WHERE id = p_target_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ideas not found';
  END IF;

  IF v_source.poll_id != v_target.poll_id THEN
    RAISE EXCEPTION 'Ideas must be from the same poll';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = v_source.poll_id;
  IF v_poll.status IN ('voting_open', 'closed', 'published') THEN
    RAISE EXCEPTION 'Cannot merge ideas after voting has started';
  END IF;

  -- Move upvotes from source to target (ignore duplicates)
  INSERT INTO public.idea_upvotes (idea_id, member_id, created_at)
  SELECT p_target_id, member_id, created_at
  FROM public.idea_upvotes
  WHERE idea_id = p_source_id
  ON CONFLICT DO NOTHING;

  -- Delete source upvotes
  DELETE FROM public.idea_upvotes WHERE idea_id = p_source_id;

  -- Mark source as merged
  UPDATE public.ideas
  SET status = 'merged', merged_into = p_target_id
  WHERE id = p_source_id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'merge_ideas', 'idea', p_target_id,
    jsonb_build_object('source_id', p_source_id, 'source_text', v_source.text, 'target_text', v_target.text));

  RETURN true;
END;
$$;

-- Admin: Update category title
CREATE OR REPLACE FUNCTION public.update_category_title(p_category_id uuid, p_new_title text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_category record;
  v_poll record;
  v_old_title text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_category FROM public.categories WHERE id = p_category_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Category not found';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = v_category.poll_id;
  IF v_poll.status IN ('voting_open', 'closed', 'published') THEN
    RAISE EXCEPTION 'Cannot edit ballot after voting has started';
  END IF;

  v_old_title := v_category.title;

  UPDATE public.categories
  SET title = TRIM(p_new_title)
  WHERE id = p_category_id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'edit_category', 'category', p_category_id,
    jsonb_build_object('old_title', v_old_title, 'new_title', p_new_title));

  RETURN true;
END;
$$;

-- Admin: Delete category
CREATE OR REPLACE FUNCTION public.delete_category(p_category_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_category record;
  v_poll record;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_category FROM public.categories WHERE id = p_category_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Category not found';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = v_category.poll_id;
  IF v_poll.status IN ('voting_open', 'closed', 'published') THEN
    RAISE EXCEPTION 'Cannot modify ballot after voting has started';
  END IF;

  -- Mark linked idea as declined if any
  IF v_category.idea_id IS NOT NULL THEN
    UPDATE public.ideas
    SET status = 'declined', decline_reason = 'Removed from ballot'
    WHERE id = v_category.idea_id;
  END IF;

  DELETE FROM public.categories WHERE id = p_category_id;

  -- Reorder remaining categories
  WITH numbered AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY position) as new_pos
    FROM public.categories
    WHERE poll_id = v_category.poll_id
  )
  UPDATE public.categories c
  SET position = n.new_pos
  FROM numbered n
  WHERE c.id = n.id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'delete_category', 'category', p_category_id,
    jsonb_build_object('title', v_category.title));

  RETURN true;
END;
$$;

-- Admin: Reorder categories
CREATE OR REPLACE FUNCTION public.reorder_categories(p_poll_id uuid, p_category_ids uuid[])
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_pos int := 1;
  v_cat_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  IF v_poll.status IN ('voting_open', 'closed', 'published') THEN
    RAISE EXCEPTION 'Cannot reorder ballot after voting has started';
  END IF;

  -- Update positions based on array order
  FOREACH v_cat_id IN ARRAY p_category_ids
  LOOP
    UPDATE public.categories
    SET position = v_pos
    WHERE id = v_cat_id AND poll_id = p_poll_id;
    v_pos := v_pos + 1;
  END LOOP;

  RETURN true;
END;
$$;

-- Admin: Get turnout stats (for voting tab)
CREATE OR REPLACE FUNCTION public.get_turnout_stats(p_poll_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
DECLARE
  v_poll record;
  v_joined int;
  v_voted int;
  v_daily jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  -- Count joined and voted
  SELECT COUNT(*) INTO v_joined
  FROM public.poll_participants WHERE poll_id = p_poll_id;

  SELECT COUNT(*) INTO v_voted
  FROM public.ballots_cast WHERE poll_id = p_poll_id;

  -- Get daily breakdown (if voting has started)
  IF v_poll.status IN ('voting_open', 'closed', 'published') THEN
    SELECT jsonb_agg(jsonb_build_object(
      'date', d,
      'count', c
    ) ORDER BY d) INTO v_daily
    FROM (
      SELECT DATE(cast_at) as d, COUNT(*) as c
      FROM public.ballots_cast
      WHERE poll_id = p_poll_id
      GROUP BY DATE(cast_at)
    ) sub;
  END IF;

  RETURN jsonb_build_object(
    'joined', v_joined,
    'voted', v_voted,
    'not_voted', v_joined - v_voted,
    'daily', COALESCE(v_daily, '[]'::jsonb)
  );
END;
$$;

-- Admin: Get audit log for a poll
CREATE OR REPLACE FUNCTION public.get_poll_audit_log(p_poll_id uuid)
RETURNS TABLE (
  id uuid,
  actor_id uuid,
  actor_handle text,
  action text,
  target_type text,
  target_id uuid,
  details jsonb,
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
    a.id,
    a.actor_id,
    COALESCE(p.handle, 'system') as actor_handle,
    a.action,
    a.target_type,
    a.target_id,
    a.details,
    a.created_at
  FROM public.audit_log a
  LEFT JOIN public.profiles p ON p.id = a.actor_id
  WHERE a.target_id = p_poll_id
     OR a.details->>'poll_id' = p_poll_id::text
     OR (a.target_type = 'poll' AND a.target_id = p_poll_id)
     OR (a.target_type = 'idea' AND EXISTS (
       SELECT 1 FROM public.ideas i WHERE i.id = a.target_id AND i.poll_id = p_poll_id
     ))
     OR (a.target_type = 'category' AND EXISTS (
       SELECT 1 FROM public.categories c WHERE c.id = a.target_id AND c.poll_id = p_poll_id
     ))
  ORDER BY a.created_at DESC;
END;
$$;

-- Admin: Publish poll (with checkbox validation)
CREATE OR REPLACE FUNCTION public.publish_poll(
  p_poll_id uuid,
  p_checked_results boolean,
  p_checked_captions boolean,
  p_checked_privacy boolean
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

  -- All three checkboxes must be true
  IF NOT (p_checked_results AND p_checked_captions AND p_checked_privacy) THEN
    RAISE EXCEPTION 'All three checkboxes must be checked to publish';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  IF v_poll.status != 'closed' THEN
    RAISE EXCEPTION 'Poll must be closed before publishing';
  END IF;

  -- Transition to published
  UPDATE public.polls
  SET
    status = 'published',
    published_at = now(),
    updated_at = now()
  WHERE id = p_poll_id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'publish_poll', 'poll', p_poll_id,
    jsonb_build_object(
      'checked_results', p_checked_results,
      'checked_captions', p_checked_captions,
      'checked_privacy', p_checked_privacy
    ));

  RETURN true;
END;
$$;

-- Admin: Update poll captions
CREATE OR REPLACE FUNCTION public.update_poll_captions(p_poll_id uuid, p_captions jsonb)
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

  -- Can only update captions before or when closed (not after published)
  IF v_poll.status = 'published' THEN
    RAISE EXCEPTION 'Cannot update captions after publishing';
  END IF;

  UPDATE public.polls
  SET captions = p_captions, updated_at = now()
  WHERE id = p_poll_id;

  RETURN true;
END;
$$;

-- Admin: Update poll dates with validation
CREATE OR REPLACE FUNCTION public.update_poll_dates(
  p_poll_id uuid,
  p_join_open_at timestamptz DEFAULT NULL,
  p_join_close_at timestamptz DEFAULT NULL,
  p_ideas_close_at timestamptz DEFAULT NULL,
  p_voting_open_at timestamptz DEFAULT NULL,
  p_voting_close_at timestamptz DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_poll record;
  v_new_join_close timestamptz;
  v_new_voting_open timestamptz;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  -- Cannot modify dates after voting starts
  IF v_poll.status IN ('voting_open', 'closed', 'published') THEN
    RAISE EXCEPTION 'Cannot modify dates after voting has started';
  END IF;

  -- Calculate the new values
  v_new_join_close := COALESCE(p_join_close_at, v_poll.join_close_at);
  v_new_voting_open := COALESCE(p_voting_open_at, v_poll.voting_open_at);

  -- Gate 1: voting_open_at must be >= join_close_at
  IF v_new_voting_open IS NOT NULL AND v_new_join_close IS NOT NULL THEN
    IF v_new_voting_open < v_new_join_close THEN
      RAISE EXCEPTION 'Voting can''t open before joining closes. Move voting later or joining earlier.';
    END IF;
  END IF;

  -- Cannot set dates in the past (except for dates that have already passed)
  IF p_join_open_at IS NOT NULL AND p_join_open_at < now() AND (v_poll.join_open_at IS NULL OR v_poll.join_open_at > now()) THEN
    RAISE EXCEPTION 'Cannot set join open date in the past';
  END IF;

  UPDATE public.polls
  SET
    join_open_at = COALESCE(p_join_open_at, join_open_at),
    join_close_at = COALESCE(p_join_close_at, join_close_at),
    ideas_close_at = COALESCE(p_ideas_close_at, ideas_close_at),
    voting_open_at = COALESCE(p_voting_open_at, voting_open_at),
    voting_close_at = COALESCE(p_voting_close_at, voting_close_at),
    updated_at = now()
  WHERE id = p_poll_id;

  RETURN true;
END;
$$;

-- Admin: Reopen voting (from closed, before publish)
CREATE OR REPLACE FUNCTION public.reopen_voting(p_poll_id uuid)
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

  SELECT * INTO v_poll FROM public.polls WHERE id = p_poll_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Poll not found';
  END IF;

  IF v_poll.status != 'closed' THEN
    RAISE EXCEPTION 'Can only reopen voting from closed state';
  END IF;

  UPDATE public.polls
  SET
    status = 'voting_open',
    voting_close_at = NULL,
    updated_at = now()
  WHERE id = p_poll_id;

  -- Audit log
  INSERT INTO public.audit_log (actor_id, action, target_type, target_id, details)
  VALUES (auth.uid(), 'reopen_voting', 'poll', p_poll_id,
    jsonb_build_object('reopened_at', now()));

  RETURN true;
END;
$$;

-- Admin: Get all polls (for list view)
CREATE OR REPLACE FUNCTION public.get_all_polls_admin()
RETURNS TABLE (
  id uuid,
  slug text,
  title text,
  topic text,
  status text,
  join_open_at timestamptz,
  join_close_at timestamptz,
  ideas_close_at timestamptz,
  voting_open_at timestamptz,
  voting_close_at timestamptz,
  published_at timestamptz,
  settings jsonb,
  captions jsonb,
  created_at timestamptz,
  participant_count bigint,
  category_count bigint,
  ballot_count bigint
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
    p.id,
    p.slug,
    p.title,
    p.topic,
    p.status,
    p.join_open_at,
    p.join_close_at,
    p.ideas_close_at,
    p.voting_open_at,
    p.voting_close_at,
    p.published_at,
    p.settings,
    p.captions,
    p.created_at,
    (SELECT COUNT(*) FROM public.poll_participants pp WHERE pp.poll_id = p.id) as participant_count,
    (SELECT COUNT(*) FROM public.categories c WHERE c.poll_id = p.id) as category_count,
    (SELECT COUNT(*) FROM public.ballots_cast bc WHERE bc.poll_id = p.id) as ballot_count
  FROM public.polls p
  ORDER BY p.created_at DESC;
END;
$$;

-- Admin: Get categories for ballot view
CREATE OR REPLACE FUNCTION public.get_poll_categories_admin(p_poll_id uuid)
RETURNS TABLE (
  id uuid,
  title text,
  pos int,
  idea_id uuid,
  idea_text text
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
    c.id,
    c.title,
    c.position as pos,
    c.idea_id,
    i.text as idea_text
  FROM public.categories c
  LEFT JOIN public.ideas i ON i.id = c.idea_id
  WHERE c.poll_id = p_poll_id
  ORDER BY c.position;
END;
$$;

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.close_joining_early(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_remove_participant(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_idea_text(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.merge_ideas(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_category_title(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_category(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reorder_categories(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_turnout_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_audit_log(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_poll(uuid, boolean, boolean, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_poll_captions(uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_poll_dates(uuid, timestamptz, timestamptz, timestamptz, timestamptz, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reopen_voting(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_all_polls_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_poll_categories_admin(uuid) TO authenticated;
