/**
 * Poll rules data module.
 * Provides poll settings and dates for the rules page.
 * Today uses inline defaults; can switch to Supabase later.
 */
var FeralRulesData = (function() {
  'use strict';

  // Default settings (used when no active poll)
  var DEFAULTS = {
    votes_per_person_per_ballot: 3,
    gold_cap: 3,
    min_votes_for_award: 2,
    max_categories: 20,
    min_categories: 12,
    min_participants: 10,
    ideas_per_member: 3
  };

  // Demo dates (null means hide dates, show "dates are posted when the next poll opens")
  var _currentPoll = null;

  /**
   * Get poll settings. Returns defaults if no active poll.
   */
  function getSettings() {
    if (_currentPoll && _currentPoll.settings) {
      return Object.assign({}, DEFAULTS, _currentPoll.settings);
    }
    return DEFAULTS;
  }

  /**
   * Get poll dates. Returns null if no active poll.
   */
  function getDates() {
    if (!_currentPoll) return null;
    return {
      joinCloses: _currentPoll.join_close_at,
      ideasClose: _currentPoll.ideas_close_at,
      votingOpens: _currentPoll.voting_open_at,
      votingCloses: _currentPoll.voting_close_at
    };
  }

  /**
   * Check if there's an active poll.
   */
  function hasActivePoll() {
    return _currentPoll !== null;
  }

  /**
   * Format a date for display (e.g., "nov 7")
   */
  function formatDate(dateStr) {
    if (!dateStr) return null;
    var d = new Date(dateStr);
    var months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    return months[d.getMonth()] + ' ' + d.getDate();
  }

  /**
   * Set the current poll data (for testing or loading from API)
   */
  function setCurrentPoll(poll) {
    _currentPoll = poll;
  }

  return {
    getSettings: getSettings,
    getDates: getDates,
    hasActivePoll: hasActivePoll,
    formatDate: formatDate,
    setCurrentPoll: setCurrentPoll,
    DEFAULTS: DEFAULTS
  };
})();

if (typeof window !== 'undefined') {
  window.FeralRulesData = FeralRulesData;
}
