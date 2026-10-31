// Feral Collective Auth Utilities
// Requires: supabase-config.js to be loaded first, then supabase-js

(function() {
  'use strict';

  // Wait for Supabase to be ready
  let supabase = null;
  let currentUser = null;
  let currentProfile = null;

  function getSupabase() {
    if (!supabase && window.supabase && window.FERAL) {
      supabase = window.supabase.createClient(
        window.FERAL.SUPABASE_URL,
        window.FERAL.SUPABASE_ANON_KEY
      );
    }
    return supabase;
  }

  // Escape HTML to prevent XSS
  function esc(str) {
    if (str == null) return '';
    return String(str).replace(/[&<>"']/g, function(c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // Validate URL is https
  function isValidUrl(url) {
    if (!url) return true;
    try {
      const parsed = new URL(url.startsWith('http') ? url : 'https://' + url);
      return parsed.protocol === 'https:';
    } catch {
      return false;
    }
  }

  // Format joined date
  function formatJoined(dateStr) {
    const d = new Date(dateStr);
    return d.toLocaleDateString('en-US', { month: 'short', year: 'numeric' });
  }

  // Get current session
  async function getSession() {
    const sb = getSupabase();
    if (!sb) return null;
    const { data: { session } } = await sb.auth.getSession();
    return session;
  }

  // Get current user
  async function getUser() {
    const session = await getSession();
    return session?.user || null;
  }

  // Get current user's profile
  async function getProfile() {
    const user = await getUser();
    if (!user) return null;

    const sb = getSupabase();
    const { data, error } = await sb
      .from('profiles')
      .select('*')
      .eq('id', user.id)
      .single();

    if (error) {
      console.error('Error fetching profile:', error);
      return null;
    }
    return data;
  }

  // Check if user is admin
  async function isAdmin() {
    const profile = await getProfile();
    return profile?.is_admin === true;
  }

  // Sign in with OTP (existing users)
  async function signIn(email, redirectTo) {
    const sb = getSupabase();
    const { error } = await sb.auth.signInWithOtp({
      email: email.trim().toLowerCase(),
      options: {
        shouldCreateUser: false,
        emailRedirectTo: redirectTo || (window.location.origin + '/login/')
      }
    });
    return { error };
  }

  // Sign up with OTP (new users with invite code)
  async function signUp(email, inviteCode, handle, displayName) {
    const sb = getSupabase();
    const { error } = await sb.auth.signInWithOtp({
      email: email.trim().toLowerCase(),
      options: {
        shouldCreateUser: true,
        data: {
          invite_code: inviteCode.trim().toUpperCase(),
          handle: handle.trim().toLowerCase(),
          display_name: displayName.trim()
        }
      }
    });
    return { error };
  }

  // Verify OTP code
  async function verifyOtp(email, token) {
    const sb = getSupabase();
    const { data, error } = await sb.auth.verifyOtp({
      email: email.trim().toLowerCase(),
      token: token.trim(),
      type: 'email'
    });
    return { data, error };
  }

  // Sign out
  async function signOut() {
    const sb = getSupabase();
    localStorage.removeItem('feral_session');
    const { error } = await sb.auth.signOut();
    return { error };
  }

  // Check handle availability
  async function checkHandle(handle) {
    const sb = getSupabase();
    const { data, error } = await sb.rpc('handle_available', {
      h: handle.trim().toLowerCase()
    });
    if (error) return false;
    return data === true;
  }

  // Update profile
  async function updateProfile(updates) {
    const user = await getUser();
    if (!user) return { error: { message: 'Not signed in' } };

    const sb = getSupabase();
    const { data, error } = await sb
      .from('profiles')
      .update(updates)
      .eq('id', user.id)
      .select()
      .single();

    return { data, error };
  }

  // Export user data
  async function exportMyData() {
    const sb = getSupabase();
    const { data, error } = await sb.rpc('export_my_data');
    return { data, error };
  }

  // Delete account
  async function deleteMyAccount() {
    const sb = getSupabase();
    const { data, error } = await sb.rpc('delete_my_account');
    return { data, error };
  }

  // Get signed avatar URL
  async function getAvatarUrl(userId, updatedAt) {
    const sb = getSupabase();
    const path = `${userId}/avatar.webp`;
    const { data } = await sb.storage
      .from('avatars')
      .createSignedUrl(path, 3600); // 1 hour
    if (data?.signedUrl) {
      // Add cache buster
      return data.signedUrl + (updatedAt ? '&v=' + new Date(updatedAt).getTime() : '');
    }
    return null;
  }

  // Upload avatar
  async function uploadAvatar(file) {
    const user = await getUser();
    if (!user) return { error: { message: 'Not signed in' } };

    const sb = getSupabase();
    const path = `${user.id}/avatar.webp`;

    const { error } = await sb.storage
      .from('avatars')
      .upload(path, file, {
        contentType: 'image/webp',
        upsert: true
      });

    if (error) return { error };

    // Update profile
    const { error: profileError } = await sb
      .from('profiles')
      .update({
        avatar_type: 'photo',
        avatar_path: path,
        avatar_updated_at: new Date().toISOString()
      })
      .eq('id', user.id);

    return { error: profileError };
  }

  // Remove avatar
  async function removeAvatar() {
    const user = await getUser();
    if (!user) return { error: { message: 'Not signed in' } };

    const sb = getSupabase();

    // Remove from storage
    await sb.storage
      .from('avatars')
      .remove([`${user.id}/avatar.webp`]);

    // Update profile
    const { error } = await sb
      .from('profiles')
      .update({
        avatar_type: 'initial',
        avatar_icon: null,
        avatar_path: null,
        avatar_updated_at: new Date().toISOString()
      })
      .eq('id', user.id);

    return { error };
  }

  // Map error codes to friendly messages
  function friendlyError(error) {
    if (!error) return null;
    const msg = error.message || error.hint || String(error);

    // Auth errors
    if (msg.includes('User not found') || msg.includes('Invalid login credentials')) {
      return 'No account for that email. Need an invite code?';
    }
    if (msg.includes('invalid_invite')) {
      return "That invite code isn't valid, has been used, or has expired.";
    }
    if (msg.includes('handle_taken')) {
      return 'That handle is taken.';
    }
    if (msg.includes('handle_required')) {
      return 'Please choose a handle.';
    }
    if (msg.includes('handle_invalid')) {
      return 'Handle must be 3-20 characters: lowercase letters, numbers, dots, underscores.';
    }
    if (msg.includes('handle_change_rate_limited')) {
      return 'You can only change your handle once every 30 days.';
    }
    if (msg.includes('session_too_old')) {
      return 'Please sign in again to complete this action.';
    }
    if (msg.includes('cannot_delete_last_admin')) {
      return 'You are the only admin. Assign another admin before deleting your account.';
    }
    if (msg.includes('admin_required')) {
      return 'This action requires admin access.';
    }
    if (msg.includes('rate limit') || msg.includes('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }

    return msg;
  }

  // Redirect if not authenticated
  async function requireAuth(redirectTo) {
    const user = await getUser();
    if (!user) {
      window.location.href = redirectTo || '/login';
      return false;
    }
    return true;
  }

  // Redirect if not admin
  async function requireAdmin(redirectTo) {
    const admin = await isAdmin();
    if (!admin) {
      window.location.href = redirectTo || '/';
      return false;
    }
    return true;
  }

  // Render header
  async function renderHeader(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    const user = await getUser();
    const profile = user ? await getProfile() : null;

    let menuHtml = '';
    if (user && profile) {
      menuHtml = `
        <nav class="header-menu" aria-label="User menu">
          <a href="/u/${esc(profile.handle)}">My profile</a>
          <a href="/calendar">Calendar</a>
          <a href="/settings">Settings</a>
          <button type="button" id="signOutBtn">Sign out</button>
        </nav>
      `;
    } else {
      menuHtml = `<a href="/login" class="header-signin">Sign in</a>`;
    }

    container.innerHTML = `
      <a href="/" class="header-mark">the Feral Collective</a>
      ${menuHtml}
    `;

    // Sign out handler
    const signOutBtn = document.getElementById('signOutBtn');
    if (signOutBtn) {
      signOutBtn.addEventListener('click', async () => {
        await signOut();
        window.location.href = '/';
      });
    }
  }

  // Render footer
  function renderFooter(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    container.innerHTML = `
      <nav class="footer-links">
        <a href="/privacy">Privacy</a>
        <a href="/guidelines">Guidelines</a>
        <a href="/terms">Terms</a>
        <a href="mailto:[PRIVACY_EMAIL]">Contact</a>
      </nav>
    `;
  }

  // Export to window
  window.FeralAuth = {
    getSupabase,
    getSession,
    getUser,
    getProfile,
    isAdmin,
    signIn,
    signUp,
    verifyOtp,
    signOut,
    checkHandle,
    updateProfile,
    exportMyData,
    deleteMyAccount,
    getAvatarUrl,
    uploadAvatar,
    removeAvatar,
    friendlyError,
    requireAuth,
    requireAdmin,
    renderHeader,
    renderFooter,
    esc,
    isValidUrl,
    formatJoined
  };
})();
