// Feral Collective Poll Utilities
// Requires: supabase-config.js, auth.js to be loaded first

(function() {
  'use strict';

  // Constants for ballot token storage
  const BALLOT_TOKEN_PREFIX = 'feral_ballot_';

  // Get Supabase client from auth
  function getSupabase() {
    return window.FeralAuth?.getSupabase();
  }

  // ============================================================================
  // POLL QUERIES
  // ============================================================================

  // Get the current active poll
  async function getCurrentPoll() {
    const sb = getSupabase();
    if (!sb) return null;

    const { data, error } = await sb.rpc('get_current_poll');
    if (error) {
      console.error('Error fetching current poll:', error);
      return null;
    }
    return data;
  }

  // Get poll by slug
  async function getPollBySlug(slug) {
    const sb = getSupabase();
    if (!sb) return null;

    const { data, error } = await sb.rpc('get_poll_by_slug', { p_slug: slug });
    if (error) {
      console.error('Error fetching poll:', error);
      return null;
    }
    return data;
  }

  // Get poll stats
  async function getPollStats(pollId) {
    const sb = getSupabase();
    if (!sb) return null;

    const { data, error } = await sb.rpc('get_poll_stats', { p_poll_id: pollId });
    if (error) {
      console.error('Error fetching poll stats:', error);
      return null;
    }
    return data;
  }

  // Get poll participants
  async function getParticipants(pollId) {
    const sb = getSupabase();
    if (!sb) return [];

    const { data, error } = await sb.rpc('get_poll_participants', { p_poll_id: pollId });
    if (error) {
      console.error('Error fetching participants:', error);
      return [];
    }
    return data || [];
  }

  // Check if current user is participant
  async function isParticipant(pollId) {
    const sb = getSupabase();
    if (!sb) return false;

    const { data, error } = await sb.rpc('is_participant', { p_poll_id: pollId });
    if (error) return false;
    return data === true;
  }

  // Check if current user has voted
  async function hasVoted(pollId) {
    const sb = getSupabase();
    if (!sb) return false;

    const { data, error } = await sb.rpc('has_voted', { p_poll_id: pollId });
    if (error) return false;
    return data === true;
  }

  // ============================================================================
  // JOINING
  // ============================================================================

  // Join a poll
  async function joinPoll(pollId) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('join_poll', { p_poll_id: pollId });
    return { data, error };
  }

  // Leave a poll
  async function leavePoll(pollId) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('leave_poll', { p_poll_id: pollId });
    return { data, error };
  }

  // ============================================================================
  // IDEAS
  // ============================================================================

  // Get ideas for a poll
  async function getIdeas(pollId) {
    const sb = getSupabase();
    if (!sb) return [];

    const { data, error } = await sb.rpc('get_poll_ideas', { p_poll_id: pollId });
    if (error) {
      console.error('Error fetching ideas:', error);
      return [];
    }
    return data || [];
  }

  // Submit an idea
  async function submitIdea(pollId, text) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('submit_idea', {
      p_poll_id: pollId,
      p_text: text.trim()
    });
    return { data, error };
  }

  // Toggle upvote on an idea
  async function toggleUpvote(ideaId) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('toggle_idea_upvote', { p_idea_id: ideaId });
    return { data, error };
  }

  // Check if idea text looks like it names someone
  function looksLikeItNamesSomeone(text) {
    // Simple heuristic: check for common name patterns
    // This is advisory only - actual validation is server-side
    const patterns = [
      /\b(he|she|they)\s+(is|are|would|will|should)\b/i,
      /\bmost likely to\s+[A-Z][a-z]+\b/,
      /\b[A-Z][a-z]+\s+(is|would|will|should)\b/,
      /\bwho\s+(is|would|will|can)\b/i
    ];
    return patterns.some(p => p.test(text));
  }

  // ============================================================================
  // VOTING
  // ============================================================================

  // Get categories for voting
  async function getCategories(pollId) {
    const sb = getSupabase();
    if (!sb) return [];

    const { data, error } = await sb
      .from('categories')
      .select('id, title, position')
      .eq('poll_id', pollId)
      .order('position');

    if (error) {
      console.error('Error fetching categories:', error);
      return [];
    }
    return data || [];
  }

  // Submit a ballot
  async function submitBallot(pollId, picks, previousToken = null) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('submit_ballot', {
      p_poll_id: pollId,
      p_picks: picks,
      p_previous_token: previousToken
    });

    if (!error && data) {
      // Store the new token
      saveBallotToken(pollId, data);
    }

    return { data, error };
  }

  // Save ballot token to localStorage
  function saveBallotToken(pollId, token) {
    try {
      localStorage.setItem(BALLOT_TOKEN_PREFIX + pollId, token);
    } catch (e) {
      console.warn('Could not save ballot token:', e);
    }
  }

  // Get ballot token from localStorage
  function getBallotToken(pollId) {
    try {
      return localStorage.getItem(BALLOT_TOKEN_PREFIX + pollId);
    } catch (e) {
      return null;
    }
  }

  // Clear ballot token
  function clearBallotToken(pollId) {
    try {
      localStorage.removeItem(BALLOT_TOKEN_PREFIX + pollId);
    } catch (e) {
      // ignore
    }
  }

  // Download ballot key as a text file
  function downloadBallotKey(pollId, token) {
    const text = `Feral Collective Ballot Key\n\nPoll: ${pollId}\nToken: ${token}\n\nKeep this safe! You'll need it to edit your vote.`;
    const blob = new Blob([text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `ballot-key-${pollId.slice(0, 8)}.txt`;
    a.click();
    URL.revokeObjectURL(url);
  }

  // Shuffle array (Fisher-Yates) with optional seed
  function shuffleArray(array, seed = null) {
    const result = [...array];
    let random;

    if (seed !== null) {
      // Seeded random for consistent shuffling
      let s = seed;
      random = () => {
        s = (s * 1103515245 + 12345) & 0x7fffffff;
        return s / 0x7fffffff;
      };
    } else {
      random = Math.random;
    }

    for (let i = result.length - 1; i > 0; i--) {
      const j = Math.floor(random() * (i + 1));
      [result[i], result[j]] = [result[j], result[i]];
    }

    return result;
  }

  // Generate a shuffle seed from user ID and category ID
  function getShuffleSeed(userId, categoryId) {
    const str = userId + categoryId;
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i);
      hash = hash & hash;
    }
    return Math.abs(hash);
  }

  // ============================================================================
  // ADMIN FUNCTIONS
  // ============================================================================

  // Get ideas with admin details
  async function getIdeasAdmin(pollId) {
    const sb = getSupabase();
    if (!sb) return [];

    const { data, error } = await sb.rpc('get_poll_ideas_admin', { p_poll_id: pollId });
    if (error) {
      console.error('Error fetching ideas:', error);
      return [];
    }
    return data || [];
  }

  // Update idea status
  async function updateIdeaStatus(ideaId, status, reason = null, mergedInto = null) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('update_idea_status', {
      p_idea_id: ideaId,
      p_status: status,
      p_reason: reason,
      p_merged_into: mergedInto
    });
    return { data, error };
  }

  // Create category from idea
  async function createCategory(pollId, ideaId, title, position) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('create_category', {
      p_poll_id: pollId,
      p_idea_id: ideaId,
      p_title: title,
      p_position: position
    });
    return { data, error };
  }

  // Transition poll status
  async function transitionPollStatus(pollId, newStatus) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('transition_poll_status', {
      p_poll_id: pollId,
      p_new_status: newStatus
    });
    return { data, error };
  }

  // Get poll tally (admin only, after voting closes)
  async function getPollTally(pollId) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('get_poll_tally', { p_poll_id: pollId });
    return { data, error };
  }

  // Save results
  async function saveResults(pollId, results) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('save_results', {
      p_poll_id: pollId,
      p_results: results
    });
    return { data, error };
  }

  // Create new poll
  async function createPoll(slug, title, topic = null, settings = null) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('create_poll', {
      p_slug: slug,
      p_title: title,
      p_topic: topic,
      p_settings: settings
    });
    return { data, error };
  }

  // Update poll settings
  async function updatePoll(pollId, updates) {
    const sb = getSupabase();
    if (!sb) return { error: { message: 'Not connected' } };

    const { data, error } = await sb.rpc('update_poll', {
      p_poll_id: pollId,
      p_title: updates.title || null,
      p_topic: updates.topic || null,
      p_join_open_at: updates.join_open_at || null,
      p_join_close_at: updates.join_close_at || null,
      p_ideas_close_at: updates.ideas_close_at || null,
      p_settings: updates.settings || null
    });
    return { data, error };
  }

  // ============================================================================
  // HELPERS
  // ============================================================================

  // Format date for display
  function formatDate(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    return d.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit'
    });
  }

  // Format relative time
  function formatRelativeTime(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    const now = new Date();
    const diffMs = d - now;
    const diffDays = Math.ceil(diffMs / (1000 * 60 * 60 * 24));
    const diffHours = Math.ceil(diffMs / (1000 * 60 * 60));

    if (diffMs < 0) {
      return 'closed';
    } else if (diffDays > 1) {
      return `${diffDays} days left`;
    } else if (diffHours > 1) {
      return `${diffHours} hours left`;
    } else {
      return 'closing soon';
    }
  }

  // Get poll phase label
  function getPollPhaseLabel(poll) {
    if (!poll) return '';
    switch (poll.status) {
      case 'draft': return 'Coming soon';
      case 'ideas_open': return 'Suggesting ideas';
      case 'curating': return 'Ideas being reviewed';
      case 'voting_open': return 'Voting open';
      case 'closed': return 'Voting closed';
      case 'published': return 'Results published';
      default: return poll.status;
    }
  }

  // Map error codes to friendly messages
  function friendlyError(error) {
    if (!error) return null;
    const msg = error.message || error.hint || String(error);

    // Poll-specific errors
    if (msg.includes('not accepting new participants')) {
      return 'This poll is no longer accepting new members.';
    }
    if (msg.includes('Joining has not opened')) {
      return 'Joining has not opened yet.';
    }
    if (msg.includes('Joining has closed')) {
      return 'Joining has closed.';
    }
    if (msg.includes('already joined')) {
      return "You're already in this poll.";
    }
    if (msg.includes('Voting has started')) {
      return 'Voting has started - you cannot leave now.';
    }
    if (msg.includes('not in this poll')) {
      return "You're not in this poll.";
    }
    if (msg.includes('Ideas are not being accepted')) {
      return 'Idea submission is closed.';
    }
    if (msg.includes('Idea submission has closed')) {
      return 'Idea submission has closed.';
    }
    if (msg.includes('must join the poll')) {
      return 'You must join the poll first.';
    }
    if (msg.includes('maximum number of ideas')) {
      return "You've submitted the maximum number of ideas.";
    }
    if (msg.includes('at least 10 characters')) {
      return 'Idea must be at least 10 characters.';
    }
    if (msg.includes('90 characters or less')) {
      return 'Idea must be 90 characters or less.';
    }
    if (msg.includes('Voting is not open')) {
      return 'Voting is not open.';
    }
    if (msg.includes('must be a locked participant')) {
      return 'You must be a participant to vote.';
    }
    if (msg.includes('already voted')) {
      return "You've already voted. Use your ballot key to edit.";
    }
    if (msg.includes('Invalid ballot token')) {
      return 'Invalid ballot key. You cannot edit this vote.';
    }
    if (msg.includes('cannot vote for yourself')) {
      return 'You cannot vote for yourself.';
    }
    if (msg.includes('same person more than')) {
      return "You've voted for this person too many times.";
    }
    if (msg.includes('Nominee is not in this poll')) {
      return 'That person is not in this poll.';
    }
    if (msg.includes('Invalid category')) {
      return 'Invalid category.';
    }
    if (msg.includes('Cannot view tally while voting is open')) {
      return 'Results are hidden while voting is open.';
    }

    // Fall back to auth errors
    return window.FeralAuth?.friendlyError(error) || msg;
  }

  // Export to window
  window.FeralPoll = {
    // Queries
    getCurrentPoll,
    getPollBySlug,
    getPollStats,
    getParticipants,
    isParticipant,
    hasVoted,

    // Joining
    joinPoll,
    leavePoll,

    // Ideas
    getIdeas,
    submitIdea,
    toggleUpvote,
    looksLikeItNamesSomeone,

    // Voting
    getCategories,
    submitBallot,
    saveBallotToken,
    getBallotToken,
    clearBallotToken,
    downloadBallotKey,
    shuffleArray,
    getShuffleSeed,

    // Admin
    getIdeasAdmin,
    updateIdeaStatus,
    createCategory,
    transitionPollStatus,
    getPollTally,
    saveResults,
    createPoll,
    updatePoll,

    // Helpers
    formatDate,
    formatRelativeTime,
    getPollPhaseLabel,
    friendlyError
  };
})();
