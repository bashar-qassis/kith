# Phase 02 Gap Analysis

## Coverage Summary
Phase 02 is well-structured and comprehensive. The plan covers all authentication methods specified in the product spec (email/password, TOTP, WebAuthn, OAuth, API tokens), authorization via Kith.Policy, rate limiting, and session security. Most gaps are minor edge cases or implementation details.

## Gaps Found

1. **Account Suspension / User Deactivation (MEDIUM)**
   - Gap: Product spec implies "user is active" checks in `fetch_api_user`, but Phase 02 has no task covering user deactivation, suspension, or soft-disable mechanisms.
   - Missing: How users become inactive, what "active" means (a boolean column?), whether suspended users can still access recovery flows (password reset, etc.)
   - Impact: Could allow suspended users to regain access via password reset or other flows.

2. **Password Change Session Invalidation Details (MEDIUM)**
   - Gap: TASK-02-03 (Password Reset) states "all existing sessions are invalidated," but Phase 02 has no task for password change from Settings.
   - Missing: (a) Are users allowed to change password from Settings? (b) Does password change also invalidate all sessions like reset does? (c) Is password change rate-limited?
   - Impact: Missing spec could lead to inconsistent session invalidation behavior.

3. **Account Lockout After Failed Login Attempts (LOW)**
   - Gap: Rate limiting is per-IP (10 req/min → 15-min lockout), but no per-account lockout for distributed-IP attacks.
   - Missing: Whether a user account should be locked after N failed password attempts.
   - Impact: IP-based lockout insufficient against distributed attackers.

4. **Session Idle Timeout / Server-Side Expiry (LOW)**
   - Gap: TASK-02-17 states "Sessions have no server-side expiry by default," but spec doesn't clarify idle timeout expectations.
   - Missing: Optional server-side session timeout (e.g., 24h or 30 days). Acceptable for v1 if documented.

5. **Email Verification Bypass via OAuth (LOW)**
   - Gap: TASK-02-02 requires email confirmation for standard signup, but TASK-02-11 (Social OAuth) creates a new Account + User without stating whether OAuth users must verify email.
   - Missing: If a user signs up via GitHub/Google OAuth, are they auto-confirmed?

6. **API Token Revocation / Management (LOW)**
   - Gap: TASK-02-13 creates tokens but no task for users to view, revoke, or rotate API tokens from Settings.
   - Missing: Can users see their issued tokens? Can they revoke a token without logging out all sessions?

7. **Recovery Code Display & Backup Instructions (LOW)**
   - Gap: TASK-02-07 creates and tests recovery codes but doesn't detail the UX for displaying codes after TOTP setup.
   - Missing: Guidance on code format, display method, and recovery instructions.

8. **Remember-Me Cookie Behavior on Password/2FA Change (LOW)**
   - Gap: TASK-02-17 mentions 60-day remember-me cookies but doesn't specify whether password change/2FA disable invalidates them.
   - Missing: Should these long-lived tokens be invalidated on security-sensitive changes?

## No Gaps / Well Covered

- All authentication methods: Email/password, TOTP (pot), WebAuthn (wax), OAuth (assent with PKCE), API bearer tokens — all explicitly tasked
- Rate limiting: Per-IP and per-user limits with exact request/minute and lockout durations (TASK-02-15)
- Policy module: All v1 action atoms defined for Contacts, Notes, Activities, Calls, Life Events, Files, Reminders, Tags, Account, Team-level, and Relationships (TASK-02-21)
- Session security: Encrypted cookies, SameSite=Strict, HttpOnly, HTTPS-only in prod, session token rotation, server-side invalidation on logout (TASK-02-17)
- 2FA flows: TOTP setup/disable, recovery codes, WebAuthn registration/auth, pending 2FA state handled correctly (TASK-02-05 through TASK-02-10)
- Security safeguards: No user enumeration, real IP extraction (RemoteIp), TOTP time-drift, WebAuthn RP ID validation
- Audit logging: Async via Oban for all auth events, append-only table design (TASK-02-22)
- CSRF, secure headers, CSP with nonce-based scripts (TASK-02-19, TASK-02-20)
- Account linking: OAuth link/unlink with "no login method" safety check (TASK-02-12)
- Concurrent sessions: View and revoke individual sessions, logout all other devices (TASK-02-18)
- Signup controls: `DISABLE_SIGNUP` env var, atomic Account+User creation, first user auto-admin (TASK-02-04)
