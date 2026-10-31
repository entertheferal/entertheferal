/**
 * Poll hub data module.
 * Abstracts data access - today reads polls.json, later can switch to Supabase.
 */
const FeralPollHub = (function() {
  'use strict';

  let _data = null;
  let _fetchPromise = null;

  // Fetch and cache polls.json
  async function fetchData() {
    if (_data) return _data;
    if (_fetchPromise) return _fetchPromise;

    _fetchPromise = fetch('/poll/polls.json')
      .then(r => {
        if (!r.ok) throw new Error('Failed to load polls data');
        return r.json();
      })
      .then(json => {
        _data = json;
        return _data;
      })
      .catch(err => {
        console.error('FeralPollHub:', err);
        _data = { current: null, polls: [] };
        return _data;
      });

    return _fetchPromise;
  }

  /**
   * Get the current poll (if any).
   * Returns null if between polls.
   */
  async function getCurrentPoll() {
    const data = await fetchData();
    return data.current || null;
  }

  /**
   * Get all published polls (past polls).
   * Each has: slug, title, month, line, art, awards, peopleWithGold, resultsUrl
   */
  async function getPastPolls() {
    const data = await fetchData();
    return data.polls.filter(p => p.status === 'published');
  }

  /**
   * Get member's participation data for past polls.
   * Requires auth. Returns map: { pollSlug: { inPoll, goldCount } }
   * For now returns empty - will be populated when we have live data.
   */
  async function getMemberPollStats(memberId) {
    // Future: fetch from Supabase
    // For now, return empty - no member-specific stats in static mode
    return {};
  }

  /**
   * Get poll phase label for display.
   */
  function getPhaseLabel(status) {
    const labels = {
      'draft': 'draft',
      'ideas_open': 'joining and ideas open',
      'curating': 'picking the final list',
      'voting_open': 'voting open',
      'closed': 'voting closed',
      'published': 'results are up'
    };
    return labels[status] || 'between polls';
  }

  /**
   * Get phase key for state machine ('open', 'curating', 'voting', 'closed', 'results', 'none')
   */
  function getPhaseKey(status) {
    const keys = {
      'ideas_open': 'open',
      'curating': 'curating',
      'voting_open': 'voting',
      'closed': 'closed',
      'published': 'results'
    };
    return keys[status] || 'none';
  }

  return {
    getCurrentPoll,
    getPastPolls,
    getMemberPollStats,
    getPhaseLabel,
    getPhaseKey,
    fetchData
  };
})();

// Make available globally
if (typeof window !== 'undefined') {
  window.FeralPollHub = FeralPollHub;
}
