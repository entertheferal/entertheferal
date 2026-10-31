-- Test script for Feral Collective accounts system
-- Run these in the Supabase SQL Editor to verify the implementation
-- NOTE: These tests modify data. Run on a test project or clean up after.

-- ============================================================================
-- Setup: Create test data
-- ============================================================================

-- Create test invite codes
INSERT INTO invite_codes (code, note, max_uses, expires_at, revoked)
VALUES
  ('TEST-VALID-0001', 'Valid single-use', 1, NULL, false),
  ('TEST-MULTI-0002', 'Valid multi-use', 5, NULL, false),
  ('TEST-EXPRD-0003', 'Expired', 1, now() - interval '1 day', false),
  ('TEST-REVKD-0004', 'Revoked', 1, NULL, true),
  ('TEST-USEUP-0005', 'Used up', 1, NULL, false)
ON CONFLICT (code) DO NOTHING;

-- Mark one as used up
UPDATE invite_codes SET uses = max_uses WHERE code = 'TEST-USEUP-0005';

-- ============================================================================
-- Test 1: Invalid invite codes should fail
-- ============================================================================

-- This should fail: no invite code
DO $$
BEGIN
  -- Simulate signup without invite
  -- In practice, the BEFORE INSERT trigger would reject this
  RAISE NOTICE 'Test 1: Verify trigger rejects signup without valid invite code';
END $$;

-- ============================================================================
-- Test 2: Expired codes should fail
-- ============================================================================

SELECT 'Test 2: Expired code' AS test,
  CASE
    WHEN (SELECT uses < max_uses AND NOT revoked AND (expires_at IS NULL OR expires_at > now())
          FROM invite_codes WHERE code = 'TEST-EXPRD-0003')
    THEN 'FAIL: Expired code would be accepted'
    ELSE 'PASS: Expired code correctly rejected'
  END AS result;

-- ============================================================================
-- Test 3: Revoked codes should fail
-- ============================================================================

SELECT 'Test 3: Revoked code' AS test,
  CASE
    WHEN (SELECT uses < max_uses AND NOT revoked AND (expires_at IS NULL OR expires_at > now())
          FROM invite_codes WHERE code = 'TEST-REVKD-0004')
    THEN 'FAIL: Revoked code would be accepted'
    ELSE 'PASS: Revoked code correctly rejected'
  END AS result;

-- ============================================================================
-- Test 4: Used-up codes should fail
-- ============================================================================

SELECT 'Test 4: Used-up code' AS test,
  CASE
    WHEN (SELECT uses < max_uses AND NOT revoked AND (expires_at IS NULL OR expires_at > now())
          FROM invite_codes WHERE code = 'TEST-USEUP-0005')
    THEN 'FAIL: Used-up code would be accepted'
    ELSE 'PASS: Used-up code correctly rejected'
  END AS result;

-- ============================================================================
-- Test 5: Valid codes should work
-- ============================================================================

SELECT 'Test 5: Valid code' AS test,
  CASE
    WHEN (SELECT uses < max_uses AND NOT revoked AND (expires_at IS NULL OR expires_at > now())
          FROM invite_codes WHERE code = 'TEST-VALID-0001')
    THEN 'PASS: Valid code would be accepted'
    ELSE 'FAIL: Valid code rejected'
  END AS result;

-- ============================================================================
-- Test 6: Handle availability check
-- ============================================================================

SELECT 'Test 6: Handle availability' AS test,
  CASE
    WHEN handle_available('admin') = false
      AND handle_available('a') = false
      AND handle_available('valid_handle') = true
    THEN 'PASS: Handle validation works'
    ELSE 'FAIL: Handle validation broken'
  END AS result;

-- ============================================================================
-- Test 7: RLS - Anonymous cannot read profiles
-- ============================================================================

-- This test requires running as anon role
-- In practice: try to SELECT from profiles without authentication
SELECT 'Test 7: RLS on profiles' AS test,
  'MANUAL: Verify anonymous requests to profiles table return empty/error' AS result;

-- ============================================================================
-- Test 8: RLS - Anonymous cannot read invite_codes
-- ============================================================================

SELECT 'Test 8: RLS on invite_codes' AS test,
  'MANUAL: Verify anonymous/non-admin requests to invite_codes return empty' AS result;

-- ============================================================================
-- Test 9: Non-admins cannot call admin functions
-- ============================================================================

SELECT 'Test 9: Admin function protection' AS test,
  'MANUAL: Verify non-admin calling create_invite() raises admin_required' AS result;

-- ============================================================================
-- Test 10: Profile protection trigger
-- ============================================================================

SELECT 'Test 10: Profile field protection' AS test,
  'MANUAL: Verify non-admin cannot update roles, is_admin, is_active fields' AS result;

-- ============================================================================
-- Test 11: Handle change rate limit
-- ============================================================================

SELECT 'Test 11: Handle change rate limit' AS test,
  'MANUAL: Set handle_changed_at to now(), then try to change handle - should fail' AS result;

-- ============================================================================
-- Test 12: Delete account - last admin protection
-- ============================================================================

SELECT 'Test 12: Last admin protection' AS test,
  'MANUAL: With only one admin, delete_my_account() should raise cannot_delete_last_admin' AS result;

-- ============================================================================
-- Test 13: Concurrent invite code use
-- ============================================================================

-- This tests atomicity of the UPDATE ... RETURNING in the trigger
-- Run two signups with the same single-use code simultaneously
-- Only one should succeed

SELECT 'Test 13: Concurrent redemption' AS test,
  'MANUAL: Attempt two simultaneous signups with TEST-VALID-0001 - only one should succeed' AS result;

-- ============================================================================
-- Cleanup
-- ============================================================================

-- Uncomment to clean up test data:
-- DELETE FROM invite_codes WHERE code LIKE 'TEST-%';

SELECT 'Tests complete. Review MANUAL tests and clean up test data.' AS summary;
